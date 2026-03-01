//
//  AppState.swift
//  Zphyr
//
//  Central observable state for the entire app.
//  Single source of truth for permissions, model status, and dictation state.
//

import Foundation
import AVFoundation
import AppKit
import Observation
import os

// MARK: - Model Download/Load status
enum ModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case failed(String)

    var isReady: Bool { self == .ready }

    var label: String {
        switch self {
        case .notDownloaded:         return "Not downloaded"
        case .downloading(let p):    return "Downloading \(Int(p * 100))%"
        case .loading:               return "Loading in memory…"
        case .ready:                 return "Ready"
        case .failed(let msg):       return "Error: \(msg)"
        }
    }

    var progress: Double {
        switch self {
        case .downloading(let p): return p
        case .loading:            return 0.95
        case .ready:              return 1.0
        default:                  return 0
        }
    }
}

// MARK: - Download speed tracking
struct DownloadStats {
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 632 * 1024 * 1024  // ~632 MB default
    var speedBytesPerSec: Double = 0            // smoothed
    var startedAt: Date = Date()

    var formattedSpeed: String {
        if speedBytesPerSec <= 0 { return "" }
        if speedBytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", speedBytesPerSec / 1_000_000)
        }
        return String(format: "%.0f KB/s", speedBytesPerSec / 1_000)
    }

    var formattedReceived: String {
        let mb = Double(bytesReceived) / 1_000_000
        let total = Double(totalBytes) / 1_000_000
        return String(format: "%.0f / %.0f MB", mb, total)
    }

    var eta: String {
        guard speedBytesPerSec > 0 else { return "" }
        let remaining = Double(totalBytes - bytesReceived)
        let secs = remaining / speedBytesPerSec
        if secs < 60  { return String(format: "~%.0fs", secs) }
        if secs < 3600 { return String(format: "~%.0f min", secs / 60) }
        return ""
    }
}

// MARK: - Writing Tone
enum WritingTone: String, CaseIterable, Identifiable {
    case formal      = "Formal"
    case casual      = "Casual"
    case veryCasual  = "Very casual"

    var id: String { rawValue }

    func displayName(for languageCode: String) -> String {
        switch self {
        case .formal:
            return L10n.ui(for: languageCode, fr: "Formel", en: "Formal", es: "Formal", zh: "正式", ja: "フォーマル", ru: "Формальный")
        case .casual:
            return L10n.ui(for: languageCode, fr: "Casual", en: "Casual", es: "Casual", zh: "自然", ja: "カジュアル", ru: "Повседневный")
        case .veryCasual:
            return L10n.ui(for: languageCode, fr: "Très casual", en: "Very casual", es: "Muy casual", zh: "非常随意", ja: "とてもカジュアル", ru: "Очень неформальный")
        }
    }

    func subtitle(for languageCode: String) -> String {
        switch self {
        case .formal:
            return L10n.ui(for: languageCode, fr: "Majuscules + ponctuation", en: "Caps + punctuation", es: "Mayúsculas + puntuación", zh: "首字母大写 + 标点", ja: "大文字 + 句読点", ru: "Заглавные + пунктуация")
        case .casual:
            return L10n.ui(for: languageCode, fr: "Majuscules + moins de ponctuation", en: "Caps + lighter punctuation", es: "Mayúsculas + menos puntuación", zh: "首字母大写 + 更少标点", ja: "大文字 + 少なめの句読点", ru: "Заглавные + меньше пунктуации")
        case .veryCasual:
            return L10n.ui(for: languageCode, fr: "Sans majuscules + sans ponctuation", en: "No caps + no punctuation", es: "Sin mayúsculas + sin puntuación", zh: "无大写 + 无标点", ja: "大文字なし + 句読点なし", ru: "Без заглавных + без пунктуации")
        }
    }

    var icon: String {
        switch self {
        case .formal:     return "textformat.abc"
        case .casual:     return "text.bubble"
        case .veryCasual: return "bubble.left"
        }
    }
}

