//
//  ASROrchestrator.swift
//  Zphyr
//
//  Coordinates VAD -> multi-backend ASR with timeout, candidate ranking, and quality gating.
//
// TODO: [STREAMING] Replace single-shot transcribe() with a streaming variant that
// emits partial results via AsyncStream<TranscriptSegment>. The stabilizer and formatter
// will need to handle partial, mutable segments.

import Foundation
import os

@MainActor
final class ASROrchestrator {

    struct TranscriptionCandidate {
        let text: String
        let backendDisplayName: String
        let qualityIssue: String?
    }

    private enum AttemptError: LocalizedError {
        case timedOut(seconds: Double)
        case lowQuality(String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds):
                return "Transcription timed out after \(Int(seconds.rounded()))s."
            case .lowQuality(let reason):
                return "Transcription rejected due to low-quality output (\(reason))."
            }
        }
    }

    private let log = Logger(subsystem: "com.zphyr.app", category: "ASROrchestrator")

    private let whisperBaseTranscriptionTimeoutSeconds: Double = 20.0

    // MARK: - Main Entry

    /// Apply VAD then transcribe audio through the primary backend (with fallback candidates).
    func transcribe(
        audio: [Float],
        language: String?,
        primaryBackend: any ASRService,
        sampleRate: Double = 16_000
    ) async -> String {
        let vad = VoiceActivityDetector(sampleRate: sampleRate)
        let processedAudio: [Float]
        do {
            let result = try vad.trim(audio)
            processedAudio = result.trimmedBuffer
            let leadingMs = Int(Double(result.leadingTrimmedSamples) / (sampleRate / 1_000))
            let trailingMs = Int(Double(result.trailingTrimmedSamples) / (sampleRate / 1_000))
            if leadingMs > 0 || trailingMs > 0 {
                log.notice(
                    "[ASROrchestrator] VAD trim applied; lead=\(leadingMs, privacy: .public)ms tail=\(trailingMs, privacy: .public)ms threshold=\(Double(result.threshold), privacy: .public)"
                )
            }
        } catch {
            await MainActor.run {
                AppState.shared.error = L10n.ui(
                    for: AppState.shared.selectedLanguage.id,
                    fr: "Aucune voix d\u{00E9}tect\u{00E9}e dans l'audio. R\u{00E9}essaie en parlant plus pr\u{00E8}s du micro.",
                    en: "No voice detected in the audio. Try speaking closer to the microphone.",
                    es: "No se detect\u{00F3} voz en el audio. Intenta hablar m\u{00E1}s cerca del micr\u{00F3}fono.",
                    zh: "\u{97F3}\u{9891}\u{4E2D}\u{672A}\u{68C0}\u{6D4B}\u{5230}\u{8BED}\u{97F3}\u{3002}\u{8BF7}\u{9760}\u{8FD1}\u{9EA6}\u{514B}\u{98CE}\u{91CD}\u{8BD5}\u{3002}",
                    ja: "\u{97F3}\u{58F0}\u{304C}\u{691C}\u{51FA}\u{3055}\u{308C}\u{307E}\u{305B}\u{3093}\u{3067}\u{3057}\u{305F}\u{3002}\u{30DE}\u{30A4}\u{30AF}\u{306B}\u{8FD1}\u{3065}\u{3044}\u{3066}\u{518D}\u{8A66}\u{884C}\u{3057}\u{3066}\u{304F}\u{3060}\u{3055}\u{3044}\u{3002}",
                    ru: "\u{0412} \u{0430}\u{0443}\u{0434}\u{0438}\u{043E} \u{043D}\u{0435} \u{043E}\u{0431}\u{043D}\u{0430}\u{0440}\u{0443}\u{0436}\u{0435}\u{043D} \u{0433}\u{043E}\u{043B}\u{043E}\u{0441}. \u{041F}\u{043E}\u{043F}\u{0440}\u{043E}\u{0431}\u{0443}\u{0439}\u{0442}\u{0435} \u{0433}\u{043E}\u{0432}\u{043E}\u{0440}\u{0438}\u{0442}\u{044C} \u{0431}\u{043B}\u{0438}\u{0436}\u{0435} \u{043A} \u{043C}\u{0438}\u{043A}\u{0440}\u{043E}\u{0444}\u{043E}\u{043D}\u{0443}."
                )
            }
            log.error("[ASROrchestrator] VAD rejected audio: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        let durationMs = Int(Double(processedAudio.count) / (sampleRate / 1_000))
        let primaryBackendName = primaryBackend.descriptor.displayName
        let primaryLoaded = primaryBackend.isLoaded
        log.notice("[ASROrchestrator] transcribe: samples=\(processedAudio.count, privacy: .public) (~\(durationMs, privacy: .public)ms) lang=\(language ?? "auto", privacy: .public) backend=\(primaryBackendName, privacy: .public) loaded=\(primaryLoaded, privacy: .public)")

        guard !processedAudio.isEmpty else {
            log.error("[ASROrchestrator] audioSnapshot is EMPTY -- no audio was captured")
            return ""
        }

        let candidates = transcriptionCandidates(primaryBackend: primaryBackend)
        let orderedNames = candidates.map { $0.descriptor.displayName }.joined(separator: " -> ")
        log.notice("[ASROrchestrator] decoding candidates=\(orderedNames, privacy: .public)")

        var lastFailure: Error?
        var successfulCandidates: [TranscriptionCandidate] = []
        for (index, backend) in candidates.enumerated() {
            let descriptor = backend.descriptor

            if descriptor.requiresModelInstall && !backend.isLoaded {
                log.error("[ASROrchestrator] decoding skipped attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) reason=backend not loaded")
                continue
            }

            let timeout = dynamicTranscriptionTimeout(
                for: descriptor.kind,
                durationMs: durationMs
            )
            log.notice("[ASROrchestrator] decoding attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) timeout=\(timeout, privacy: .public)s")

            do {
                let raw = try await transcribeWithTimeout(
                    backend: backend,
                    audio: processedAudio,
                    timeoutSeconds: timeout
                )
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw ASRBackendError.emptyResult }

                let issue = Self.qualityIssue(result, durationMs: durationMs)
                if let issue {
                    log.warning("[ASROrchestrator] candidate quality warning backend=\(descriptor.displayName, privacy: .public) issue=\(issue, privacy: .public)")
                }
                if Self.isCatastrophicTranscription(result) {
                    throw AttemptError.lowQuality("catastrophic_markup_corruption")
                }

                if descriptor.kind != primaryBackend.descriptor.kind {
                    log.notice("[ASROrchestrator] fallback backend succeeded primary=\(primaryBackendName, privacy: .public) used=\(descriptor.displayName, privacy: .public)")
                }
                log.notice("[ASROrchestrator] backend result chars=\(result.count, privacy: .public)")
                successfulCandidates.append(
                    TranscriptionCandidate(
                        text: result,
                        backendDisplayName: descriptor.displayName,
                        qualityIssue: issue
                    )
                )
            } catch {
                lastFailure = error
                log.error("[ASROrchestrator] decoding failed attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        if let selected = Self.rankCandidates(successfulCandidates) {
            log.notice(
                "[ASROrchestrator] selected candidate backend=\(selected.backendDisplayName, privacy: .public) score=\(Self.completenessScore(for: selected.text), privacy: .public) issue=\(selected.qualityIssue ?? "none", privacy: .public)"
            )
            return selected.text
        }

        await MainActor.run {
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "La transcription a \u{00E9}chou\u{00E9}. R\u{00E9}essayez apr\u{00E8}s rechargement du moteur.",
                en: "Transcription failed. Retry after reloading the backend.",
                es: "La transcripci\u{00F3}n fall\u{00F3}. Vuelve a intentarlo tras recargar el backend.",
                zh: "\u{8F6C}\u{5199}\u{5931}\u{8D25}\u{3002}\u{8BF7}\u{91CD}\u{65B0}\u{52A0}\u{8F7D}\u{540E}\u{7AEF}\u{540E}\u{91CD}\u{8BD5}\u{3002}",
                ja: "\u{6587}\u{5B57}\u{8D77}\u{3053}\u{3057}\u{306B}\u{5931}\u{6557}\u{3057}\u{307E}\u{3057}\u{305F}\u{3002}\u{30D0}\u{30C3}\u{30AF}\u{30A8}\u{30F3}\u{30C9}\u{518D}\u{8AAD}\u{307F}\u{8FBC}\u{307F}\u{5F8C}\u{306B}\u{518D}\u{8A66}\u{884C}\u{3057}\u{3066}\u{304F}\u{3060}\u{3055}\u{3044}\u{3002}",
                ru: "\u{0421}\u{0431}\u{043E}\u{0439} \u{0442}\u{0440}\u{0430}\u{043D}\u{0441}\u{043A}\u{0440}\u{0438}\u{0431}\u{0430}\u{0446}\u{0438}\u{0438}. \u{041F}\u{043E}\u{0432}\u{0442}\u{043E}\u{0440}\u{0438}\u{0442}\u{0435} \u{043F}\u{043E}\u{0441}\u{043B}\u{0435} \u{043F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{0433}\u{0440}\u{0443}\u{0437}\u{043A}\u{0438} \u{0431}\u{044D}\u{043A}\u{0435}\u{043D}\u{0434}\u{0430}."
            )
        }
        if let lastFailure {
            log.error("[ASROrchestrator] all backend attempts failed; last error=\(lastFailure.localizedDescription, privacy: .public)")
        } else {
            log.error("[ASROrchestrator] all backend attempts failed; no backend available")
        }
        return ""
    }

    // MARK: - Candidate Selection

    private func transcriptionCandidates(primaryBackend: any ASRService) -> [any ASRService] {
        guard primaryBackend.descriptor.kind == .whisperKit, AppleSpeechAnalyzerBackend.isRuntimeSupported else {
            return [primaryBackend]
        }
        return [AppleSpeechAnalyzerBackend(), primaryBackend]
    }

    // MARK: - Timeout

    private func transcribeWithTimeout(
        backend: any ASRService,
        audio: [Float],
        timeoutSeconds: Double
    ) async throws -> String {
        let timeoutNanos = UInt64(max(1.0, timeoutSeconds) * 1_000_000_000)
        return try await withThrowingTaskGroup(of: String.self, returning: String.self) { group in
            group.addTask {
                try await backend.transcribe(audioBuffer: audio)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw AttemptError.timedOut(seconds: timeoutSeconds)
            }
            guard let firstCompleted = try await group.next() else {
                throw ASRBackendError.transcriptionFailed("No transcription result produced.")
            }
            group.cancelAll()
            return firstCompleted
        }
    }

    private func dynamicTranscriptionTimeout(
        for kind: ASRBackendKind,
        durationMs: Int
    ) -> Double {
        let audioSeconds = max(0.5, Double(durationMs) / 1_000.0)
        switch kind {
        case .whisperKit:
            return min(120.0, max(whisperBaseTranscriptionTimeoutSeconds, audioSeconds * 2.2 + 8.0))
        case .appleSpeechAnalyzer:
            return min(60.0, max(15.0, audioSeconds * 1.4 + 6.0))
        }
    }

    // MARK: - Quality Checks (static, exposed for tests)

    nonisolated static func qualityIssue(_ text: String, durationMs: Int) -> String? {
        _ = durationMs
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty_result" }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace })

        let longTokenCount = words.filter { $0.count >= 48 }.count
        if longTokenCount >= 4 {
            return "too_many_long_tokens=\(longTokenCount)"
        }

        var frequencies: [Substring: Int] = [:]
        for token in words where token.count >= 4 {
            frequencies[token, default: 0] += 1
        }
        if let repeated = frequencies.first(where: { $0.value >= 14 }) {
            return "repeated_token=\(repeated.key)"
        }

        let lower = trimmed.lowercased()
        let suspiciousMarkers = ["<footer", "<header", "{%", "_increment", "_magic", "extends"]
        let markerHits = suspiciousMarkers.reduce(0) { partial, marker in
            partial + (lower.contains(marker) ? 1 : 0)
        }
        if markerHits >= 1 {
            return "suspicious_markup_markers=\(markerHits)"
        }

        return nil
    }

    nonisolated static func isCatastrophicTranscription(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let catastrophicMarkers = ["<footer", "<header", "{%", "</", "_increment", "_magic", "extends"]
        let markerHits = catastrophicMarkers.reduce(0) { partial, marker in
            partial + (lowered.contains(marker) ? 1 : 0)
        }
        if markerHits >= 3 { return true }

        let words = lowered.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hugeTokens = words.filter { $0.count >= 72 }
        if hugeTokens.count >= 2 { return true }

        let expectedScripts = expectedScriptsForSelectedLanguages()
        var foreignCount = 0
        var totalLetters = 0
        for scalar in text.unicodeScalars {
            guard scalar.properties.isAlphabetic else { continue }
            totalLetters += 1
            if !scalarBelongsToScripts(scalar, scripts: expectedScripts) {
                foreignCount += 1
            }
        }
        if totalLetters > 4, Double(foreignCount) / Double(totalLetters) > 0.15 {
            return true
        }

        if text.range(of: #"(.{2,6})\1{3,}"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    nonisolated static func completenessScore(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Int.min }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let sentenceDelimiters = trimmed.filter { ".!?".contains($0) }.count
        let punctuationBonus = min(20, sentenceDelimiters * 2)
        return trimmed.count * 2 + words * 5 + punctuationBonus
    }

    nonisolated static func rankCandidates(
        _ candidates: [TranscriptionCandidate]
    ) -> TranscriptionCandidate? {
        candidates.max { lhs, rhs in
            let leftScore = completenessScore(for: lhs.text) - (lhs.qualityIssue == nil ? 0 : 120)
            let rightScore = completenessScore(for: rhs.text) - (rhs.qualityIssue == nil ? 0 : 120)
            if leftScore == rightScore {
                return lhs.text.count < rhs.text.count
            }
            return leftScore < rightScore
        }
    }

    // MARK: - Script Detection (internal helpers)

    private nonisolated static func expectedScriptsForSelectedLanguages() -> Set<String> {
        let langs = MainActor.assumeIsolated { AppState.shared.selectedLanguages.map(\.id) }
        var scripts: Set<String> = ["latin"]
        for lang in langs {
            switch lang.lowercased().prefix(2) {
            case "fr", "en", "es", "de", "it", "pt", "nl", "ro", "sv", "da", "no", "pl", "cs", "fi":
                scripts.insert("latin")
            case "zh", "yue":
                scripts.formUnion(["cjk", "latin"])
            case "ja":
                scripts.formUnion(["cjk", "hiragana", "katakana", "latin"])
            case "ko":
                scripts.formUnion(["hangul", "latin"])
            case "ru", "uk", "bg":
                scripts.formUnion(["cyrillic", "latin"])
            case "ar", "he":
                scripts.formUnion(["arabic", "hebrew", "latin"])
            case "th":
                scripts.formUnion(["thai", "latin"])
            case "hi":
                scripts.formUnion(["devanagari", "latin"])
            default:
                scripts.insert("latin")
            }
        }
        return scripts
    }

    private nonisolated static func scalarBelongsToScripts(_ scalar: Unicode.Scalar, scripts: Set<String>) -> Bool {
        let v = scalar.value
        if v < 0x0080 { return scripts.contains("latin") }
        if (0x0080...0x024F).contains(v) || (0x1E00...0x1EFF).contains(v) { return scripts.contains("latin") }
        if (0x0400...0x052F).contains(v) { return scripts.contains("cyrillic") }
        if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) { return scripts.contains("arabic") }
        if (0x0590...0x05FF).contains(v) { return scripts.contains("hebrew") }
        if (0x0E00...0x0E7F).contains(v) { return scripts.contains("thai") }
        if (0x0900...0x097F).contains(v) { return scripts.contains("devanagari") }
        if (0x3040...0x309F).contains(v) { return scripts.contains("hiragana") }
        if (0x30A0...0x30FF).contains(v) { return scripts.contains("katakana") }
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v) { return scripts.contains("cjk") }
        if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) { return scripts.contains("hangul") }
        return true
    }
}
