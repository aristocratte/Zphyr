//
//  ContextFetcher.swift
//  Zphyr
//
//  Uses Accessibility APIs to extract identifiers (camelCase, snake_case, PascalCase)
//  from the frontmost application's focused UI element.
//  These are injected into the Whisper initial_prompt to boost recognition accuracy.
//

import AppKit

struct ContextFetcher {

    // MARK: - Public API

    /// Returns a deduplicated array of code-style tokens from the frontmost app's text.
    /// Falls back to an empty array if Accessibility is not granted or nothing is found.
    static func fetchCodeTokens() -> [String] {
        guard AXIsProcessTrusted() else { return [] }

        let systemElement = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success, let element = axElement(from: focusedElement) else { return [] }

        // Only use selected text (privacy-first): avoid collecting full field/window content.
        if let selected = stringAttribute(element, attribute: kAXSelectedTextAttribute) {
            let tokens = extractTokens(from: selected)
            if !tokens.isEmpty { return tokens }
        }

        return []
    }

    /// Builds the Whisper initial_prompt string from extracted tokens and custom dictionary.
    @MainActor
    static func buildWhisperPrompt(language: String, tokens: [String]) -> String {
        var parts: [String] = []

        parts.append(
            L10n.ui(
                for: language,
                fr: "Ceci est une transcription de code ou de documentation technique.",
                en: "This is a transcription of code or technical documentation.",
                es: "Esta es una transcripción de código o documentación técnica.",
                zh: "这是代码或技术文档的转写。",
                ja: "これはコードまたは技術ドキュメントの文字起こしです。",
                ru: "Это транскрипция кода или технической документации."
            )
        )

        if !tokens.isEmpty {
            let sample = Array(tokens.prefix(30)).joined(separator: ", ")
            parts.append(
                L10n.ui(
                    for: language,
                    fr: "Contexte du code : \(sample).",
                    en: "Code context: \(sample).",
                    es: "Contexto de código: \(sample).",
                    zh: "代码上下文：\(sample)。",
                    ja: "コード文脈: \(sample)。",
                    ru: "Контекст кода: \(sample)."
                )
            )
        }

        // Inject custom dictionary words for better recognition
        let dictWords = DictionaryStore.shared.wordsForPrompt
        if !dictWords.isEmpty {
            let sample = Array(dictWords.prefix(40)).joined(separator: ", ")
            parts.append(
                L10n.ui(
                    for: language,
                    fr: "Vocabulaire personnalisé : \(sample).",
                    en: "Custom vocabulary: \(sample).",
                    es: "Vocabulario personalizado: \(sample).",
                    zh: "自定义词汇：\(sample)。",
                    ja: "カスタム語彙: \(sample)。",
                    ru: "Пользовательский словарь: \(sample)."
                )
            )
        }

        let spokenHints = DictionaryStore.shared.spokenHintsForPrompt
        if !spokenHints.isEmpty {
            let sample = Array(spokenHints.prefix(20)).joined(separator: ", ")
            parts.append(
                L10n.ui(
                    for: language,
                    fr: "Prononciations personnalisées : \(sample).",
                    en: "Custom pronunciations: \(sample).",
                    es: "Pronunciaciones personalizadas: \(sample).",
                    zh: "自定义发音：\(sample)。",
                    ja: "カスタム発音: \(sample)。",
                    ru: "Пользовательские произношения: \(sample)."
                )
            )
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Private helpers

    private static func stringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let str = value as? String, !str.isEmpty else { return nil }
        return str
    }

    private static func axElement(from value: AnyObject?) -> AXUIElement? {
        guard let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Extracts camelCase, PascalCase, snake_case, SCREAMING_SNAKE_CASE identifiers.
    private static func extractTokens(from text: String) -> [String] {
        // Limit text size to avoid regex timeout on huge files
        let capped = String(text.prefix(8000))

        // Pattern covers:
        //   camelCase / PascalCase : starts lowercase or uppercase, contains mixed case
        //   snake_case / SCREAMING : word chars separated by underscores
        let pattern = #"\b[a-zA-Z][a-zA-Z0-9]*(?:_[a-zA-Z0-9]+)+\b|\b[a-z][a-z0-9]*(?:[A-Z][a-z0-9]*)+\b|\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(capped.startIndex..., in: capped)
        let matches = regex.matches(in: capped, range: range)

        let tokens = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: capped) else { return nil }
            return String(capped[range])
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }
}
