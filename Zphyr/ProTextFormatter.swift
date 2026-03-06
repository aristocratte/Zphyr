import Foundation
import os

@MainActor
struct ProTextFormatter: TextFormatter {
    private let deterministicFormatter = EcoTextFormatter()
    private let integrityVerifier = TextIntegrityVerifier()
    private let log = Logger(subsystem: "com.zphyr.app", category: "ProFormatter")
    private let integrityValidationMode: TextIntegrityVerifier.ValidationMode = .trustFormatterOutput(
        reason: "AdvancedLLMFormatter/custom MLX local formatter"
    )
    private let trustedFormatterDecision = "trusted_local_mlx_formatter_output"

    func format(_ context: TextFormatterContext) async -> TextFormatterResult {
        let deterministic = await deterministicFormatter.format(
            TextFormatterContext(
                rawASRText: context.rawASRText,
                normalizedText: context.normalizedText,
                languageCode: context.languageCode,
                defaultCodeStyle: context.defaultCodeStyle,
                preferredMode: .advanced
            )
        )

        let constraints = LLMFormattingConstraints.strict
        let llmInput = Self.llmInput(for: context)
        guard !llmInput.isEmpty else {
            log.warning(
                "[ProFormatter] sanitized raw ASR input is empty → deterministic fallback rawPreview=\"\(Self.debugPreview(context.rawASRText), privacy: .public)\" normalizedPreview=\"\(Self.debugPreview(context.normalizedText), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: [],
                llmInputLength: 0,
                llmOutputLength: nil,
                llmRecall: nil,
                llmValidationDecision: "skipped_empty_sanitized_raw_input"
            )
        }
        log.notice(
            "[ProFormatter] invoking LLM sanitizedRawPreview=\"\(Self.debugPreview(llmInput), privacy: .public)\" rawPreview=\"\(Self.debugPreview(context.rawASRText), privacy: .public)\" normalizedPreview=\"\(Self.debugPreview(context.normalizedText), privacy: .public)\""
        )
        guard let llmCandidate = await AdvancedLLMFormatter.shared.format(
            llmInput,
            style: context.defaultCodeStyle,
            constraints: constraints
        ) else {
            log.notice(
                "[ProFormatter] LLM returned nil → deterministic fallback preview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: [],
                llmInputLength: llmInput.count,
                llmOutputLength: nil,
                llmRecall: nil,
                llmValidationDecision: "llm_returned_nil"
            )
        }

        let recall = tokenRecall(source: context.rawASRText, candidate: llmCandidate)
        let sanitizedCandidate = Self.sanitizeRawASRText(llmCandidate)
        let noOpAgainstLLMInput = sanitizedCandidate == llmInput
        let exactMatchRaw = llmCandidate == context.rawASRText
        let exactMatchNormalized = llmCandidate == context.normalizedText
        log.notice(
            "[ProFormatter] LLM candidate received integrityMode=\"\(integrityValidationMode.description, privacy: .public)\" noOpAgainstSanitizedInput=\(noOpAgainstLLMInput, privacy: .public) exactMatchRaw=\(exactMatchRaw, privacy: .public) exactMatchNormalized=\(exactMatchNormalized, privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recallIfStrict=\(recall, privacy: .public) candidatePreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\""
        )

        switch integrityVerifier.validate(
            rawASRText: context.rawASRText,
            formattedText: llmCandidate,
            mode: integrityValidationMode
        ) {
        case .valid:
            log.notice(
                "[ProFormatter] LLM text accepted (integrity bypass active for local MLX formatter) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recallIfStrict=\(recall, privacy: .public) noOpAgainstSanitizedInput=\(noOpAgainstLLMInput, privacy: .public) outputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\""
            )
            return TextFormatterResult(
                text: llmCandidate,
                usedDeterministicFallback: false,
                rejectedIntroducedTokens: [],
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: trustedFormatterDecision
            )

        case .invalidIntroducedTokens(let introducedTokens):
            log.warning(
                "[ProFormatter] integrity check failed (introduced tokens) → deterministic fallback (rejected=\(introducedTokens.joined(separator: ","), privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: introducedTokens,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: "rejected_introduced_tokens"
            )

        case .invalidDroppedContent(let recall, let missingTokens):
            log.warning(
                "[ProFormatter] integrity check failed (dropped content) → deterministic fallback (mode=\"\(integrityValidationMode.description, privacy: .public)\" recall=\(recall, privacy: .public) missing=\(missingTokens.prefix(12).joined(separator: ","), privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: missingTokens,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: "rejected_dropped_content"
            )
        }
    }

    nonisolated static func llmInput(for context: TextFormatterContext) -> String {
        sanitizeRawASRText(context.rawASRText)
    }

    nonisolated static func sanitizeRawASRText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}_\\s]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenRecall(source: String, candidate: String) -> Double {
        let sourceTokens = tokenize(source)
        let candidateTokens = tokenize(candidate)
        guard !sourceTokens.isEmpty else { return 1.0 }
        let sourceCounts = counts(sourceTokens)
        let candidateCounts = counts(candidateTokens)
        let matched = sourceCounts.reduce(0) { partial, entry in
            partial + min(entry.value, candidateCounts[entry.key, default: 0])
        }
        return Double(matched) / Double(sourceTokens.count)
    }

    private func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var normalized = text
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        normalized = normalized.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func counts(_ tokens: [String]) -> [String: Int] {
        var value: [String: Int] = [:]
        value.reserveCapacity(tokens.count)
        for token in tokens {
            value[token, default: 0] += 1
        }
        return value
    }

    private static func debugPreview(_ text: String, limit: Int = 280) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else { return normalized }
        let remaining = normalized.count - limit
        return "\(normalized.prefix(limit))…(+\(remaining) chars)"
    }
}
