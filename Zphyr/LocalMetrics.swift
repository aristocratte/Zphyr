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
    var vadTrimmedLeadingMs: Int = 0
    var vadTrimmedTrailingMs: Int = 0
    var stabilizeDurationMs: Int = 0
    var formatterDurationMs: Int = 0
    var insertionDurationMs: Int = 0
    var rawCharacterCount: Int = 0
    var finalCharacterCount: Int = 0
    var backendName: String = ""
    var formatterMode: String = ""
    var usedFormatterFallback: Bool = false
    var listBlocksDetected: Int = 0

    var totalDurationMs: Int {
        asrDurationMs + stabilizeDurationMs + formatterDurationMs + insertionDurationMs
    }

    var compressionRatio: Double {
        guard rawCharacterCount > 0 else { return 1.0 }
        return Double(finalCharacterCount) / Double(rawCharacterCount)
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
            "[Metrics] session=\(metrics.sessionID.uuidString, privacy: .public) total=\(metrics.totalDurationMs, privacy: .public)ms asr=\(metrics.asrDurationMs, privacy: .public)ms fmt=\(metrics.formatterDurationMs, privacy: .public)ms chars=\(metrics.rawCharacterCount, privacy: .public)->\(metrics.finalCharacterCount, privacy: .public) backend=\(metrics.backendName, privacy: .public) mode=\(metrics.formatterMode, privacy: .public) fallback=\(metrics.usedFormatterFallback, privacy: .public) lists=\(metrics.listBlocksDetected, privacy: .public)"
        )
    }

    func clearHistory() {
        lastSession = nil
        sessionHistory.removeAll()
    }

    // TODO: [EVALUATION] Add export to JSON for offline evaluation harness
    // func exportToJSON() -> Data
}
