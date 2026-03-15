//
//  UpdateChecker.swift
//  Zphyr
//

import Foundation
import AppKit

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

    private(set) var state: State = .idle

    private let repoOwner = "aristocratte"
    private let repoName  = "Zphyr"

    private init() {}

    // MARK: - Public API

    func checkInBackground() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await check()
        }
    }

    func downloadAndInstall() {
        guard case .updateAvailable(_, let url) = state else { return }
        Task { await performInstall(from: url) }
    }

    // MARK: - Check

    private func check() async {
        state = .checking
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            state = .idle; return
        }
        do {
            var req = URLRequest(url: apiURL, timeoutInterval: 10)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .upToDate; return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestRaw = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard isNewer(latestRaw, than: current) else { state = .upToDate; return }

            if let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
               let url   = URL(string: asset.browserDownloadURL) {
                state = .updateAvailable(version: latestRaw, downloadURL: url)
            } else {
                state = .upToDate
            }
        } catch {
            state = .idle
        }
    }

    // MARK: - Download & Install

    private func performInstall(from downloadURL: URL) async {
        state = .downloading(progress: 0)
        let tmp = FileManager.default.temporaryDirectory
        let dmgDest = tmp.appendingPathComponent("ZphyrUpdate.dmg")

        do {
            // 1. Download DMG
            let (tmpFile, _) = try await URLSession.shared.download(from: downloadURL)
            try? FileManager.default.removeItem(at: dmgDest)
            try FileManager.default.moveItem(at: tmpFile, to: dmgDest)
            state = .downloading(progress: 0.6)

            // 2. Mount DMG
            let mountPoint = tmp.appendingPathComponent("ZphyrMount_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let mount = Process()
            mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mount.arguments = ["attach", dmgDest.path, "-mountpoint", mountPoint.path,
                               "-nobrowse", "-quiet", "-noverify"]
            try mount.run(); mount.waitUntilExit()
            guard mount.terminationStatus == 0 else {
                state = .failed("Could not mount update image"); return
            }
            state = .downloading(progress: 0.80)

            // 3. Copy new .app to temp
            let entries = try FileManager.default.contentsOfDirectory(at: mountPoint,
                                                                       includingPropertiesForKeys: nil)
            guard let newApp = entries.first(where: { $0.pathExtension == "app" }) else {
                state = .failed("App bundle not found in update"); return
            }
            let tempApp = tmp.appendingPathComponent("ZphyrNew.app")
            try? FileManager.default.removeItem(at: tempApp)
            try FileManager.default.copyItem(at: newApp, to: tempApp)
            state = .downloading(progress: 0.95)

            // 4. Unmount
            let unmount = Process()
            unmount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            unmount.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            try? unmount.run(); unmount.waitUntilExit()

            state = .installing

            // 5. Write shell script that replaces app after we quit, then relaunches
            let currentApp = Bundle.main.bundleURL
            let script = """
            #!/bin/bash
            sleep 1.5
            rm -rf \"\(currentApp.path)\"
            cp -R \"\(tempApp.path)\" \"\(currentApp.path)\"
            open \"\(currentApp.path)\"
            rm -rf \"\(tempApp.path)\"
            rm -f \"\(dmgDest.path)\"
            """
            let scriptURL = tmp.appendingPathComponent("zphyr_install.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: scriptURL.path)
            let installer = Process()
            installer.executableURL = URL(fileURLWithPath: "/bin/bash")
            installer.arguments = [scriptURL.path]
            try installer.run()

            // Quit so the script can replace us
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)

        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Version comparison

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numericParts(candidate)
        let b = numericParts(current)
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }

    private func numericParts(_ version: String) -> [Int] {
        let stripped = version.components(separatedBy: "-").first ?? version
        return stripped.components(separatedBy: ".").compactMap { Int($0) }
    }
}

// MARK: - GitHub API models

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