// MARK: - Dictation state
enum DictationState: Equatable {
    case idle
    case listening
    case processing
    case done(text: String)
}

// MARK: - Mic permission status
enum MicPermission {
    case undetermined, granted, denied
}

// MARK: - Dictionary learning suggestion
struct DictionarySuggestion: Equatable {
    let mistakenWord: String
    let correctedWord: String
}

// MARK: - AppState
@Observable
@MainActor
final class AppState {
    static let shared = AppState()
    private nonisolated static let dictionaryLogger = Logger(subsystem: "com.zphyr.app", category: "DictionarySuggestion")

    // Snippets defaults keys
    static let snippetLinkedInURLKey = "zphyr.snippet.linkedin.url"
    static let snippetSocialURLKey = "zphyr.snippet.social.url"
    static let snippetContactEmailKey = "zphyr.snippet.contact.email"
    static let snippetLinkedInEnabledKey = "zphyr.snippet.linkedin.enabled"
    static let snippetSocialEnabledKey = "zphyr.snippet.social.enabled"
    static let snippetGmailEnabledKey = "zphyr.snippet.gmail.enabled"
    static let snippetVerboseInEmailKey = "zphyr.snippet.email.verbose"
    static let snippetLinkedInTriggersKey = "zphyr.snippet.linkedin.triggers"
    static let snippetSocialTriggersKey = "zphyr.snippet.social.triggers"
    static let snippetGmailTriggersKey = "zphyr.snippet.gmail.triggers"

    // Snippets defaults values
    static let snippetLinkedInDefaultURL = "https://www.linkedin.com/company/zphyr"
    static let snippetSocialDefaultURL = "https://linktr.ee/zphyr"
    static let snippetContactDefaultEmail = "contact@zphyr.app"
    static let snippetLinkedInDefaultTriggers = L10n.defaultSnippetTriggers(for: .linkedIn, languageCode: "fr")
    static let snippetSocialDefaultTriggers = L10n.defaultSnippetTriggers(for: .social, languageCode: "fr")
    static let snippetGmailDefaultTriggers = L10n.defaultSnippetTriggers(for: .gmail, languageCode: "fr")

    // Permissions
    var micPermission: MicPermission = .undetermined
    var accessibilityGranted: Bool = false

    // Model
    var modelStatus: ModelStatus = .notDownloaded
    var downloadStats: DownloadStats = DownloadStats()

    // Dictation
    var dictationState: DictationState = .idle

    // Audio levels for spectrum HUD
    var audioLevels: [CGFloat] = Array(repeating: 0.15, count: 28)

    // Last result
    var lastTranscription: String = ""

    // Pending dictionary learning suggestion
    var pendingDictionarySuggestion: DictionarySuggestion?

    // Settings — Dictation language (persisted)
    var selectedLanguage: WhisperLanguage = {
        let saved = UserDefaults.standard.string(forKey: "zphyr.dictation.language") ?? "fr"
        return WhisperLanguage.all.first(where: { $0.id == saved })
            ?? WhisperLanguage.all.first(where: { $0.id == "fr" })!
    }() {
        didSet { UserDefaults.standard.set(selectedLanguage.id, forKey: "zphyr.dictation.language") }
    }

    // Settings — UI display language (independent from dictation language)
    var uiDisplayLanguage: SupportedUILanguage = {
        let saved = UserDefaults.standard.string(forKey: "zphyr.ui.language") ?? "fr"
        return SupportedUILanguage(rawValue: saved) ?? .fr
    }() {
        didSet { UserDefaults.standard.set(uiDisplayLanguage.rawValue, forKey: "zphyr.ui.language") }
    }

    // Settings — auto-insert (persisted)
    var autoInsert: Bool = UserDefaults.standard.bool(forKey: "zphyr.autoInsert") {
        didSet { UserDefaults.standard.set(autoInsert, forKey: "zphyr.autoInsert") }
    }

