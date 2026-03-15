//
//  LocalMetrics.swift
//  Zphyr
//
//  Privacy-safe, local-only performance metrics for a dictation session.
//  Nothing leaves the device. Used for evaluation harness and debugging.
//

import Foundation
import os

struct DictationSessionMetrics {
    var sessionID: UUID = UUID()
    var capturedSampleCount: Int = 0
    var asrDurationMs: Int = 0
    var transcriptionMode: ASRTranscriptionMode = .finalOnly
    var partialUpdatesCount: Int = 0
    var retriedFromBuffer: Bool = false
    var vadTrimmedLeadingMs: Int = 0
    var vadTrimmedTrailingMs: Int = 0
    var stabilizeDurationMs: Int = 0
    var formatterDurationMs: Int = 0
    var insertionDurationMs: Int = 0
    var rawCharacterCount: Int = 0
    var finalCharacterCount: Int = 0
    var backendName: String = ""
    var formatterMode: String = ""
    var outputProfile: String = ""
    var pipelineDecision: PipelineDecision = .deterministicOnly
    var pipelineFallbackReason: FallbackReason?
    var usedFormatterFallback: Bool = false
    var listBlocksDetected: Int = 0
    var insertionTargetFamily: String = ""
    var insertionStrategy: String = ""
    var insertionFallbackReason: FallbackReason?
    var speechEndedAt: Date?
    var asrStartedAt: Date?
    var rawTranscriptReadyAt: Date?
    var formattingCompletedAt: Date?
    var insertionCompletedAt: Date?
    var sessionCompletedAt: Date?

    var totalDurationMs: Int {
        asrDurationMs + stabilizeDurationMs + formatterDurationMs + insertionDurationMs
    }

    var speechEndToASRStartMs: Int {
        Self.deltaMs(from: speechEndedAt, to: asrStartedAt)
    }

    var asrToRawTranscriptMs: Int {
        Self.deltaMs(from: asrStartedAt, to: rawTranscriptReadyAt)
    }

    var rawTranscriptToFormattingFinalMs: Int {
        Self.deltaMs(from: rawTranscriptReadyAt, to: formattingCompletedAt)
    }

    var formattingFinalToInsertionMs: Int {
        Self.deltaMs(from: formattingCompletedAt, to: insertionCompletedAt)
    }

    var endToEndDurationMs: Int {
        Self.deltaMs(from: speechEndedAt, to: sessionCompletedAt)
    }

    var compressionRatio: Double {
        guard rawCharacterCount > 0 else { return 1.0 }
        return Double(finalCharacterCount) / Double(rawCharacterCount)
    }

    private static func deltaMs(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}

@MainActor
final class LocalMetricsRecorder {
    static let shared = LocalMetricsRecorder()
    private let log = Logger(subsystem: "com.zphyr.app", category: "Metrics")

    private(set) var lastSession: DictationSessionMetrics?
    private(set) var sessionHistory: [DictationSessionMetrics] = []  // keep last 20

    private static let maxHistory = 20

    func record(_ metrics: DictationSessionMetrics) {
        lastSession = metrics
        sessionHistory.append(metrics)
        if sessionHistory.count > Self.maxHistory {
            sessionHistory.removeFirst(sessionHistory.count - Self.maxHistory)
        }
        logSummary(metrics)
    }

    func logSummary(_ metrics: DictationSessionMetrics) {
        log.notice(
            "[Metrics] session=\(metrics.sessionID.uuidString, privacy: .public) e2e=\(metrics.endToEndDurationMs, privacy: .public)ms speechToAsr=\(metrics.speechEndToASRStartMs, privacy: .public)ms asrToRaw=\(metrics.asrToRawTranscriptMs, privacy: .public)ms rawToFinal=\(metrics.rawTranscriptToFormattingFinalMs, privacy: .public)ms finalToInsert=\(metrics.formattingFinalToInsertionMs, privacy: .public)ms pipelineTotal=\(metrics.totalDurationMs, privacy: .public)ms asr=\(metrics.asrDurationMs, privacy: .public)ms transcriptionMode=\(metrics.transcriptionMode.rawValue, privacy: .public) partialUpdates=\(metrics.partialUpdatesCount, privacy: .public) retried=\(metrics.retriedFromBuffer, privacy: .public) stabilize=\(metrics.stabilizeDurationMs, privacy: .public)ms fmt=\(metrics.formatterDurationMs, privacy: .public)ms insert=\(metrics.insertionDurationMs, privacy: .public)ms chars=\(metrics.rawCharacterCount, privacy: .public)->\(metrics.finalCharacterCount, privacy: .public) backend=\(metrics.backendName, privacy: .public) mode=\(metrics.formatterMode, privacy: .public) profile=\(metrics.outputProfile.isEmpty ? "none" : metrics.outputProfile, privacy: .public) decision=\(metrics.pipelineDecision.rawValue, privacy: .public) pipelineFallback=\(metrics.pipelineFallbackReason?.rawValue ?? "none", privacy: .public) insertionFamily=\(metrics.insertionTargetFamily.isEmpty ? "none" : metrics.insertionTargetFamily, privacy: .public) insertionStrategy=\(metrics.insertionStrategy.isEmpty ? "none" : metrics.insertionStrategy, privacy: .public) insertionFallback=\(metrics.insertionFallbackReason?.rawValue ?? "none", privacy: .public) fallback=\(metrics.usedFormatterFallback, privacy: .public) lists=\(metrics.listBlocksDetected, privacy: .public)"
        )
    }

    func clearHistory() {
        lastSession = nil
        sessionHistory.removeAll()
    }

    // TODO: [EVALUATION] Add export to JSON for offline evaluation harness
    // func exportToJSON() -> Data
}
