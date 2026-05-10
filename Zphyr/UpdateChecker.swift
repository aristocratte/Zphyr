//
//  UpdateChecker.swift
//  Zphyr
//

import Foundation
import AppKit
import CryptoKit
import Security
import os

@Observable @MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State {
        case idle
        case checking
        case updateAvailable(version: String, downloadURL: URL)
        case downloading(progress: Double)
        case installing
        case upToDate
        case failed(String)

        var hasUpdate: Bool {
            switch self {
            case .updateAvailable, .downloading, .installing: return true
            default: return false
            }
        }

        var latestVersion: String? {
            if case .updateAvailable(let v, _) = self { return v }
            return nil
        }

        var downloadProgress: Double? {
            if case .downloading(let p) = self { return p }
            return nil
        }
    }

    enum ReleaseChannel {
        case stable
        case includePrerelease
    }

    private static let maxDMGBytes: Int64 = 500 * 1_024 * 1_024

    private enum UpdateCheckError: LocalizedError {
        case invalidRepositoryURL
        case invalidResponse
        case httpStatus(Int, message: String?)
        case decodeFailed
        case noCompatibleAsset(String)
        case invalidDownloadURL(String)
        case installPreflightFailed(String)
        case missingDigest(String)
        case sizeExceeded(Int64)
        case integrityMismatch
        case codeSignatureInvalid(String)
        case unsafeInstallPath(String)

        var errorDescription: String? {
            switch self {
            case .invalidRepositoryURL:
                return "Update source is misconfigured."
            case .invalidResponse:
                return "Unexpected response from update server."
            case .httpStatus(let code, let message):
                if let message, !message.isEmpty {
                    return "Update check failed (\(code)): \(message)"
                }
                return "Update check failed with HTTP status \(code)."
            case .decodeFailed:
                return "Could not parse release metadata from GitHub."
            case .noCompatibleAsset(let version):
                return "No compatible DMG asset was found for release \(version)."
            case .invalidDownloadURL(let version):
                return "Release \(version) has an invalid download URL."
            case .installPreflightFailed(let message):
                return message
            case .missingDigest(let version):
                return "Release \(version) is missing an integrity digest. Refusing to install."
            case .sizeExceeded(let bytes):
                let mb = Double(bytes) / 1_048_576
                return String(format: "Update payload of %.0f MB exceeds the safety cap.", mb)
            case .integrityMismatch:
                return "Downloaded update failed integrity verification."
            case .codeSignatureInvalid(let detail):
                return "Update signature check failed: \(detail)"
            case .unsafeInstallPath(let path):
                return "Update install path contains unsupported characters: \(path)"
            }
        }
    }

    private(set) var state: State = .idle

    private let repoOwner = "aristocratte"
    private let repoName  = "Zphyr"
    private let releaseChannel: ReleaseChannel
    private let urlSession: URLSession
    private let fileManager: FileManager
    private let appBundle: Bundle
    private let log = Logger(subsystem: "com.zphyr.app", category: "UpdateChecker")
    private var pendingAssetSHA256: String?

    private init(
        releaseChannel: ReleaseChannel = .stable,
        urlSession: URLSession = .shared,
        fileManager: FileManager = .default,
        appBundle: Bundle = .main
    ) {
        self.releaseChannel = releaseChannel
        self.urlSession = urlSession
        self.fileManager = fileManager
        self.appBundle = appBundle
    }

    // MARK: - Public API

    func checkInBackground() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await check()
        }
    }

    func downloadAndInstall() {
        guard case .updateAvailable(let version, let url) = state else { return }
        guard let expectedSHA256 = pendingAssetSHA256 else {
            log.error("[Updater] refusing install: release has no SHA256 digest")
            state = .failed(UpdateCheckError.missingDigest(version).localizedDescription)
            return
        }
        Task { await performInstall(from: url, expectedSHA256: expectedSHA256) }
    }

    // MARK: - Check

    private func check() async {
        state = .checking
        do {
            pendingAssetSHA256 = nil
            let releases = try await fetchReleases()
            guard let release = Self.preferredRelease(from: releases, channel: releaseChannel) else {
                state = .upToDate
                return
            }

            let latestRaw = Self.normalizedVersionTag(release.tagName)
            let current = appVersionString()
            guard Self.isNewerVersion(latestRaw, than: current) else {
                state = .upToDate
                return
            }

            guard let asset = Self.preferredDMGAsset(
                from: release.assets,
                architectureHint: Self.currentArchitectureHint()
            ) else {
                throw UpdateCheckError.noCompatibleAsset(latestRaw)
            }
            guard let url = URL(string: asset.browserDownloadURL) else {
                throw UpdateCheckError.invalidDownloadURL(latestRaw)
            }

            pendingAssetSHA256 = Self.normalizedSHA256(from: asset.digest)
            state = .updateAvailable(version: latestRaw, downloadURL: url)
        } catch let error as UpdateCheckError {
            log.error("[Updater] check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        } catch {
            log.error("[Updater] check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("Update check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Download & Install

    private func performInstall(from downloadURL: URL, expectedSHA256: String) async {
        state = .downloading(progress: 0)

        // Stage everything inside an app-private directory (mode 0700) so other
        // processes cannot read or race-replace the staged bundle / installer.
        let stagingRoot: URL
        do {
            stagingRoot = try Self.makeStagingDirectory(fileManager: fileManager)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let dmgDest = stagingRoot.appendingPathComponent("ZphyrUpdate.dmg")
        let mountPoint = stagingRoot.appendingPathComponent("mount")
        var didMount = false

        defer {
            if didMount {
                Self.detachDiskImage(at: mountPoint)
            }
            try? fileManager.removeItem(at: stagingRoot)
        }

        do {
            // 1. Download DMG (size-capped)
            let (tmpFile, _) = try await urlSession.download(from: downloadURL)
            try? fileManager.removeItem(at: dmgDest)
            try fileManager.moveItem(at: tmpFile, to: dmgDest)

            let attrs = try fileManager.attributesOfItem(atPath: dmgDest.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size <= Self.maxDMGBytes else {
                throw UpdateCheckError.sizeExceeded(size)
            }
            state = .downloading(progress: 0.45)

            // 2. Verify SHA256 BEFORE we touch hdiutil. Mounting an unverified
            //    DMG is needless attack surface (License.plist triggers, etc.).
            let fileSHA256 = try Self.sha256Hex(for: dmgDest)
            guard fileSHA256 == expectedSHA256 else {
                throw UpdateCheckError.integrityMismatch
            }
            state = .downloading(progress: 0.60)

            // 3. Mount DMG
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let mount = Process()
            mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mount.arguments = ["attach", dmgDest.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
            mount.environment = Self.scrubbedEnvironment()
            try mount.run(); mount.waitUntilExit()
            guard mount.terminationStatus == 0 else {
                state = .failed("Could not mount update image")
                return
            }
            didMount = true
            state = .downloading(progress: 0.75)

            // 4. Copy new .app to staging
            let entries = try fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let newApp = Self.preferredAppBundle(from: entries) else {
                state = .failed("App bundle not found in update")
                return
            }
            let tempApp = stagingRoot.appendingPathComponent("ZphyrNew.app")
            try? fileManager.removeItem(at: tempApp)
            try fileManager.copyItem(at: newApp, to: tempApp)
            state = .downloading(progress: 0.85)

            // 5. Verify the staged bundle's code signature and that its Team ID
            //    matches the currently running app — refuses unsigned builds and
            //    swaps from a different developer.
            try Self.verifyStagedAppSignature(stagedApp: tempApp, currentBundle: appBundle)
            state = .downloading(progress: 0.95)

            // 6. Unmount before we hand control to the installer
            Self.detachDiskImage(at: mountPoint)
            didMount = false

            state = .installing

            // 7. Write installer to the same private staging dir (mode 0700)
            let currentApp = appBundle.bundleURL
            if let preflightError = Self.installPreflightError(for: currentApp, fileManager: fileManager) {
                throw UpdateCheckError.installPreflightFailed(preflightError)
            }
            // Reject paths whose shell-quoted form is ambiguous; we hard-fail
            // rather than try to escape every edge case in bash.
            for path in [currentApp.path, tempApp.path, dmgDest.path, stagingRoot.path] {
                guard Self.isShellSafePath(path) else {
                    throw UpdateCheckError.unsafeInstallPath(path)
                }
            }

            let scriptURL = stagingRoot.appendingPathComponent("zphyr_install.sh")
            let script = Self.buildInstallerScript(
                currentAppPath: currentApp.path,
                stagedAppPath: tempApp.path,
                dmgPath: dmgDest.path,
                stagingPath: stagingRoot.path
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let installer = Process()
            installer.executableURL = URL(fileURLWithPath: "/bin/bash")
            installer.arguments = [scriptURL.path]
            installer.environment = Self.scrubbedEnvironment()
            try installer.run()

            // Quit so the script can replace us
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)

        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Release fetching

    private func fetchReleases() async throws -> [GitHubRelease] {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=20") else {
            throw UpdateCheckError.invalidRepositoryURL
        }
        var request = URLRequest(url: apiURL, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Zphyr/\(appVersionString())", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateCheckError.httpStatus(http.statusCode, message: Self.apiErrorMessage(from: data))
        }

        guard let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) else {
            throw UpdateCheckError.decodeFailed
        }
        return releases
    }

    private func appVersionString() -> String {
        (appBundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // MARK: - Version comparison

    private nonisolated static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        compareVersionStrings(candidate, current) == .orderedDescending
    }

    private nonisolated static func compareVersionStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = SemanticVersion(raw: lhs), let right = SemanticVersion(raw: rhs) else {
            return fallbackNumericCompare(lhs, rhs)
        }
        if left == right { return .orderedSame }
        return left > right ? .orderedDescending : .orderedAscending
    }

    private nonisolated static func fallbackNumericCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = numericParts(normalizedVersionTag(lhs))
        let b = numericParts(normalizedVersionTag(rhs))
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return .orderedDescending }
            if av < bv { return .orderedAscending }
        }
        return .orderedSame
    }

    private nonisolated static func numericParts(_ version: String) -> [Int] {
        version.components(separatedBy: ".").compactMap { Int($0) }
    }

    fileprivate nonisolated static func normalizedVersionTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    // MARK: - Release and asset selection

    private nonisolated static func preferredRelease(from releases: [GitHubRelease], channel: ReleaseChannel) -> GitHubRelease? {
        let eligible = releases.filter { release in
            guard !release.draft else { return false }
            if channel == .stable && isPrereleaseRelease(release) { return false }
            return true
        }
        guard !eligible.isEmpty else { return nil }

        return eligible.max { lhs, rhs in
            let compare = compareVersionStrings(
                normalizedVersionTag(lhs.tagName),
                normalizedVersionTag(rhs.tagName)
            )
            if compare == .orderedSame {
                return (lhs.publishedAt ?? "") < (rhs.publishedAt ?? "")
            }
            return compare == .orderedAscending
        }
    }

    private nonisolated static func preferredDMGAsset(from assets: [GitHubAsset], architectureHint: String) -> GitHubAsset? {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard !dmgAssets.isEmpty else { return nil }

        let scored: [(asset: GitHubAsset, score: Int)] = dmgAssets.map { asset in
            (asset: asset, score: score(assetName: asset.name, architectureHint: architectureHint))
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let leftDownloads = lhs.asset.downloadCount ?? 0
            let rightDownloads = rhs.asset.downloadCount ?? 0
            if leftDownloads != rightDownloads { return leftDownloads > rightDownloads }
            return lhs.asset.name.localizedCaseInsensitiveCompare(rhs.asset.name) == .orderedAscending
        }

        guard let top = sorted.first else { return nil }
        if sorted.count > 1 {
            let second = sorted[1]
            let tieOnScore = top.score == second.score
            let tieOnDownloads = (top.asset.downloadCount ?? 0) == (second.asset.downloadCount ?? 0)
            if tieOnScore && tieOnDownloads {
                return nil
            }
        }
        return top.asset
    }

    private nonisolated static func isPrereleaseRelease(_ release: GitHubRelease) -> Bool {
        if release.prerelease {
            return true
        }
        guard let version = SemanticVersion(raw: normalizedVersionTag(release.tagName)) else {
            return false
        }
        return version.isPrerelease
    }

    private nonisolated static func score(assetName: String, architectureHint: String) -> Int {
        let name = assetName.lowercased()
        var score = 0
        if name.contains("zphyr") { score += 40 }
        if name.hasSuffix(".dmg") { score += 5 }
        if name.contains("release") { score += 8 }
        if name.contains("universal") { score += 24 }
        if name.contains("debug") { score -= 30 }
        if name.contains("symbols") { score -= 40 }

        let armTokens = ["arm64", "aarch64", "apple-silicon"]
        let intelTokens = ["x86_64", "intel"]
        let hasArmToken = armTokens.contains { name.contains($0) }
        let hasIntelToken = intelTokens.contains { name.contains($0) }

        if architectureHint == "arm64" {
            if hasArmToken { score += 30 }
            if hasIntelToken { score -= 35 }
        } else if architectureHint == "x86_64" {
            if hasIntelToken { score += 30 }
            if hasArmToken { score -= 35 }
        }
        if !hasArmToken && !hasIntelToken { score += 3 }
        return score
    }

    private nonisolated static func preferredAppBundle(from entries: [URL]) -> URL? {
        let apps = entries.filter { $0.pathExtension == "app" }
        guard !apps.isEmpty else { return nil }
        if let exact = apps.first(where: { $0.lastPathComponent.lowercased() == "zphyr.app" }) {
            return exact
        }
        return apps.count == 1 ? apps[0] : nil
    }

    // MARK: - Install safety helpers

    private nonisolated static func installPreflightError(for currentApp: URL, fileManager: FileManager) -> String? {
        if isLikelyTranslocated(path: currentApp.path) {
            return "Move Zphyr to /Applications before installing updates."
        }
        let parentPath = currentApp.deletingLastPathComponent().path
        guard fileManager.isWritableFile(atPath: parentPath) else {
            return "Insufficient write permissions in \(parentPath). Move Zphyr to a writable location."
        }
        return nil
    }

    private nonisolated static func isLikelyTranslocated(path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }

    private nonisolated static func buildInstallerScript(
        currentAppPath: String,
        stagedAppPath: String,
        dmgPath: String,
        stagingPath: String
    ) -> String {
        // Paths are validated to be shell-safe before this is called.
        // The whole staging dir is removed at the end so no per-file cleanup is needed.
        """
        #!/bin/bash
        set -u
        export PATH=/usr/bin:/bin
        sleep 1.5
        CURRENT_APP="\(currentAppPath)"
        STAGED_APP="\(stagedAppPath)"
        STAGING_DIR="\(stagingPath)"
        BACKUP_APP="${CURRENT_APP}.backup.$$"

        cleanup() {
          rm -rf "$STAGING_DIR"
        }

        if [ ! -d "$STAGED_APP" ]; then
          cleanup
          exit 11
        fi

        if [ -e "$CURRENT_APP" ]; then
          mv "$CURRENT_APP" "$BACKUP_APP" || { cleanup; exit 12; }
        fi

        if /usr/bin/ditto "$STAGED_APP" "$CURRENT_APP"; then
          rm -rf "$BACKUP_APP"
          cleanup
          /usr/bin/open "$CURRENT_APP"
          exit 0
        fi

        rm -rf "$CURRENT_APP"
        if [ -e "$BACKUP_APP" ]; then
          mv "$BACKUP_APP" "$CURRENT_APP"
        fi
        cleanup
        exit 13
        """
    }

    // MARK: - Sandboxed staging directory

    /// Creates an app-private directory under `Application Support/` with mode 0700.
    /// Used for download/staging so other processes cannot read the staged bundle
    /// or race-replace the installer script.
    private nonisolated static func makeStagingDirectory(fileManager: FileManager) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "com.zphyr.app"
        let root = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        return root
    }

    /// Strict allow-list to keep update paths safe to embed in a bash heredoc.
    /// Permits letters, digits, `/ . _ - + : @` and space. Rejects `"`, `$`, `` ` ``, `\`, etc.
    nonisolated static func isShellSafePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._- +:@")
        return path.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Minimal env passed to spawned helpers. Drops `DYLD_*`, custom `$PATH`,
    /// and anything else inherited from the GUI session that an attacker could
    /// pre-set via `launchctl setenv`.
    private nonisolated static func scrubbedEnvironment() -> [String: String] {
        var env: [String: String] = ["PATH": "/usr/bin:/bin"]
        if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
        if let user = ProcessInfo.processInfo.environment["USER"] { env["USER"] = user }
        return env
    }

    // MARK: - Code signature verification of the staged bundle

    private nonisolated static func verifyStagedAppSignature(stagedApp: URL, currentBundle: Bundle) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(stagedApp as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw UpdateCheckError.codeSignatureInvalid("could not read signature (\(createStatus))")
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        let validateStatus = SecStaticCodeCheckValidity(code, flags, nil)
        if validateStatus != errSecSuccess {
            throw UpdateCheckError.codeSignatureInvalid("validity check failed (\(validateStatus))")
        }

        let stagedTeamID = try teamIdentifier(for: code)
        let currentTeamID = teamIdentifier(forRunning: currentBundle)
        guard let stagedTeamID, !stagedTeamID.isEmpty else {
            throw UpdateCheckError.codeSignatureInvalid("staged bundle has no Team ID")
        }
        if let currentTeamID, !currentTeamID.isEmpty, currentTeamID != stagedTeamID {
            throw UpdateCheckError.codeSignatureInvalid(
                "Team ID mismatch (current=\(currentTeamID), staged=\(stagedTeamID))"
            )
        }
    }

    private nonisolated static func teamIdentifier(for code: SecStaticCode) throws -> String? {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw UpdateCheckError.codeSignatureInvalid("could not read signing info (\(status))")
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private nonisolated static func teamIdentifier(forRunning bundle: Bundle) -> String? {
        guard let url = bundle.bundleURL as CFURL? else { return nil }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private nonisolated static func detachDiskImage(at mountPoint: URL) {
        let unmount = Process()
        unmount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        unmount.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
        try? unmount.run()
        unmount.waitUntilExit()
    }

    private nonisolated static func apiErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? String
        else {
            return nil
        }
        return message
    }

    private nonisolated static func normalizedSHA256(from digest: String?) -> String? {
        guard let digest else { return nil }
        let lower = digest.lowercased()
        if lower.hasPrefix("sha256:") {
            let value = String(lower.dropFirst("sha256:".count))
            return value.count == 64 ? value : nil
        }
        return lower.count == 64 ? lower : nil
    }

    private nonisolated static func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func currentArchitectureHint() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    // MARK: - Tests

    nonisolated static func _test_isNewerVersion(_ candidate: String, than current: String) -> Bool {
        isNewerVersion(candidate, than: current)
    }

    nonisolated static func _test_preferredReleaseTag(
        from releases: [GitHubRelease],
        includePrerelease: Bool
    ) -> String? {
        let channel: ReleaseChannel = includePrerelease ? .includePrerelease : .stable
        return preferredRelease(from: releases, channel: channel)?.tagName
    }

    nonisolated static func _test_preferredDMGAssetName(
        from assets: [GitHubAsset],
        architectureHint: String
    ) -> String? {
        preferredDMGAsset(from: assets, architectureHint: architectureHint)?.name
    }
}

private struct SemanticVersion: Comparable {
    private enum Identifier: Comparable {
        case numeric(Int)
        case text(String)

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case (.numeric(let l), .numeric(let r)):
                return l < r
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case (.text(let l), .text(let r)):
                return l < r
            }
        }
    }

    private let numbers: [Int]
    private let prerelease: [Identifier]

    var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    init?(raw: String) {
        let normalized = UpdateChecker.normalizedVersionTag(raw)
        let noBuildMetadata = normalized.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let mainAndPrerelease = noBuildMetadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericTokens = mainAndPrerelease[0].split(separator: ".")
        let parsedNumbers = numericTokens.compactMap { Int($0) }
        guard !parsedNumbers.isEmpty, parsedNumbers.count == numericTokens.count else {
            return nil
        }
        self.numbers = parsedNumbers

        if mainAndPrerelease.count > 1 {
            let prereleaseTokens = mainAndPrerelease[1].split(separator: ".")
            self.prerelease = prereleaseTokens.map { token in
                if let value = Int(token) {
                    return .numeric(value)
                }
                return .text(String(token).lowercased())
            }
        } else {
            self.prerelease = []
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }

        let leftIsPrerelease = !lhs.prerelease.isEmpty
        let rightIsPrerelease = !rhs.prerelease.isEmpty
        if leftIsPrerelease != rightIsPrerelease {
            return leftIsPrerelease
        }

        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return true }
            guard index < rhs.prerelease.count else { return false }
            if lhs.prerelease[index] != rhs.prerelease[index] {
                return lhs.prerelease[index] < rhs.prerelease[index]
            }
        }
        return false
    }
}

// MARK: - GitHub API models

struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let downloadCount: Int?
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case downloadCount = "download_count"
        case digest
    }
}
