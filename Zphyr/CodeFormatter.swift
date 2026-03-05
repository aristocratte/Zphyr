//
//  CodeFormatter.swift
//  Zphyr
//
//  Mode Trigger explicite : détecte les mots-clés "camel", "snake", "pascal", etc.
//  dans le texte transcrit et reformate les mots qui suivent sans aucun LLM externe.
//
//  Exemples :
//    "camel audio url"          → audioURL
//    "snake get user profile"   → get_user_profile
//    "pascal base view model"   → BaseViewModel
//    "screaming api key"        → API_KEY
//    "kebab my component"       → my-component
//

import Foundation

enum CodeStyle: String, CaseIterable, Identifiable {
    case camel     = "camel"
    case snake     = "snake"
    case pascal    = "pascal"
    case screaming = "screaming"
    case kebab     = "kebab"

    var id: String { rawValue }

    func displayName(for lang: String) -> String {
        switch self {
        case .camel:     return L10n.ui(for: lang, fr: "camelCase", en: "camelCase", es: "camelCase", zh: "camelCase", ja: "camelCase", ru: "camelCase")
        case .snake:     return L10n.ui(for: lang, fr: "snake_case", en: "snake_case", es: "snake_case", zh: "snake_case", ja: "snake_case", ru: "snake_case")
        case .pascal:    return L10n.ui(for: lang, fr: "PascalCase", en: "PascalCase", es: "PascalCase", zh: "PascalCase", ja: "PascalCase", ru: "PascalCase")
        case .screaming: return L10n.ui(for: lang, fr: "SCREAMING_SNAKE", en: "SCREAMING_SNAKE", es: "SCREAMING_SNAKE", zh: "SCREAMING_SNAKE", ja: "SCREAMING_SNAKE", ru: "SCREAMING_SNAKE")
        case .kebab:     return L10n.ui(for: lang, fr: "kebab-case", en: "kebab-case", es: "kebab-case", zh: "kebab-case", ja: "kebab-case", ru: "kebab-case")
        }
    }
}

final class CodeFormatter {

    // Matches: <style> <words…>  optionally followed by a preposition/article
    // Handles French and English stop-words so the identifier boundary is clean.
    private let triggerRegex = try? NSRegularExpression(
        pattern: #"\b(camel|snake|pascal|screaming|kebab)\s+([a-zA-ZÀ-ÿ0-9\s]+?)(?=\s+(?:en|dans|pour|avec|sur|with|in|to|for|at|of|the|a|de|du|la|le|les|un|une|et|ou)\b|[,;.!?]|$)"#,
        options: [.caseInsensitive]
    )
    private let advancedRegex: NSRegularExpression? = {
        let keywordList = "variable|var|fonction|function|méthode|method|clase|función|método|tipo|parámetro|funktion|klasse|methode|konstante|переменная|функция|метод|класс|константа|параметр|classe|class|const|let|constante|type|param|paramètre|parameter"
        let stopWordList = "en|dans|pour|avec|sur|with|in|to|for|at|of|the|a|de|du|la|le|les|un|une|et|ou|puis|ensuite|ici|là|python|swift|javascript|typescript|rust|golang|kotlin|go|js|ts|py"
        let pattern = #"\b(?:"# + keywordList + #")\s+([a-zA-ZÀ-ÿ0-9](?:\s+[a-zA-ZÀ-ÿ0-9]){1,4})(?=\s+(?:"# + stopWordList + #")\b|[,;.!?]|$)"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Scans `text` for trigger keywords and replaces matched spans with the formatted identifier.
    /// Everything outside a trigger span is returned unchanged.
    func formatTranscribedText(_ text: String, defaultStyle: CodeStyle = .camel) -> String {
        guard let triggerRegex else { return text }
        var result = text
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = triggerRegex.matches(in: text, range: range)

        // Process in reverse order so replacements don't shift ranges
        for match in matches.reversed() {
            let styleRaw = nsText.substring(with: match.range(at: 1)).lowercased()
            let wordsRaw = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let style = CodeStyle(rawValue: styleRaw) ?? defaultStyle
            let formatted = formatWords(wordsRaw, style: style)
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: formatted)
            }
        }
        return result
    }

    /// Advanced mode: auto-detects technical keywords and applies language-aware formatting.
    /// No LLM, no network — pure regex, instantaneous.
    ///
    /// Examples:
    ///   "je crée la variable background color red en python" → "je crée la variable background_color_red en python"
    ///   "appel la fonction fetch user data dans le composant" → "appel la fonction fetchUserData dans le composant"
    func formatAdvanced(_ text: String, defaultStyle: CodeStyle) -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        // Determine which style to apply based on language keywords in the text
        let effectiveStyle = detectStyleFromLanguage(in: text) ?? defaultStyle

        // Regex: technical keyword followed by 2–5 words that form the identifier
        // Stops before stop-words, punctuation, or end of string
        guard let advancedRegex else { return text }

        var result = text
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = advancedRegex.matches(in: text, range: range)

        // Process in reverse to preserve offsets
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let wordsRange = match.range(at: 1)
            let wordsRaw = nsText.substring(with: wordsRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formatted = formatWords(wordsRaw, style: effectiveStyle)
            if let swiftRange = Range(wordsRange, in: result) {
                result.replaceSubrange(swiftRange, with: formatted)
            }
        }
        return result
    }

    // MARK: - Language Detection

    private func detectStyleFromLanguage(in text: String) -> CodeStyle? {
        let lower = text.lowercased()
        if lower.contains("python") || lower.contains(" .py") || lower.contains(" py ") || lower.contains("en python") { return .snake }
        if lower.contains(" rust") || lower.contains("en rust") || lower.contains("in rust") { return .snake }
        if lower.contains("swift") { return .camel }
        if lower.contains("javascript") || lower.contains(" js ") || lower.contains("en js") || lower.contains("in js") { return .camel }
        if lower.contains("typescript") || lower.contains(" ts ") || lower.contains("en ts") || lower.contains("in ts") { return .camel }
        if lower.contains("kotlin") { return .camel }
        if lower.contains("golang") || lower.contains("go lang") { return .camel }
        return nil
    }

    // MARK: - Private

    private func formatWords(_ words: String, style: CodeStyle) -> String {
        // Normalise: lower-case, split on whitespace and common separators
        let parts = words
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        switch style {
        case .camel:
            return parts.enumerated().map { idx, w in idx == 0 ? w : w.capitalized }.joined()
        case .snake:
            return parts.joined(separator: "_")
        case .pascal:
            return parts.map { $0.capitalized }.joined()
        case .screaming:
            return parts.map { $0.uppercased() }.joined(separator: "_")
        case .kebab:
            return parts.joined(separator: "-")
        }
    }
}
