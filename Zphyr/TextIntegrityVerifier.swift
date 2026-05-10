import CryptoKit
import Foundation
import os

struct TextIntegrityVerifier {
    enum ValidationResult: Sendable {
        case valid
        case invalidIntroducedTokens([String])
        case invalidProtectedTerms([String])
        case invalidDroppedContent(recall: Double, missingTokens: [String])
    }

    enum ValidationMode: Sendable {
        case strict(minRecall: Double)
        case trustFormatterOutput(reason: String)

        var description: String {
            switch self {
            case .strict(let minRecall):
                return "strict(minRecall=\(minRecall))"
            case .trustFormatterOutput(let reason):
                return "trustFormatterOutput(reason=\(reason))"
            }
        }
    }

    private let allowedInsertedTokens: Set<String>
    private let allowedDroppedTokens: Set<String>
    private static let log = Logger(subsystem: "com.zphyr.app", category: "TextIntegrityVerifier")

    init(allowedInsertedTokens: Set<String> = TextIntegrityVerifier.defaultAllowedInsertedTokens,
         allowedDroppedTokens: Set<String> = TextIntegrityVerifier.defaultAllowedDroppedTokens) {
        self.allowedInsertedTokens = allowedInsertedTokens
        self.allowedDroppedTokens = allowedDroppedTokens
    }

    func validate(
        rawASRText: String,
        formattedText: String,
        protectedTerms: [String] = []
    ) -> ValidationResult {
        validate(
            rawASRText: rawASRText,
            formattedText: formattedText,
            protectedTerms: protectedTerms,
            mode: .strict(minRecall: 0.0)
        )
    }

    func validate(
        rawASRText: String,
        formattedText: String,
        protectedTerms: [String] = [],
        minRecall: Double
    ) -> ValidationResult {
        validate(
            rawASRText: rawASRText,
            formattedText: formattedText,
            protectedTerms: protectedTerms,
            mode: .strict(minRecall: minRecall)
        )
    }

    func validate(
        rawASRText: String,
        formattedText: String,
        protectedTerms: [String] = [],
        mode: ValidationMode
    ) -> ValidationResult {
        switch mode {
        case .trustFormatterOutput(let reason):
            let trimmedOutput = formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOutput.isEmpty else {
                Self.log.warning(
                    "[IntegrityVerifier] trusted formatter output was empty reason=\"\(reason, privacy: .public)\" rawLen=\(rawASRText.count, privacy: .public)"
                )
                return .invalidIntroducedTokens(["<empty>"])
            }
            Self.log.notice(
                "[IntegrityVerifier] bypassing introduced-token and recall validation mode=\"\(mode.description, privacy: .public)\" rawLen=\(rawASRText.count, privacy: .public) formattedLen=\(formattedText.count, privacy: .public) rawPreview=\"\(Self.debugPreview(rawASRText), privacy: .public)\" formattedPreview=\"\(Self.debugPreview(formattedText), privacy: .public)\""
            )
            return .valid

        case .strict(let minRecall):
            return validateStrict(
                rawASRText: rawASRText,
                formattedText: formattedText,
                protectedTerms: protectedTerms,
                minRecall: minRecall
            )
        }
    }

