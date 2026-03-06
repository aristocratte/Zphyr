import Foundation
import os

@MainActor
struct ProTextFormatter: TextFormatter {
    private let deterministicFormatter = EcoTextFormatter()
    private let integrityVerifier = TextIntegrityVerifier()
    private let log = Logger(subsystem: "com.zphyr.app", category: "ProFormatter")
    private let minimumRecall: Double = 0.92

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
        let llmInput = context.normalizedText
        log.notice(
            "[ProFormatter] invoking LLM inputPreview=\"\(Self.debugPreview(llmInput), privacy: .public)\" rawPreview=\"\(Self.debugPreview(context.rawASRText), privacy: .public)\""
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
                llmRecall: nil
            )
        }

        switch integrityVerifier.validate(
            rawASRText: context.rawASRText,
            formattedText: llmCandidate,
            minRecall: minimumRecall
        ) {
        case .valid:
            let recall = tokenRecall(source: context.rawASRText, candidate: llmCandidate)
            log.notice(
                "[ProFormatter] LLM text accepted (integrity check passed) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public) outputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\""
            )
            return TextFormatterResult(
                text: llmCandidate,
                usedDeterministicFallback: false,
                rejectedIntroducedTokens: [],
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall
            )

        case .invalidIntroducedTokens(let introducedTokens):
            let recall = tokenRecall(source: context.rawASRText, candidate: llmCandidate)
            log.warning(
                "[ProFormatter] integrity check failed (introduced tokens) → deterministic fallback (rejected=\(introducedTokens.joined(separator: ","), privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: introducedTokens,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall
            )

        case .invalidDroppedContent(let recall, let missingTokens):
            log.warning(
                "[ProFormatter] integrity check failed (dropped content) → deterministic fallback (recall=\(recall, privacy: .public) threshold=\(minimumRecall, privacy: .public) missing=\(missingTokens.prefix(12).joined(separator: ","), privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: missingTokens,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall
            )
        }
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
