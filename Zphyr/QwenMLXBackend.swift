import Foundation

@MainActor
final class QwenMLXBackend: ASRService {
    private let engine = Qwen3ASREngine.shared

    let descriptor = ASRBackendDescriptor(
        kind: .qwenMLX,
        displayName: "Qwen3-ASR (MLX)",
        requiresModelInstall: true,
        modelSizeLabel: "~2.46 GB",
        onboardingSubtitle: "Qwen3-ASR installs once and runs 100% locally afterwards.",
        approxModelBytes: Int64(Qwen3ASREngine.modelBytes)
    )

    var isLoaded: Bool { engine.isLoaded }
    var isInstalling: Bool { engine.isInstalling }
    var downloadProgress: Double { engine.downloadProgress }
    var installError: String? { engine.installError }
    var installPath: String? { Qwen3ASREngine.resolveInstallURL()?.path }
    var isPaused: Bool { engine.isPaused }

    func loadIfInstalled() async {
        await engine.loadIfInstalled()
    }

    func installModel() async {
        await engine.installModel()
    }

    func cancelInstall() {
        engine.cancelInstall()
    }

    func pauseInstall() {
        engine.pauseInstall()
    }

    func resumeInstall() {
        engine.resumeInstall()
    }

    func uninstallModel() {
        engine.unload()
        if let installURL = Qwen3ASREngine.resolveInstallURL() {
            try? FileManager.default.removeItem(at: installURL)
        }
        try? FileManager.default.removeItem(at: Qwen3ASREngine.cacheDir)
        AppState.shared.qwen3asrInstalled = false
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        guard engine.isLoaded else {
            throw ASRBackendError.notLoaded("Qwen3-ASR model is not loaded.")
        }
        guard let result = await engine.transcribe(audioBuffer, language: selectedLanguageHint())?
            .trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else {
            throw ASRBackendError.emptyResult
        }
        return result
    }

    private func selectedLanguageHint() -> String? {
        let langs = AppState.shared.selectedLanguages
        return langs.count > 1 ? nil : (langs.first?.id ?? "fr")
    }
}
