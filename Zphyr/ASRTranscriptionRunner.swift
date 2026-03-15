import Foundation
import os

@MainActor
enum ASRTranscriptionRunner {
    private nonisolated static let log = Logger(subsystem: "com.zphyr.app", category: "ASRTimeout")

    static func transcribe(
        backend: any ASRService,
        audio: [Float],
        timeoutSeconds: Double,
        timeoutError: @escaping @Sendable () -> Error
    ) async throws -> String {
        let attemptID = UUID().uuidString
        let backendName = backend.descriptor.displayName
        let timeoutNanos = UInt64(max(1.0, timeoutSeconds) * 1_000_000_000)
        log.notice(
            "[ASRTimeout] begin attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) samples=\(audio.count, privacy: .public) timeout=\(timeoutSeconds, privacy: .public)s"
        )
        let transcriptionTask = Task {
            Self.log.notice(
                "[ASRTimeout] worker start attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public)"
            )
            do {
                let result = try await backend.transcribe(audioBuffer: audio)
                Self.log.notice(
                    "[ASRTimeout] worker success attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) chars=\(result.count, privacy: .public)"
                )
                return result
            } catch {
                Self.log.error(
                    "[ASRTimeout] worker failed attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }

        return try await withTaskCancellationHandler {
            defer { transcriptionTask.cancel() }
            return try await withThrowingTaskGroup(of: String.self, returning: String.self) { group in
                group.addTask {
                    try await transcriptionTask.value
                }
                group.addTask {
                    Self.log.notice(
                        "[ASRTimeout] watchdog armed attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public)"
                    )
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    try Task.checkCancellation()
                    let timeoutAt = Date()
                    if let fallback = await backend.watchdogFallback(timeoutAt: timeoutAt) {
                        Self.log.notice(
                            "[ASRTimeout] watchdog fallback attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) final_source=\(fallback.finalSource, privacy: .public) partial_count=\(fallback.partialCount, privacy: .public) accumulated_chars=\(fallback.accumulatedChars, privacy: .public) timeout_reason=\(fallback.timeoutReason, privacy: .public) last_bridge_event=\(fallback.lastBridgeEventKind ?? "none", privacy: .public) watchdog_after_last_event_ms=\(fallback.watchdogAfterLastEventMs ?? -1, privacy: .public)"
                        )
                        transcriptionTask.cancel()
                        await backend.cancelActiveTranscription()
                        return fallback.text
                    }
                    Self.log.error(
                        "[ASRTimeout] watchdog fired attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) timeout_reason=no_exploitable_output"
                    )
                    transcriptionTask.cancel()
                    await backend.cancelActiveTranscription()
                    throw timeoutError()
                }

                do {
                    guard let firstCompleted = try await group.next() else {
                        throw ASRBackendError.transcriptionFailed("No transcription result produced.")
                    }
                    group.cancelAll()
                    log.notice(
                        "[ASRTimeout] completed attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) chars=\(firstCompleted.count, privacy: .public)"
                    )
                    return firstCompleted
                } catch {
                    group.cancelAll()
                    log.error(
                        "[ASRTimeout] failed attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    throw error
                }
            }
        } onCancel: {
            log.notice(
                "[ASRTimeout] cancellation handler attempt=\(attemptID, privacy: .public) backend=\(backendName, privacy: .public)"
            )
            transcriptionTask.cancel()
            Task {
                await backend.cancelActiveTranscription()
            }
        }
    }
}
