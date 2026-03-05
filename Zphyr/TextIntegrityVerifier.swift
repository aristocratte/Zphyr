import Foundation

struct TextIntegrityVerifier {
    enum ValidationResult: Sendable {
        case valid
        case invalid(introducedTokens: [String])
    }

    private let allowedInsertedTokens: Set<String>

    init(allowedInsertedTokens: Set<String> = TextIntegrityVerifier.defaultAllowedInsertedTokens) {
        self.allowedInsertedTokens = allowedInsertedTokens
    }

    func validate(rawASRText: String, formattedText: String) -> ValidationResult {
        let sourceTokens = Set(tokenize(rawASRText))
        let candidateTokens = Set(tokenize(formattedText))

        guard !candidateTokens.isEmpty else {
            return .invalid(introducedTokens: ["<empty>"])
        }

        let introduced = candidateTokens
            .subtracting(sourceTokens)
            .subtracting(allowedInsertedTokens)
            .sorted()

        return introduced.isEmpty ? .valid : .invalid(introducedTokens: introduced)
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