    private func validateStrict(
        rawASRText: String,
        formattedText: String,
        protectedTerms: [String],
        minRecall: Double
    ) -> ValidationResult {
        let sourceTokenList = tokenize(rawASRText)
        let candidateTokenList = tokenize(formattedText)

        let sourceTokens = Set(sourceTokenList)
        let candidateTokens = Set(candidateTokenList)

        guard !candidateTokens.isEmpty else {
            Self.log.warning(
                "[IntegrityVerifier] strict validation failed with empty candidate rawLen=\(rawASRText.count, privacy: .public)"
            )
            return .invalidIntroducedTokens(["<empty>"])
        }

        let relevantProtectedTerms = protectedTerms.filter {
            !$0.isEmpty && rawASRText.localizedCaseInsensitiveContains($0)
        }
        let missingProtectedTerms = relevantProtectedTerms.filter { !formattedText.contains($0) }
        if !missingProtectedTerms.isEmpty {
            Self.log.warning(
                "[IntegrityVerifier] strict validation rejected protected terms missing=\"\(missingProtectedTerms.prefix(12).joined(separator: ","), privacy: .private(mask: .hash))\" rawPreview=\"\(Self.debugPreview(rawASRText), privacy: .public)\" formattedPreview=\"\(Self.debugPreview(formattedText), privacy: .public)\""
            )
            return .invalidProtectedTerms(missingProtectedTerms)
        }

        let introduced = candidateTokens
            .subtracting(sourceTokens)
            .subtracting(allowedInsertedTokens)
            .sorted()
        if !introduced.isEmpty {
            Self.log.warning(
                "[IntegrityVerifier] strict validation rejected introduced tokens count=\(introduced.count, privacy: .public) sample=\"\(introduced.prefix(12).joined(separator: ","), privacy: .private(mask: .hash))\" rawPreview=\"\(Self.debugPreview(rawASRText), privacy: .public)\" formattedPreview=\"\(Self.debugPreview(formattedText), privacy: .public)\""
            )
            return .invalidIntroducedTokens(introduced)
        }

        let filteredSourceTokenList = sourceTokenList.filter { !allowedDroppedTokens.contains($0) }

        if filteredSourceTokenList.isEmpty {
            return .valid
        }

        let clampedMinRecall = max(0.0, min(1.0, minRecall))
        if clampedMinRecall <= 0 {
            return .valid
        }

        let sourceCounts = tokenCounts(filteredSourceTokenList)
        let candidateCounts = tokenCounts(candidateTokenList)

        let matchedCount = sourceCounts.reduce(0) { partial, entry in
            let candidateCount = candidateCounts[entry.key, default: 0]
            return partial + min(entry.value, candidateCount)
        }
        let recall = Double(matchedCount) / Double(filteredSourceTokenList.count)
        guard recall >= clampedMinRecall else {
            let missingTokens = sourceCounts.compactMap { token, sourceCount -> String? in
                let candidateCount = candidateCounts[token, default: 0]
                return candidateCount < sourceCount ? token : nil
            }.sorted()
            Self.log.warning(
                "[IntegrityVerifier] strict validation rejected dropped content recall=\(recall, privacy: .public) threshold=\(clampedMinRecall, privacy: .public) missing=\"\(missingTokens.prefix(12).joined(separator: ","), privacy: .private(mask: .hash))\" rawPreview=\"\(Self.debugPreview(rawASRText), privacy: .public)\" formattedPreview=\"\(Self.debugPreview(formattedText), privacy: .public)\""
            )
            return .invalidDroppedContent(recall: recall, missingTokens: missingTokens)
        }

        return .valid
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

    private func tokenCounts(_ tokens: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(tokens.count)
        for token in tokens {
            counts[token, default: 0] += 1
        }
        return counts
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

    static let defaultAllowedDroppedTokens: Set<String> = [
        "virgule", "point", "ligne", "paragraphe", "deux", "points", "interrogation",
        "exclamation", "tiret", "parenthèse", "guillemet", "slash", "backslash",
        "underscore", "arobase", "dollar", "pourcent", "asterisque", "égal", "egale",
        "plus", "moins", "ouvre", "ferme", "accolade", "crochet", "euh", "hum", "bah"
    ]

    static let defaultAllowedInsertedTokens: Set<String> = [
        "a", "an", "the", "and", "or", "to", "for", "in", "on", "at", "of", "with", "from", "by",
        "de", "du", "des", "la", "le", "les", "un", "une", "et", "ou", "dans", "pour", "avec", "sur", "au", "aux", "en",
        "el", "los", "las", "y", "o", "con", "para", "del", "al",
        "der", "die", "das", "und", "oder", "mit", "fur", "im", "zu", "den", "dem", "des",
        "и", "или", "в", "на", "с", "для", "по", "к", "из", "за",
        "を", "に", "で", "と", "が", "は", "の", "へ", "から",
        "的", "了", "和", "在", "与", "及",
        "todo", "list", "check", "item"
    ]
}
