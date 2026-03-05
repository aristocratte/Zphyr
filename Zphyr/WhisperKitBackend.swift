import Foundation

@MainActor
final class WhisperKitBackend: ASRService {
    let descriptor = ASRBackendDescriptor(
        kind: .whisperKit,
        displayName: "WhisperKit",
        requiresModelInstall: true,
        modelSizeLabel: "~632 MB",
        onboardingSubtitle: "WhisperKit backend is currently unavailable in this build.",
        approxModelBytes: 632 * 1_024 * 1_024
    )

    var installError: String? {
        "WhisperKit backend is a stub in this build."
    }

    func transcribe(audioBuffer _: [Float]) async throws -> String {
        throw ASRBackendError.unsupported("WhisperKit backend is not integrated yet.")
    }

    func loadIfInstalled() async {}
    func installModel() async {}
    func cancelInstall() {}
    func pauseInstall() {}
    func resumeInstall() {}
    func uninstallModel() {}
}
