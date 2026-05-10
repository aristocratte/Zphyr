import CryptoKit
import Foundation
import os

@MainActor
struct ProTextFormatter: TextFormatter {
    private enum Round2BaselinePolicy {
        static let baselineID = "round2"
    }

    private struct OutputProfilePolicy {
        let allowsRewrite: Bool
        let minRecall: Double
        let minLengthRatio: Double
        let maxLengthRatio: Double
        let strictProtectedTerms: Bool
    }

    private let deterministicFormatter = EcoTextFormatter()
    private let integrityVerifier = TextIntegrityVerifier()
    private let log = Logger(subsystem: "com.zphyr.app", category: "ProFormatter")

    func format(_ context: TextFormatterContext) async -> TextFormatterResult {
        let deterministic = await deterministicFormatter.format(
            TextFormatterContext(
                rawASRText: context.rawASRText,
                normalizedText: context.normalizedText,
                languageCode: context.languageCode,
                outputProfile: context.outputProfile,
                formattingModelID: context.formattingModelID,
                protectedTerms: context.protectedTerms,
                defaultCodeStyle: context.defaultCodeStyle,
                preferredMode: .advanced
            )
        )
        let profilePolicy = policy(for: context.outputProfile)

        guard profilePolicy.allowsRewrite else {
            log.notice(
                "[ProFormatter] skipping rewrite baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) reason=verbatim_profile"
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: false,
                pipelineDecision: .deterministicOnly,
                fallbackReason: .profileRewriteDisabledVerbatim,
                rejectedIntroducedTokens: [],
                llmInputLength: nil,
                llmOutputLength: nil,
                llmRecall: nil,
                llmValidationDecision: "skipped_profile_verbatim"
            )
        }
        let integrityValidationMode: TextIntegrityVerifier.ValidationMode = .strict(
            minRecall: profilePolicy.minRecall
        )
        let acceptedFormatterDecision = "accepted_baseline_round2_\(context.outputProfile.rawValue)_\(context.formattingModelID.rawValue)"

        let constraints = LLMFormattingConstraints.strict
        let llmInput = Self.llmInput(for: context)
        guard !llmInput.isEmpty else {
            log.warning(
                "[ProFormatter] sanitized raw ASR input is empty → deterministic fallback rawPreview=\"\(Self.debugPreview(context.rawASRText), privacy: .public)\" normalizedPreview=\"\(Self.debugPreview(context.normalizedText), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .rewriteSanitizedInputEmpty,
                rejectedIntroducedTokens: [],
                llmInputLength: 0,
                llmOutputLength: nil,
                llmRecall: nil,
                llmValidationDecision: "skipped_empty_sanitized_raw_input"
            )
        }
        log.notice(
            "[ProFormatter] invoking baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) formatterModel=\(context.formattingModelID.rawValue, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) minRecall=\(profilePolicy.minRecall, privacy: .public) protectedTerms=\(context.protectedTerms.count, privacy: .public) sanitizedRawPreview=\"\(Self.debugPreview(llmInput), privacy: .public)\" rawPreview=\"\(Self.debugPreview(context.rawASRText), privacy: .public)\" normalizedPreview=\"\(Self.debugPreview(context.normalizedText), privacy: .public)\""
        )
        guard let llmCandidate = await AdvancedLLMFormatter.shared.format(
            llmInput,
            style: context.defaultCodeStyle,
            constraints: constraints,
            modelID: context.formattingModelID
        ) else {
            log.notice(
                "[ProFormatter] LLM returned nil → deterministic fallback preview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .rewriteModelReturnedNil,
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
        let lengthRatio = Double(llmCandidate.count) / max(1.0, Double(context.rawASRText.count))
        log.notice(
            "[ProFormatter] LLM candidate received baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) integrityMode=\"\(integrityValidationMode.description, privacy: .public)\" noOpAgainstSanitizedInput=\(noOpAgainstLLMInput, privacy: .public) exactMatchRaw=\(exactMatchRaw, privacy: .public) exactMatchNormalized=\(exactMatchNormalized, privacy: .public) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public) lengthRatio=\(lengthRatio, privacy: .public) candidatePreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\""
        )

        guard lengthRatio >= profilePolicy.minLengthRatio,
              lengthRatio <= profilePolicy.maxLengthRatio else {
            log.warning(
                "[ProFormatter] baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) rejected candidate for lengthRatio=\(lengthRatio, privacy: .public) expectedRange=\(profilePolicy.minLengthRatio, privacy: .public)...\(profilePolicy.maxLengthRatio, privacy: .public)"
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .profileValidationRejected,
                rejectedIntroducedTokens: [],
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: "rejected_profile_length_ratio"
            )
        }

        switch integrityVerifier.validate(
            rawASRText: context.rawASRText,
            formattedText: llmCandidate,
            protectedTerms: profilePolicy.strictProtectedTerms ? context.protectedTerms : [],
            mode: integrityValidationMode
        ) {
        case .valid:
            log.notice(
                "[ProFormatter] baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) accepted LLM text llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public) noOpAgainstSanitizedInput=\(noOpAgainstLLMInput, privacy: .public) outputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\""
            )
            return TextFormatterResult(
                text: llmCandidate,
                usedDeterministicFallback: false,
                pipelineDecision: .acceptedBaselineRound2,
                fallbackReason: nil,
                rejectedIntroducedTokens: [],
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: acceptedFormatterDecision
            )

        case .invalidProtectedTerms(let missingTerms):
            log.warning(
                "[ProFormatter] baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) integrity check failed (protected terms) → deterministic fallback missing=\(missingTerms.joined(separator: ","), privacy: .public)"
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .profileProtectedTermsRejected,
                rejectedIntroducedTokens: missingTerms,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: "rejected_protected_terms"
            )

        case .invalidIntroducedTokens(let introducedTokens):
            log.warning(
                "[ProFormatter] baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) integrity check failed (introduced tokens) → deterministic fallback (rejected=\(introducedTokens.joined(separator: ","), privacy: .private(mask: .hash)) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public) recall=\(recall, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .rewriteIntroducedTokens,
                rejectedIntroducedTokens: introducedTokens,
                llmInputLength: llmInput.count,
                llmOutputLength: llmCandidate.count,
                llmRecall: recall,
                llmValidationDecision: "rejected_introduced_tokens"
            )

        case .invalidDroppedContent(let recall, let missingTokens):
            log.warning(
                "[ProFormatter] baseline=\(Round2BaselinePolicy.baselineID, privacy: .public) profile=\(context.outputProfile.rawValue, privacy: .public) integrity check failed (dropped content) → deterministic fallback (mode=\"\(integrityValidationMode.description, privacy: .public)\" recall=\(recall, privacy: .public) missing=\(missingTokens.prefix(12).joined(separator: ","), privacy: .private(mask: .hash)) llmInLen=\(llmInput.count, privacy: .public) llmOutLen=\(llmCandidate.count, privacy: .public)) llmOutputPreview=\"\(Self.debugPreview(llmCandidate), privacy: .public)\" fallbackPreview=\"\(Self.debugPreview(deterministic.text), privacy: .public)\""
            )
            return TextFormatterResult(
                text: deterministic.text,
                usedDeterministicFallback: true,
                pipelineDecision: .deterministicFallback,
                fallbackReason: .profileValidationRejected,
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

    private func policy(for outputProfile: OutputProfile) -> OutputProfilePolicy {
        switch outputProfile {
        case .verbatim:
            return OutputProfilePolicy(
                allowsRewrite: false,
                minRecall: 1.0,
                minLengthRatio: 0.95,
                maxLengthRatio: 1.05,
                strictProtectedTerms: true
            )
        case .clean:
            return OutputProfilePolicy(
                allowsRewrite: true,
                minRecall: 0.97,
                minLengthRatio: 0.60,
                maxLengthRatio: 1.30,
                strictProtectedTerms: false
            )
        case .technical:
            return OutputProfilePolicy(
                allowsRewrite: true,
                minRecall: 0.995,
                minLengthRatio: 0.80,
                maxLengthRatio: 1.15,
                strictProtectedTerms: true
            )
        case .email:
            return OutputProfilePolicy(
                allowsRewrite: true,
                minRecall: 0.96,
                minLengthRatio: 0.70,
                maxLengthRatio: 1.25,
                strictProtectedTerms: false
            )
        }
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
        #if DEBUG
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else { return normalized }
        let remaining = normalized.count - limit
        return "\(normalized.prefix(limit))…(+\(remaining) chars)"
        #else
        let h = SHA256.hash(data: Data(text.utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        return "redacted len=\(text.count) hash=\(h)"
        #endif
    }
}
