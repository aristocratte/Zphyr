import Foundation

enum ASRBackendFactory {
    static func resolveEffectiveKind(preferred: ASRBackendKind) -> ASRBackendKind {
        switch preferred {
        case .appleSpeechAnalyzer:
            return AppleSpeechAnalyzerBackend.isRuntimeSupported ? .appleSpeechAnalyzer : .whisperKit
        case .whisperKit:
            return .whisperKit
        case .parakeet:
            return .parakeet
        }
    }

    @MainActor
    static func make(preferred: ASRBackendKind) -> any ASRService {
        switch resolveEffectiveKind(preferred: preferred) {
        case .appleSpeechAnalyzer:
            return AppleSpeechAnalyzerBackend()
        case .whisperKit:
            return WhisperKitBackend.shared
        case .parakeet:
            return ParakeetBackend.shared
        }
    }
}
