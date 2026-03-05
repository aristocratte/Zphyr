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
import ServiceManagement

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
    var totalBytes: Int64 = 0
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
        let received = Double(bytesReceived)
        let total = Double(totalBytes)
        let mb = received / 1_000_000
        let totalMB = total / 1_000_000

        if received < 1_000_000 {
            let kb = received / 1_000
            return String(format: "%.0f KB / %.0f MB", kb, totalMB)
        }
        if received < 100_000_000 {
            return String(format: "%.1f / %.0f MB", mb, totalMB)
        }
        return String(format: "%.0f / %.0f MB", mb, totalMB)
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

// MARK: - Formatting Mode
enum FormattingMode: String, CaseIterable, Identifiable {
    case trigger  = "trigger"
    case advanced = "advanced"

    var id: String { rawValue }

    func displayName(for lang: String) -> String {
        switch self {
        case .trigger:
            return L10n.ui(for: lang, fr: "Normal (Trigger explicite)", en: "Normal (Explicit trigger)", es: "Normal (disparador)", zh: "普通（显式触发）", ja: "通常（明示的トリガー）", ru: "Обычный (триггер)")
        case .advanced:
            return L10n.ui(for: lang, fr: "Avancé (IA locale Qwen3-1.7B)", en: "Advanced (local AI Qwen3-1.7B)", es: "Avanzado (IA local Qwen3-1.7B)", zh: "高级（本地 AI Qwen3-1.7B）", ja: "高度（ローカル AI Qwen3-1.7B）", ru: "Расширенный (локальный ИИ Qwen3-1.7B)")
        }
    }

