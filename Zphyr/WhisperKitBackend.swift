import Foundation
import os
import WhisperKit

/// Singleton managing on-device speech recognition via Whisper Large v3 Turbo.
/// Uses WhisperKit (argmaxinc/WhisperKit) for optimized Apple Silicon inference.
@Observable
@MainActor
final class WhisperKitBackend: ASRService {

    static let shared = WhisperKitBackend()

    static let modelVariant   = "openai_whisper-large-v3-turbo"
    static let modelSizeBytes: Double = 600 * 1_024 * 1_024  // ~600 MB

    let descriptor = ASRBackendDescriptor(
        kind: .whisperKit,
        displayName: "Whisper Large v3 Turbo",
        requiresModelInstall: true,
        modelSizeLabel: "~600 MB",
        onboardingSubtitle: "Whisper s'installe une seule fois (~600 Mo). Il s'exécute ensuite 100% en local.",
        approxModelBytes: 600 * 1_024 * 1_024
    )

    // ── Observable state (drives onboarding + settings UI) ─────────────────
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = nil
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    var isPaused: Bool           = false

    private(set) var isLoaded: Bool = false
    var installPath: String? { Self.resolveInstallURL()?.path }

    private var installTask: Task<Void, Never>? = nil
    private let log = Logger(subsystem: "com.zphyr.app", category: "WhisperASR")

    private var whisperKit: WhisperKit?

    private init() {}

    // MARK: - Install path resolution

    /// Discovers the local model cache directory on disk.
    static func resolveInstallURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // WhisperKit uses HuggingFace Hub cache via swift-transformers
        let hubRoot = home.appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml")
        if fm.fileExists(atPath: hubRoot.path) {
            return hubRoot
        }
        // Alternative: explicit model folder
        let altRoot = home.appendingPathComponent("Library/Caches/huggingface/models/argmaxinc/whisperkit-coreml")
        if fm.fileExists(atPath: altRoot.path) {
            return altRoot
        }
        return nil
    }

    // MARK: - Installation

    func installModel() async {
        guard !isInstalling else { return }
        isInstalling     = true
        installError     = nil
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""

        let task = Task<Void, Never> {
            do {
                let config = WhisperKitConfig(
                    model: Self.modelVariant,
                    verbose: false,
                    prewarm: true,
                    load: true
                )
                let kit = try await WhisperKit(config)
                if !Task.isCancelled {
                    self.whisperKit = kit
                    self.isLoaded = true
                    self.downloadProgress = 1.0
                    self.downloadSpeed    = ""
                    self.downloadedMB     = ""
                    AppState.shared.whisperInstalled = true
                    self.log.notice("[WhisperASR] installation complete")
                }
            } catch is CancellationError {
                self.log.notice("[WhisperASR] install cancelled")
            } catch {
                if !Task.isCancelled {
                    self.installError = error.localizedDescription
                    self.log.error("[WhisperASR] install error: \(error.localizedDescription)")
                }
            }
            self.isInstalling = false
            self.installTask  = nil
        }
        installTask = task
        await task.value
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask      = nil
        isInstalling     = false
        isPaused         = false
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""
        log.notice("[WhisperASR] install cancelled by user")
    }

    func pauseInstall() {
        isPaused      = true
        downloadSpeed = ""
    }

    func resumeInstall() {
        isPaused = false
    }

    // MARK: - Loading

    func loadIfInstalled() async {
        guard AppState.shared.whisperInstalled, !isLoaded else { return }
        do {
            let config = WhisperKitConfig(
                model: Self.modelVariant,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            whisperKit = try await WhisperKit(config)
            isLoaded = true
            log.notice("[WhisperASR] loaded from disk cache")
        } catch {
            AppState.shared.whisperInstalled = false
            log.warning("[WhisperASR] cache missing or corrupt — resetting flag: \(error.localizedDescription)")
        }
    }

    func unload() {
        whisperKit = nil
        isLoaded = false
        log.notice("[WhisperASR] model unloaded from memory")
    }

    func uninstallModel() {
        unload()
        if let url = Self.resolveInstallURL() {
            try? FileManager.default.removeItem(at: url)
        }
        AppState.shared.whisperInstalled = false
        log.notice("[WhisperASR] model uninstalled")
    }

    // MARK: - Transcription

    func transcribe(audioBuffer: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            throw ASRBackendError.notLoaded("Whisper model is not loaded.")
        }
        guard !audioBuffer.isEmpty else {
            throw ASRBackendError.invalidAudioBuffer
        }

        let languageHint = selectedLanguageHint()
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageHint,
            temperatureFallbackCount: 3,
            usePrefillPrompt: languageHint != nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results: [TranscriptionResult] = try await kit.transcribe(
            audioArray: audioBuffer,
            decodeOptions: options
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw ASRBackendError.emptyResult }
        log.notice("[WhisperASR] transcribed \(text.count) chars, language=\(languageHint ?? "auto")")
        return text
    }

    // MARK: - Helpers

    private func selectedLanguageHint() -> String? {
        let langs = AppState.shared.selectedLanguages
        return langs.count > 1 ? nil : (langs.first?.id ?? "fr")
    }
}
