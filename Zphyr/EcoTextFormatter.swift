import Foundation

struct EcoTextFormatter: TextFormatter {
    private let codeFormatter = CodeFormatter()

    func format(_ context: TextFormatterContext) async -> TextFormatterResult {
        let text: String
        switch context.outputProfile {
        case .verbatim:
            text = context.normalizedText
        case .clean, .email:
            switch context.preferredMode {
            case .trigger:
                text = codeFormatter.formatTranscribedText(context.normalizedText, defaultStyle: context.defaultCodeStyle)
            case .advanced:
                text = codeFormatter.formatAdvanced(context.normalizedText, defaultStyle: context.defaultCodeStyle)
            }
        case .technical:
            text = codeFormatter.formatAdvanced(context.normalizedText, defaultStyle: context.defaultCodeStyle)
        }

        return TextFormatterResult.deterministic(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
