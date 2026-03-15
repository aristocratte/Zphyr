import Foundation

struct TextFormatterContext: Sendable {
    let rawASRText: String
    let normalizedText: String
    let languageCode: String
    let outputProfile: OutputProfile
    let formattingModelID: FormattingModelID
    let protectedTerms: [String]
    let defaultCodeStyle: CodeStyle
    let preferredMode: FormattingMode
}

struct TextFormatterResult: Sendable {
    let text: String
    let usedDeterministicFallback: Bool
    let pipelineDecision: PipelineDecision
    let fallbackReason: FallbackReason?
    let rejectedIntroducedTokens: [String]
    let llmInputLength: Int?
    let llmOutputLength: Int?
    let llmRecall: Double?
    let llmValidationDecision: String?

    static func deterministic(_ text: String) -> TextFormatterResult {
        TextFormatterResult(
            text: text,
            usedDeterministicFallback: false,
            pipelineDecision: .deterministicOnly,
            fallbackReason: nil,
            rejectedIntroducedTokens: [],
            llmInputLength: nil,
            llmOutputLength: nil,
            llmRecall: nil,
            llmValidationDecision: nil
        )
    }
}

protocol TextFormatter {
    func format(_ context: TextFormatterContext) async -> TextFormatterResult
}
