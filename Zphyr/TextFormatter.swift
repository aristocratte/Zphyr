import Foundation

struct TextFormatterContext: Sendable {
    let rawASRText: String
    let normalizedText: String
    let languageCode: String
    let defaultCodeStyle: CodeStyle
    let preferredMode: FormattingMode
}

struct TextFormatterResult: Sendable {
    let text: String
    let usedDeterministicFallback: Bool
    let rejectedIntroducedTokens: [String]

    static func deterministic(_ text: String) -> TextFormatterResult {
        TextFormatterResult(text: text, usedDeterministicFallback: false, rejectedIntroducedTokens: [])
    }
}

protocol TextFormatter {
    func format(_ context: TextFormatterContext) async -> TextFormatterResult
}
