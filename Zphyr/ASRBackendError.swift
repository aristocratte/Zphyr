import Foundation

enum ASRBackendError: LocalizedError {
    case unsupported(String)
    case notLoaded(String)
    case transcriptionFailed(String)
    case emptyResult
    case invalidAudioBuffer

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason):
            return reason
        case .notLoaded(let reason):
            return reason
        case .transcriptionFailed(let reason):
            return reason
        case .emptyResult:
            return "No transcription text produced."
        case .invalidAudioBuffer:
            return "Invalid audio buffer."
        }
    }
}
