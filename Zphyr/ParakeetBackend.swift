//
//  ParakeetBackend.swift
//  Zphyr
//
//  ASR backend using Parakeet TDT v3 0.6B from mlx-community.
//  Model (~640 MB) is downloaded from HuggingFace Hub.
//
//  ─── ENABLING NATIVE INFERENCE ──────────────────────────────────────────────
//  Transcription currently falls back to Apple Speech Analyzer.
//  To enable native Parakeet MLX inference, add one of the following
//  Swift Packages in Xcode → File → Add Package Dependencies:
//
//  Option A (MLX, archived but functional):
//    URL: https://github.com/FluidInference/swift-parakeet-mlx
//    Then implement the #if canImport(ParakeetMLX) branch below.
//
//  Option B (CoreML/ANE, recommended, actively maintained):
//    URL: https://github.com/FluidInference/FluidAudio
//    Then implement the #if canImport(FluidAudio) branch below.
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import os

// MARK: - Download delegate (gives real-time byte progress for large files)

private final class HFDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    private var continuation: CheckedContinuation<URL, Error>?

    func setContinuation(_ c: CheckedContinuation<URL, Error>) { continuation = c }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The system deletes `location` as soon as this method returns,
        // so we must move the file to a stable path before resuming.
        do {
            let stable = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: stable)
            continuation?.resume(returning: stable)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - ParakeetBackend

/// Singleton for Parakeet TDT v3 0.6B ASR backend.
/// Downloads model files from mlx-community/parakeet-tdt-0.6b-v3.
/// Until native Swift/MLX inference is integrated, transcription delegates
/// to Apple Speech Analyzer automatically via ASROrchestrator fallback.
@Observable
@MainActor
final class ParakeetBackend: ASRService {

    static let shared = ParakeetBackend()
    static let isRuntimeSupported: Bool = true

    // MARK: - Config
    private static let modelRepo  = "mlx-community/parakeet-tdt-0.6b-v3"
    private static let cacheDir   = "mlx-community/parakeet-tdt-0.6b-v3"
    private static let approxSize: Int64 = 640 * 1_024 * 1_024

    let descriptor = ASRBackendDescriptor(
        kind: .parakeet,
        displayName: "Parakeet v3 0.6B",
        requiresModelInstall: true,
        modelSizeLabel: "~640 MB",
        onboardingSubtitle: "Parakeet v3 s'installe une seule fois (~640 Mo). 25 langues, 100% local via MLX.",
        approxModelBytes: 640 * 1_024 * 1_024
    )

    // MARK: - Observable state
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = nil
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    var isPaused: Bool           = false
    private(set) var isLoaded: Bool = false
    var installPath: String? { Self.resolveInstallURL()?.path }

    private var installTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.zphyr.app", category: "ParakeetASR")

    // Speed tracking
    private var lastBytes: Int64   = 0
    private var lastSpeedTime: Date = .distantPast

    // MARK: - Init
    private init() {
        let onDisk = Self.resolveInstallURL() != nil
        if AppState.shared.parakeetInstalled != onDisk {
            AppState.shared.parakeetInstalled = onDisk
        }
    }

    // MARK: - Install path

