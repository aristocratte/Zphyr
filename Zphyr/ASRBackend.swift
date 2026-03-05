import Foundation

/// Complete ASR service used by the dictation pipeline.
typealias ASRService = ASRBackend & ASRBackendLifecycle

/// ASR strategy contract.
protocol ASRBackend: AnyObject {
    func transcribe(audioBuffer: [Float]) async throws -> String
}
