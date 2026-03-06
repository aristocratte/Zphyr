//
//  WhisperLanguage.swift
//  Zphyr
//
//  Supported dictation languages for Whisper ASR.
//

import Foundation

// MARK: - Supported Languages

struct WhisperLanguage: Identifiable, Hashable {
    let id: String        // BCP-47 dictation language code
    let name: String
    let flag: String

    enum Tier { case excellent, good }
    let tier: Tier
}

extension WhisperLanguage {
    static let all: [WhisperLanguage] = [
        // Whisper Large v3 Turbo supported languages
        WhisperLanguage(id: "zh", name: "中文（普通话）",       flag: "🇨🇳", tier: .excellent),
        WhisperLanguage(id: "en", name: "English",           flag: "🇺🇸", tier: .excellent),
        WhisperLanguage(id: "ar", name: "العربية",            flag: "🇸🇦", tier: .excellent),
        WhisperLanguage(id: "de", name: "Deutsch",           flag: "🇩🇪", tier: .excellent),
        WhisperLanguage(id: "fr", name: "Français",          flag: "🇫🇷", tier: .excellent),
        WhisperLanguage(id: "es", name: "Español",           flag: "🇪🇸", tier: .excellent),
        WhisperLanguage(id: "pt", name: "Português",         flag: "🇵🇹", tier: .excellent),
        WhisperLanguage(id: "id", name: "Bahasa Indonesia",  flag: "🇮🇩", tier: .good),
        WhisperLanguage(id: "it", name: "Italiano",          flag: "🇮🇹", tier: .excellent),
        WhisperLanguage(id: "ko", name: "한국어",              flag: "🇰🇷", tier: .excellent),
        WhisperLanguage(id: "ru", name: "Русский",           flag: "🇷🇺", tier: .excellent),
        WhisperLanguage(id: "th", name: "ภาษาไทย",           flag: "🇹🇭", tier: .good),
        WhisperLanguage(id: "vi", name: "Tiếng Việt",        flag: "🇻🇳", tier: .good),
        WhisperLanguage(id: "ja", name: "日本語",              flag: "🇯🇵", tier: .excellent),
        WhisperLanguage(id: "tr", name: "Türkçe",            flag: "🇹🇷", tier: .good),
        WhisperLanguage(id: "hi", name: "हिन्दी",              flag: "🇮🇳", tier: .good),
        WhisperLanguage(id: "ms", name: "Bahasa Melayu",     flag: "🇲🇾", tier: .good),
        WhisperLanguage(id: "nl", name: "Nederlands",        flag: "🇳🇱", tier: .excellent),
        WhisperLanguage(id: "sv", name: "Svenska",           flag: "🇸🇪", tier: .good),
        WhisperLanguage(id: "da", name: "Dansk",             flag: "🇩🇰", tier: .good),
        WhisperLanguage(id: "fi", name: "Suomi",             flag: "🇫🇮", tier: .good),
        WhisperLanguage(id: "pl", name: "Polski",            flag: "🇵🇱", tier: .excellent),
        WhisperLanguage(id: "cs", name: "Čeština",           flag: "🇨🇿", tier: .good),
        WhisperLanguage(id: "tl", name: "Filipino",          flag: "🇵🇭", tier: .good),
        WhisperLanguage(id: "fa", name: "فارسی",             flag: "🇮🇷", tier: .good),
        WhisperLanguage(id: "el", name: "Ελληνικά",          flag: "🇬🇷", tier: .good),
        WhisperLanguage(id: "hu", name: "Magyar",            flag: "🇭🇺", tier: .good),
        WhisperLanguage(id: "ro", name: "Română",            flag: "🇷🇴", tier: .good),
        WhisperLanguage(id: "mk", name: "Македонски",        flag: "🇲🇰", tier: .good),
        WhisperLanguage(id: "yue", name: "粵語",               flag: "🇭🇰", tier: .good),
    ]
}
