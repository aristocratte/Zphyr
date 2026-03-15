import Foundation

enum ASRTranscriptKind: String, CaseIterable, Codable, Sendable {
    case partial
    case final
}

enum ASRTranscriptionMode: String, CaseIterable, Codable, Sendable {
    case finalOnly
    case streamingPartials
}

struct ASRTranscriptUpdate: Equatable, Codable, Sendable {
    let kind: ASRTranscriptKind
    let text: String
    let timestamp: Date

    init(
        kind: ASRTranscriptKind,
        text: String,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }
}

struct ASRTranscriptionSupport: Equatable, Codable, Sendable {
    let mode: ASRTranscriptionMode
    let supportsCancellation: Bool
    let supportsRetryFromBuffer: Bool
}

struct ASRWatchdogFallback: Equatable, Codable, Sendable {
    let text: String
    let finalSource: String
    let partialCount: Int
    let accumulatedChars: Int
    let timeoutReason: String
    let lastBridgeEventKind: String?
    let watchdogAfterLastEventMs: Int?
}

protocol ASRStreamingSession: AnyObject {
    var updates: AsyncThrowingStream<ASRTranscriptUpdate, Error> { get }
    func append(audioBuffer: [Float]) async
    func finish() async
    func cancel()
}

/// Complete ASR service used by the dictation pipeline.
typealias ASRService = ASRBackend & ASRBackendLifecycle

/// ASR strategy contract.
protocol ASRBackend: AnyObject {
    func transcribe(audioBuffer: [Float]) async throws -> String
    func cancelActiveTranscription() async
    func watchdogFallback(timeoutAt: Date) async -> ASRWatchdogFallback?
    var transcriptionSupport: ASRTranscriptionSupport { get }
    func makeStreamingSession(
        language: String?,
        sampleRate: Double
    ) -> (any ASRStreamingSession)?
}

extension ASRBackend {
    func cancelActiveTranscription() async {}
    func watchdogFallback(timeoutAt: Date) async -> ASRWatchdogFallback? {
        _ = timeoutAt
        return nil
    }

    var transcriptionSupport: ASRTranscriptionSupport {
        ASRTranscriptionSupport(
            mode: .finalOnly,
            supportsCancellation: true,
            supportsRetryFromBuffer: true
        )
    }

    func makeStreamingSession(
        language: String?,
        sampleRate: Double
    ) -> (any ASRStreamingSession)? {
        _ = language
        _ = sampleRate
        return nil
    }
}