    func subtitle(for lang: String) -> String {
        switch self {
        case .trigger:
            return L10n.ui(for: lang, fr: "Dites «camel get user» → getUserProfile", en: "Say «camel get user» → getUserProfile", es: "Di «camel get user» → getUserProfile", zh: "说「camel get user」→ getUserProfile", ja: "「camel get user」→ getUserProfile", ru: "«camel get user» → getUserProfile")
        case .advanced:
            return L10n.ui(for: lang, fr: "Qwen3-1.7B détecte les identifiants sans mot-clé (~1,1 Go, local)", en: "Qwen3-1.7B auto-detects identifiers without trigger (~1.1 GB, local)", es: "Qwen3-1.7B detecta identificadores sin disparador (~1,1 GB, local)", zh: "Qwen3-1.7B 自动检测标识符无需触发词（~1.1 GB，本地）", ja: "Qwen3-1.7B がトリガーなしで自動検出（~1.1 GB、ローカル）", ru: "Qwen3-1.7B автоопределяет идентификаторы без триггера (~1,1 ГБ, локально)")
        }
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
    case formatting   // LLM post-processing (Qwen advanced mode)
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
    private static let stylePersonalKey = "zphyr.style.personal"
    private static let styleWorkKey = "zphyr.style.work"
    private static let styleEmailKey = "zphyr.style.email"
    private static let styleOtherKey = "zphyr.style.other"
    private static let preferredASRBackendKey = "zphyr.asr.preferredBackend"
    private var isApplyingPerformanceRouting = false

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
    var modelInstallPath: String? = nil
    var isDownloadPaused: Bool = false
    var preferredASRBackend: ASRBackendKind = {
        let raw = UserDefaults.standard.string(forKey: AppState.preferredASRBackendKey)
        return ASRBackendKind(rawValue: raw ?? "") ?? .appleSpeechAnalyzer
    }() {
        didSet {
            UserDefaults.standard.set(preferredASRBackend.rawValue, forKey: AppState.preferredASRBackendKey)
            enforcePerformanceRouting()
        }
    }
    var activeASRBackend: ASRBackendKind = .appleSpeechAnalyzer
    var qwen3asrInstalled: Bool = false  // deprecated — kept for migration
    var whisperInstalled: Bool = UserDefaults.standard.bool(forKey: "zphyr.whisperInstalled") {
        didSet { UserDefaults.standard.set(whisperInstalled, forKey: "zphyr.whisperInstalled") }
    }

    // Dictation
    var dictationState: DictationState = .idle

    // Audio levels for spectrum HUD
    var audioLevels: [CGFloat] = Array(repeating: 0.15, count: 28)

    // Last result
    var lastTranscription: String = ""

    // Pending dictionary learning suggestion
    var pendingDictionarySuggestion: DictionarySuggestion?

    // Settings — Dictation languages (persisted, supports multiple)
    var selectedLanguages: [WhisperLanguage] = {
        if let saved = UserDefaults.standard.string(forKey: "zphyr.dictation.languages") {
            let ids = saved.split(separator: ",").map(String.init)
            let langs = ids.compactMap { id in WhisperLanguage.all.first(where: { $0.id == id }) }
            if !langs.isEmpty { return langs }
        }
        // Fall back to old single-language key
        let savedSingle = UserDefaults.standard.string(forKey: "zphyr.dictation.language") ?? "fr"
        return [WhisperLanguage.all.first(where: { $0.id == savedSingle }) ?? WhisperLanguage.all.first(where: { $0.id == "fr" })!]
    }() {
        didSet {
            let ids = selectedLanguages.map(\.id).joined(separator: ",")
            UserDefaults.standard.set(ids, forKey: "zphyr.dictation.languages")
            // Also keep old key in sync (first language)
            UserDefaults.standard.set(selectedLanguages.first?.id ?? "fr", forKey: "zphyr.dictation.language")
        }
    }

    // Convenience: primary dictation language
    var selectedLanguage: WhisperLanguage {
        selectedLanguages.first ?? WhisperLanguage.all.first(where: { $0.id == "fr" })!
    }

    // Settings — UI display language (independent from dictation language)
    var uiDisplayLanguage: SupportedUILanguage = {
        let saved = UserDefaults.standard.string(forKey: "zphyr.ui.language") ?? "fr"
        return SupportedUILanguage(rawValue: saved) ?? .fr
    }() {
        didSet { UserDefaults.standard.set(uiDisplayLanguage.rawValue, forKey: "zphyr.ui.language") }
    }

    // Settings — auto-insert (persisted, default true)
    var autoInsert: Bool = {
        let v = UserDefaults.standard.object(forKey: "zphyr.autoInsert")
        return v == nil ? true : UserDefaults.standard.bool(forKey: "zphyr.autoInsert")
    }() {
        didSet { UserDefaults.standard.set(autoInsert, forKey: "zphyr.autoInsert") }
    }

    // Settings — formatting mode (persisted, default .none)
    var formattingMode: FormattingMode = {
        let saved = UserDefaults.standard.string(forKey: "zphyr.formattingMode") ?? "trigger"
        return FormattingMode(rawValue: saved) ?? .trigger
    }() {
        didSet {
            UserDefaults.standard.set(formattingMode.rawValue, forKey: "zphyr.formattingMode")
            enforcePerformanceRouting()
        }
    }

    // Settings — default code style (persisted, default .camel)
    var defaultCodeStyle: CodeStyle = {
        let saved = UserDefaults.standard.string(forKey: "zphyr.codeStyle") ?? "camel"
        return CodeStyle(rawValue: saved) ?? .camel
    }() {
        didSet { UserDefaults.standard.set(defaultCodeStyle.rawValue, forKey: "zphyr.codeStyle") }
    }

    // Settings — advanced LLM mode installation status (persisted)
    var advancedModeInstalled: Bool = {
        UserDefaults.standard.bool(forKey: "zphyr.advancedMode.installed")
    }() {
        didSet { UserDefaults.standard.set(advancedModeInstalled, forKey: "zphyr.advancedMode.installed") }
    }

    // Settings — launch at login (backed by SMAppService)
    private var isSyncingLaunchAtLogin = false
    var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently revert to the actual service state if registration fails.
                syncLaunchAtLoginFromSystem()
            }
        }
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
    var stylePersonal: WritingTone = AppState.loadWritingTone(forKey: AppState.stylePersonalKey, fallback: .casual) {
        didSet { UserDefaults.standard.set(stylePersonal.rawValue, forKey: AppState.stylePersonalKey) }
    }
    var styleWork: WritingTone = AppState.loadWritingTone(forKey: AppState.styleWorkKey, fallback: .formal) {
        didSet { UserDefaults.standard.set(styleWork.rawValue, forKey: AppState.styleWorkKey) }
    }
    var styleEmail: WritingTone = AppState.loadWritingTone(forKey: AppState.styleEmailKey, fallback: .formal) {
        didSet { UserDefaults.standard.set(styleEmail.rawValue, forKey: AppState.styleEmailKey) }
    }
    var styleOther: WritingTone = AppState.loadWritingTone(forKey: AppState.styleOtherKey, fallback: .casual) {
        didSet { UserDefaults.standard.set(styleOther.rawValue, forKey: AppState.styleOtherKey) }
    }

    // Transient error to surface in UI
    var error: String?
    var performanceProfile: PerformanceProfile = PerformanceRouter.shared.currentProfile()

    var isProModeUnlocked: Bool {
        performanceProfile.allowsProMode
    }

    var isWhisperASRUnlocked: Bool {
        performanceProfile.allowsWhisperASR
    }

    private init() {
        refreshPerformanceProfile()
        refreshMicPermission()
        refreshAccessibility()
    }

    func refreshPerformanceProfile() {
        performanceProfile = PerformanceRouter.shared.currentProfile()
        enforcePerformanceRouting()
    }

    func enforcePerformanceRouting() {
        guard !isApplyingPerformanceRouting else { return }
        isApplyingPerformanceRouting = true
        defer { isApplyingPerformanceRouting = false }

        let router = PerformanceRouter.shared
        let profile = performanceProfile

        let effectiveBackend = router.effectiveASRBackend(preferred: preferredASRBackend, profile: profile)
        if preferredASRBackend != effectiveBackend {
            preferredASRBackend = effectiveBackend
        }

        let effectiveMode = router.effectiveFormattingMode(preferred: formattingMode, profile: profile)
        if formattingMode != effectiveMode {
            formattingMode = effectiveMode
        }
    }

    private func syncLaunchAtLoginFromSystem() {
        let actual = (SMAppService.mainApp.status == .enabled)
        guard launchAtLogin != actual else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = actual
        isSyncingLaunchAtLogin = false
    }

    private static func loadWritingTone(forKey key: String, fallback: WritingTone) -> WritingTone {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let tone = WritingTone(rawValue: raw) else {
            return fallback
        }
        return tone
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

    private var lastAudioLevelRefresh: Date = .distantPast

    // MARK: - Audio levels helper (called from audio thread)
    func updateAudioLevels(_ levels: [Float]) {
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelRefresh) >= 0.08 else { return }
        lastAudioLevelRefresh = now
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
            Self.dictionaryLogger.notice("[DictionarySuggestion] ignored (already in dictionary): \(mistaken, privacy: .private(mask: .hash)) -> \(corrected, privacy: .private(mask: .hash))")
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
        Self.dictionaryLogger.notice("[DictionarySuggestion] presenting: \(mistaken, privacy: .private(mask: .hash)) -> \(corrected, privacy: .private(mask: .hash))")
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