    static func resolveInstallURL() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/models/\(cacheDir)")
        guard FileManager.default.fileExists(atPath: base.path) else { return nil }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let valid = contents.contains { $0.pathExtension == "safetensors" || $0.lastPathComponent == "config.json" }
        return valid ? base : nil
    }

    // MARK: - Installation

    func installModel() async {
        guard !isInstalling else { return }
        isInstalling     = true
        installError     = nil
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""
        lastBytes        = 0
        lastSpeedTime    = Date()

        let task = Task<Void, Never> {
            do {
                try await downloadModel()
                if !Task.isCancelled {
                    if Self.resolveInstallURL() != nil {
                        self.isLoaded         = true
                        self.downloadProgress = 1.0
                        self.downloadSpeed    = ""
                        self.downloadedMB     = ""
                        AppState.shared.parakeetInstalled = true
                        self.log.notice("[ParakeetASR] installation complete")
                    } else {
                        self.installError = "Téléchargement incomplet — réessayez."
                        self.log.error("[ParakeetASR] files missing after download")
                    }
                }
            } catch is CancellationError {
                self.log.notice("[ParakeetASR] install cancelled")
            } catch {
                if !Task.isCancelled {
                    self.installError = error.localizedDescription
                    self.log.error("[ParakeetASR] install error: \(error.localizedDescription, privacy: .public)")
                }
            }
            self.isInstalling = false
            self.installTask  = nil
        }
        installTask = task
        await task.value
    }

    // MARK: - Download logic

    private struct HFFileEntry: Decodable {
        let path: String
        let size: Int64?
        let type: String?
    }

    private func downloadModel() async throws {
        // 1. Fetch file list from HuggingFace Hub API
        let apiURL = URL(string: "https://huggingface.co/api/models/\(Self.modelRepo)/tree/main")!
        let (listData, _) = try await URLSession.shared.data(from: apiURL)
        guard !Task.isCancelled else { throw CancellationError() }

        let allEntries = try JSONDecoder().decode([HFFileEntry].self, from: listData)
        let files = allEntries.filter { $0.type != "directory" }
        let totalBytes = files.compactMap(\.size).reduce(0, +).clamped(to: 1...)

        // 2. Prepare destination directory
        let destDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/models/\(Self.cacheDir)")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // 3. Download each file (skip if already on disk with matching size)
        var downloadedBytes: Int64 = 0
        for file in files {
            guard !Task.isCancelled else { throw CancellationError() }

            while isPaused {
                guard !Task.isCancelled else { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(300))
            }

            let dest = destDir.appendingPathComponent(file.path)
            let parent = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            // Skip already downloaded files
            if let existingSize = (try? dest.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
               let expectedSize = file.size, Int64(existingSize) >= expectedSize * 95 / 100 {
                downloadedBytes += file.size ?? 0
                updateProgress(downloaded: downloadedBytes, total: totalBytes)
                log.notice("[ParakeetASR] skip (cached): \(file.path, privacy: .public)")
                continue
            }

            let fileURL = URL(string: "https://huggingface.co/\(Self.modelRepo)/resolve/main/\(file.path)")!
            log.notice("[ParakeetASR] downloading: \(file.path, privacy: .public) (\((file.size ?? 0) / 1_024) KB)")

            let fileOffsetBeforeDownload = downloadedBytes
            let tmpURL = try await downloadWithProgress(
                from: fileURL,
                fileOffset: fileOffsetBeforeDownload,
                totalBytes: totalBytes
            )
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: tmpURL)
                throw CancellationError()
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            downloadedBytes += file.size ?? 0
            updateProgress(downloaded: downloadedBytes, total: totalBytes)
        }
    }

    /// Downloads a single file using URLSessionDownloadTask for real-time progress.
    private func downloadWithProgress(
        from url: URL,
        fileOffset: Int64,
        totalBytes: Int64
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = HFDownloadDelegate()
            delegate.setContinuation(continuation)
            delegate.onProgress = { [weak self] writtenInFile, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateProgress(
                        downloaded: fileOffset + writtenInFile,
                        total: totalBytes
                    )
                }
            }
            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
            session.downloadTask(with: url).resume()
        }
    }

    private func updateProgress(downloaded: Int64, total: Int64) {
        downloadProgress = total > 0 ? Double(downloaded) / Double(total) : 0
        let now = Date()
        let dt  = now.timeIntervalSince(lastSpeedTime)
        if dt >= 0.6 {
            let delta = downloaded - lastBytes
            let bps   = dt > 0 && delta > 0 ? Double(delta) / dt : 0
            downloadSpeed = bps > 0 ? Self.formatSpeed(bps) : ""
            downloadedMB  = String(format: "%.0f / %.0f MB",
                Double(downloaded) / 1_048_576, Double(total) / 1_048_576)
            lastBytes     = downloaded
            lastSpeedTime = now
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask      = nil
        isInstalling     = false
        isPaused         = false
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""
        log.notice("[ParakeetASR] install cancelled by user")
    }

    func pauseInstall()  { isPaused = true;  downloadSpeed = "" }
    func resumeInstall() { isPaused = false }

    // MARK: - Loading

    func loadIfInstalled() async {
        guard AppState.shared.parakeetInstalled, !isLoaded else { return }
        if Self.resolveInstallURL() != nil {
            isLoaded = true
            log.notice("[ParakeetASR] model files found on disk — ready")
        } else {
            AppState.shared.parakeetInstalled = false
            log.notice("[ParakeetASR] flagged installed but files missing — reset")
        }
    }

    func uninstallModel() {
        if let url = Self.resolveInstallURL() {
            try? FileManager.default.removeItem(at: url)
        }
        isLoaded = false
        AppState.shared.parakeetInstalled = false
        log.notice("[ParakeetASR] model uninstalled")
    }

    // MARK: - Transcription

    var transcriptionSupport: ASRTranscriptionSupport {
        ASRTranscriptionSupport(mode: .finalOnly, supportsCancellation: false, supportsRetryFromBuffer: false)
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        guard isLoaded else { throw ASRBackendError.notLoaded("Parakeet model not loaded.") }

        // ── Native MLX inference — NOT YET IMPLEMENTED ─────────────────────
        // The model files are present on disk at Self.resolveInstallURL().
        //
        // To enable transcription, add one of these Swift Packages in Xcode:
        //   • FluidInference/swift-parakeet-mlx  (MLX, Swift-native)
        //   • FluidInference/FluidAudio           (CoreML/ANE, recommended)
        //
        // Then implement the inference below:
        //
        // import ParakeetMLX   // (swift-parakeet-mlx)
        // let model = try ParakeetModel(directory: Self.resolveInstallURL()!)
        // return try await model.transcribe(audioBuffer: audioBuffer)
        //
        // The ASROrchestrator will automatically fall back to Apple Speech
        // Analyzer when this error is thrown, so dictation keeps working.
        throw ASRBackendError.unsupported(
            "Parakeet: fichiers installés. Ajoutez FluidInference/swift-parakeet-mlx dans Xcode pour activer la transcription."
        )
    }

    // MARK: - Helpers

    private static func formatSpeed(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        return String(format: "%.0f KB/s", bps / 1_024)
    }
}

// MARK: - Comparable extension for clamping

private extension Comparable {
    func clamped(to range: PartialRangeFrom<Self>) -> Self {
        max(self, range.lowerBound)
    }
}