    // Settings — launch at login (persisted)
    var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "zphyr.launchAtLogin") {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "zphyr.launchAtLogin") }
    }

    // Settings — sound effects (persisted)
    var soundEffectsEnabled: Bool = {
        let v = UserDefaults.standard.object(forKey: "zphyr.soundEffects")
        return v == nil ? true : UserDefaults.standard.bool(forKey: "zphyr.soundEffects")
    }() {
        didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: "zphyr.soundEffects") }
    }

    var uiLanguage: SupportedUILanguage { uiDisplayLanguage }

    var uiLocale: Locale {
        Locale(identifier: uiDisplayLanguage.localeIdentifier)
    }

    var modelStatusLabel: String {
        L10n.modelStatusLabel(modelStatus, languageCode: uiDisplayLanguage.rawValue)
    }

    var advancedFeaturesNotice: String? {
        L10n.advancedFeaturesNotice(languageCode: uiDisplayLanguage.rawValue)
    }

    // Writing style per context
    var stylePersonal: WritingTone = .casual
    var styleWork: WritingTone = .formal
    var styleEmail: WritingTone = .formal
    var styleOther: WritingTone = .casual

    // Transient error to surface in UI
    var error: String?

    private init() {
        refreshMicPermission()
        refreshAccessibility()
    }

    // MARK: - Permission checks

    func refreshMicPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:               micPermission = .granted
        case .denied:                micPermission = .denied
        case .undetermined:          micPermission = .undetermined
        @unknown default:            micPermission = .undetermined
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
        return granted
    }

    func refreshAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() {
        // Prompt the user to grant accessibility in System Preferences
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshAccessibility()
        }
    }

    // MARK: - Audio levels helper (called from audio thread)
    func updateAudioLevels(_ levels: [Float]) {
        let mapped = levels.prefix(28).map { CGFloat($0) }
        let padded = mapped + Array(repeating: 0.15, count: max(0, 28 - mapped.count))
        audioLevels = padded
    }

    // MARK: - Dictionary suggestion flow
    func proposeDictionarySuggestion(mistakenWord: String, correctedWord: String) {
        let mistaken = mistakenWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correctedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mistaken.isEmpty, !corrected.isEmpty else { return }
        guard mistaken.caseInsensitiveCompare(corrected) != .orderedSame else { return }
        guard !DictionaryStore.shared.containsMapping(mistakenWord: mistaken, correctedWord: corrected) else {
            Self.dictionaryLogger.notice("[DictionarySuggestion] ignored (already in dictionary): \(mistaken, privacy: .public) -> \(corrected, privacy: .public)")
            return
        }

        let suggestion = DictionarySuggestion(
            mistakenWord: mistaken,
            correctedWord: corrected
        )
        if pendingDictionarySuggestion == suggestion {
            Self.dictionaryLogger.notice("[DictionarySuggestion] re-presenting pending suggestion")
            DictionarySuggestionOverlayController.shared.present(suggestion)
            return
        }

        pendingDictionarySuggestion = suggestion
        Self.dictionaryLogger.notice("[DictionarySuggestion] presenting: \(mistaken, privacy: .public) -> \(corrected, privacy: .public)")
        DictionarySuggestionOverlayController.shared.present(suggestion)
    }

    func acceptPendingDictionarySuggestion() {
        guard let suggestion = pendingDictionarySuggestion else { return }
        DictionaryStore.shared.addOrMerge(
            word: suggestion.correctedWord,
            spokenAs: suggestion.mistakenWord
        )
        pendingDictionarySuggestion = nil
        DictionarySuggestionOverlayController.shared.dismiss()
    }

    func dismissPendingDictionarySuggestion() {
        pendingDictionarySuggestion = nil
        DictionarySuggestionOverlayController.shared.dismiss()
    }
}
