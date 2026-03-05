import Foundation
import os

@MainActor
struct ProTextFormatter: TextFormatter {
    private let deterministicFormatter = EcoTextFormatter()
    private let integrityVerifier = TextIntegrityVerifier()
    private let log = Logger(subsystem: "com.zphyr.app", category: "ProFormatter")

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
        guard let llmCandidate = await AdvancedLLMFormatter.shared.format(
            context.normalizedText,
            style: context.defaultCodeStyle,
            constraints: constraints
        ) else {
            log.notice("[ProFormatter] LLM returned nil → using deterministic fallback")
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: []
            )
        }

        switch integrityVerifier.validate(rawASRText: context.rawASRText, formattedText: llmCandidate) {
        case .valid:
            log.notice("[ProFormatter] LLM text accepted (integrity check passed)")
            return TextFormatterResult(
                text: llmCandidate,
                usedDeterministicFallback: false,
                rejectedIntroducedTokens: []
            )

        case .invalid(let introducedTokens):
            log.warning("[ProFormatter] integrity check failed → deterministic fallback (rejected=\(introducedTokens.joined(separator: ","), privacy: .public))")
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                rejectedIntroducedTokens: introducedTokens
            )
        }
    }
}
