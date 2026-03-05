import Foundation

enum ASRBackendFactory {
    static func resolveEffectiveKind(preferred: ASRBackendKind) -> ASRBackendKind {
        switch preferred {
        case .appleSpeechAnalyzer:
            return AppleSpeechAnalyzerBackend.isRuntimeSupported ? .appleSpeechAnalyzer : .qwenMLX
        case .whisperKit:
            return .whisperKit
        case .qwenMLX:
            return .qwenMLX
        }
    }

    @MainActor
    static func make(preferred: ASRBackendKind) -> any ASRService {
        switch resolveEffectiveKind(preferred: preferred) {
        case .appleSpeechAnalyzer:
            return AppleSpeechAnalyzerBackend()
        case .whisperKit:
            return WhisperKitBackend()
        case .qwenMLX:
            return QwenMLXBackend()
        }
    }
}
