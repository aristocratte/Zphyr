import Foundation

struct TextIntegrityVerifier {
    enum ValidationResult: Sendable {
        case valid
        case invalidIntroducedTokens([String])
        case invalidDroppedContent(recall: Double, missingTokens: [String])
    }

    private let allowedInsertedTokens: Set<String>

    init(allowedInsertedTokens: Set<String> = TextIntegrityVerifier.defaultAllowedInsertedTokens) {
        self.allowedInsertedTokens = allowedInsertedTokens
    }

    func validate(rawASRText: String, formattedText: String) -> ValidationResult {
        validate(rawASRText: rawASRText, formattedText: formattedText, minRecall: 0.0)
    }

    func validate(rawASRText: String, formattedText: String, minRecall: Double) -> ValidationResult {
        let sourceTokenList = tokenize(rawASRText)
        let candidateTokenList = tokenize(formattedText)

        let sourceTokens = Set(sourceTokenList)
        let candidateTokens = Set(candidateTokenList)

        guard !candidateTokens.isEmpty else {
            return .invalidIntroducedTokens(["<empty>"])
        }

        let introduced = candidateTokens
            .subtracting(sourceTokens)
            .subtracting(allowedInsertedTokens)
            .sorted()
        if !introduced.isEmpty {
            return .invalidIntroducedTokens(introduced)
        }

        if sourceTokenList.isEmpty {
            return .valid
        }

        let clampedMinRecall = max(0.0, min(1.0, minRecall))
        if clampedMinRecall <= 0 {
            return .valid
        }

        let sourceCounts = tokenCounts(sourceTokenList)
        let candidateCounts = tokenCounts(candidateTokenList)

        let matchedCount = sourceCounts.reduce(0) { partial, entry in
            let candidateCount = candidateCounts[entry.key, default: 0]
            return partial + min(entry.value, candidateCount)
        }
        let recall = Double(matchedCount) / Double(sourceTokenList.count)
        guard recall >= clampedMinRecall else {
            let missingTokens = sourceCounts.compactMap { token, sourceCount -> String? in
                let candidateCount = candidateCounts[token, default: 0]
                return candidateCount < sourceCount ? token : nil
            }.sorted()
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
