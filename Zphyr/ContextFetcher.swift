//
//  ContextFetcher.swift
//  Zphyr
//
//  Builds the Whisper initial_prompt from the user's custom dictionary.
//  All Accessibility / AX code has been removed — no system-wide text access.
//

import Foundation

struct ContextFetcher {

    /// Builds the Whisper initial_prompt from the custom dictionary only.
    /// Injects known words and spoken-form pronunciations so Whisper recognises them.
    @MainActor
    static func buildWhisperPrompt(language: String) -> String {
        var parts: [String] = []

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
}
