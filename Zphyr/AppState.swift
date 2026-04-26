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
            return L10n.ui(for: lang, fr: "Avancé (IA locale)", en: "Advanced (local AI)", es: "Avanzado (IA local)", zh: "高级（本地 AI）", ja: "高度（ローカル AI）", ru: "Расширенный (локальный ИИ)")
        }
    }

    func subtitle(for lang: String) -> String {
        switch self {
        case .trigger:
            return L10n.ui(for: lang, fr: "Dites «camel get user» → getUserProfile", en: "Say «camel get user» → getUserProfile", es: "Di «camel get user» → getUserProfile", zh: "说「camel get user」→ getUserProfile", ja: "「camel get user」→ getUserProfile", ru: "«camel get user» → getUserProfile")
        case .advanced:
            return L10n.ui(for: lang, fr: "Utilise le modèle de formatage local sélectionné pour aller au-delà des règles déterministes.", en: "Uses the selected local formatting model beyond deterministic rules.", es: "Usa el modelo local de formateo seleccionado más allá de las reglas deterministas.", zh: "使用所选本地格式化模型，超出确定性规则。", ja: "選択したローカル整形モデルで決定論ルールを拡張します。", ru: "Использует выбранную локальную модель форматирования поверх детерминированных правил.")
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

enum DictationSessionPhase: String, CaseIterable, Equatable, Codable, Sendable {
    case arming
    case recording
    case retrying
    case transcribing
    case formatting
    case inserting
    case success
    case failure
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .success, .failure, .cancelled:
            return true
        default:
            return false
        }
    }
}

struct LiveTranscriptionState: Equatable, Codable, Sendable {
    var mode: ASRTranscriptionMode
    var partialText: String?
    var finalText: String?
    var lastPartialAt: Date?
    var lastFinalAt: Date?

    var displayText: String? {
        let partial = partialText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let partial, !partial.isEmpty { return partial }
        let final = finalText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let final, !final.isEmpty { return final }
        return nil
    }
}

struct DictationSessionTransition: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let phase: DictationSessionPhase
    let timestamp: Date
    let note: String?

    init(
        id: UUID = UUID(),
        phase: DictationSessionPhase,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.timestamp = timestamp
        self.note = note
    }
}

struct DictationSession: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var targetBundleID: String?
    var phase: DictationSessionPhase
    var outputProfile: OutputProfile
    var liveTranscription: LiveTranscriptionState
    var pipelineDecision: PipelineDecision?
    var pipelineFallbackReason: FallbackReason?
    var pipelineTrace: [StageTrace]
    var insertionStrategy: InsertionStrategy?
    var insertionFallbackReason: FallbackReason?
    var finalTextPreview: String?
    var finalFormattedText: String?
    var errorMessage: String?
    var transitions: [DictationSessionTransition]

    var isActive: Bool { !phase.isTerminal }

    var latestFallbackReason: FallbackReason? {
        insertionFallbackReason ?? pipelineFallbackReason
    }
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
    private nonisolated static let settingsLogger = Logger(subsystem: "com.zphyr.app", category: "SettingsRouting")
    private nonisolated static let sessionLogger = Logger(subsystem: "com.zphyr.app", category: "DictationSession")
    private static let stylePersonalKey = "zphyr.style.personal"
    private static let styleWorkKey = "zphyr.style.work"
    private static let styleEmailKey = "zphyr.style.email"
    private static let styleOtherKey = "zphyr.style.other"
    private static let outputProfilePersonalKey = "zphyr.outputProfile.personal"
    private static let outputProfileWorkKey = "zphyr.outputProfile.work"
    private static let outputProfileEmailKey = "zphyr.outputProfile.email"
    private static let outputProfileOtherKey = "zphyr.outputProfile.other"
    private static let preferredASRBackendKey = "zphyr.asr.preferredBackend"
    private static let activeFormattingModelKey = "zphyr.formatter.activeModel"
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
        let decoded = ASRBackendKind(rawValue: raw ?? "") ?? .whisperKit
        // Migration: Parakeet is no longer a user-selectable backend (stub, unimplemented).
        // If the user had it stored, silently reset to Whisper.
        if decoded == .parakeet { return .whisperKit }
        return decoded
    }() {
        didSet {
            UserDefaults.standard.set(preferredASRBackend.rawValue, forKey: AppState.preferredASRBackendKey)
            if preferredASRBackend != oldValue {
                Self.settingsLogger.notice(
                    "[Settings] preferredASRBackend changed from \(oldValue.rawValue, privacy: .public) to \(self.preferredASRBackend.rawValue, privacy: .public)"
                )
            }
            enforcePerformanceRouting()
        }
    }
    var activeASRBackend: ASRBackendKind = .appleSpeechAnalyzer
    var qwen3asrInstalled: Bool = false  // deprecated — kept for migration
    var whisperInstalled: Bool = UserDefaults.standard.bool(forKey: "zphyr.whisperInstalled") {
        didSet { UserDefaults.standard.set(whisperInstalled, forKey: "zphyr.whisperInstalled") }
    }
    var parakeetInstalled: Bool = UserDefaults.standard.bool(forKey: "zphyr.parakeetInstalled") {
        didSet { UserDefaults.standard.set(parakeetInstalled, forKey: "zphyr.parakeetInstalled") }
    }
    // Dictation
    var dictationState: DictationState = .idle
    var currentDictationSession: DictationSession?
    var lastCompletedDictationSession: DictationSession?
    var retryLastSessionAvailable: Bool = false

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
        return [WhisperLanguage.all.first(where: { $0.id == savedSingle })
            ?? WhisperLanguage.all.first(where: { $0.id == "fr" })
            ?? WhisperLanguage.all[0]]
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
        selectedLanguages.first ?? WhisperLanguage.all.first(where: { $0.id == "fr" }) ?? WhisperLanguage.all[0]
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
            if formattingMode != oldValue {
                Self.settingsLogger.notice(
                    "[Settings] formattingMode changed from \(oldValue.rawValue, privacy: .public) to \(self.formattingMode.rawValue, privacy: .public) (tier=\(self.performanceProfile.tier.rawValue, privacy: .public))"
                )
            }
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
        didSet {
            UserDefaults.standard.set(advancedModeInstalled, forKey: "zphyr.advancedMode.installed")
            if advancedModeInstalled != oldValue {
                Self.settingsLogger.notice(
                    "[Settings] advancedModeInstalled changed from \(oldValue, privacy: .public) to \(self.advancedModeInstalled, privacy: .public)"
                )
            }
        }
    }

    var activeFormattingModel: FormattingModelID = {
        // Deprecated raw values (legacy_zphyr_v1, smollm3_3b, gemma3_4b) decode as nil → migrate to .qwen3_4b
        let saved = UserDefaults.standard.string(forKey: AppState.activeFormattingModelKey) ?? FormattingModelID.qwen3_4b.rawValue
        return FormattingModelID(rawValue: saved) ?? .qwen3_4b
    }() {
        didSet {
            UserDefaults.standard.set(activeFormattingModel.rawValue, forKey: AppState.activeFormattingModelKey)
            if activeFormattingModel != oldValue {
                Self.settingsLogger.notice(
                    "[Settings] activeFormattingModel changed from \(oldValue.rawValue, privacy: .public) to \(self.activeFormattingModel.rawValue, privacy: .public)"
                )
            }
            syncActiveFormattingModelInstallState()
        }
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

    var defaultOutputProfile: OutputProfile {
        get { outputProfileOther }
        set { outputProfileOther = newValue }
    }

    var activeFormattingModelDescriptor: FormattingModelDescriptor {
        FormattingModelCatalog.descriptor(for: activeFormattingModel)
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
    var outputProfilePersonal: OutputProfile = AppState.loadOutputProfile(
        forKey: AppState.outputProfilePersonalKey,
        fallback: .clean
    ) {
        didSet { UserDefaults.standard.set(outputProfilePersonal.rawValue, forKey: AppState.outputProfilePersonalKey) }
    }
    var outputProfileWork: OutputProfile = AppState.loadOutputProfile(
        forKey: AppState.outputProfileWorkKey,
        fallback: .technical
    ) {
        didSet { UserDefaults.standard.set(outputProfileWork.rawValue, forKey: AppState.outputProfileWorkKey) }
    }
    var outputProfileEmail: OutputProfile = AppState.loadOutputProfile(
        forKey: AppState.outputProfileEmailKey,
        fallback: .email
    ) {
        didSet { UserDefaults.standard.set(outputProfileEmail.rawValue, forKey: AppState.outputProfileEmailKey) }
    }
    var outputProfileOther: OutputProfile = AppState.loadOutputProfile(
        forKey: AppState.outputProfileOtherKey,
        fallback: .clean
    ) {
        didSet { UserDefaults.standard.set(outputProfileOther.rawValue, forKey: AppState.outputProfileOtherKey) }
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

    var latestDictationSession: DictationSession? {
        currentDictationSession ?? lastCompletedDictationSession
    }

    private init() {
        refreshPerformanceProfile()
        refreshMicPermission()
        refreshAccessibility()
        syncActiveFormattingModelInstallState()
    }

    func syncActiveFormattingModelInstallState() {
        let installed = AdvancedLLMFormatter.resolveInstallURL(for: activeFormattingModel) != nil
        if advancedModeInstalled != installed {
            advancedModeInstalled = installed
        }
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
            Self.settingsLogger.notice(
                "[Routing] forcing ASR backend from \(self.preferredASRBackend.rawValue, privacy: .public) to \(effectiveBackend.rawValue, privacy: .public) (tier=\(profile.tier.rawValue, privacy: .public))"
            )
            preferredASRBackend = effectiveBackend
        }

        let effectiveMode = router.effectiveFormattingMode(preferred: formattingMode, profile: profile)
        if formattingMode != effectiveMode {
            Self.settingsLogger.notice(
                "[Routing] forcing formatting mode from \(self.formattingMode.rawValue, privacy: .public) to \(effectiveMode.rawValue, privacy: .public) (tier=\(profile.tier.rawValue, privacy: .public))"
            )
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

    private static func loadOutputProfile(forKey key: String, fallback: OutputProfile) -> OutputProfile {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let profile = OutputProfile(rawValue: raw) else {
            return fallback
        }
        return profile
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

    // MARK: - Dictation session flow

    @discardableResult
    func beginDictationSession(
        targetBundleID: String?,
        transcriptionMode: ASRTranscriptionMode = .finalOnly,
        outputProfile: OutputProfile = .clean
    ) -> UUID {
        let session = DictationSession(
            id: UUID(),
            startedAt: Date(),
            updatedAt: Date(),
            endedAt: nil,
            targetBundleID: targetBundleID,
            phase: .arming,
            outputProfile: outputProfile,
            liveTranscription: LiveTranscriptionState(
                mode: transcriptionMode,
                partialText: nil,
                finalText: nil,
                lastPartialAt: nil,
                lastFinalAt: nil
            ),
            pipelineDecision: nil,
            pipelineFallbackReason: nil,
            pipelineTrace: [],
            insertionStrategy: nil,
            insertionFallbackReason: nil,
            finalTextPreview: nil,
            finalFormattedText: nil,
            errorMessage: nil,
            transitions: [DictationSessionTransition(phase: .arming)]
        )
        currentDictationSession = session
        syncLegacyDictationState(for: .arming, preview: nil)
        Self.sessionLogger.notice(
            "[Session] began id=\(session.id.uuidString, privacy: .public) target=\(targetBundleID ?? "nil", privacy: .public) transcriptionMode=\(transcriptionMode.rawValue, privacy: .public) outputProfile=\(outputProfile.rawValue, privacy: .public)"
        )
        return session.id
    }

    func transitionCurrentDictationSession(
        to phase: DictationSessionPhase,
        note: String? = nil
    ) {
        guard var session = currentDictationSession else { return }
        if session.phase == phase && note == nil { return }
        let now = Date()
        session.phase = phase
        session.updatedAt = now
        session.transitions.append(
            DictationSessionTransition(phase: phase, timestamp: now, note: note)
        )
        currentDictationSession = session
        syncLegacyDictationState(for: phase, preview: session.finalTextPreview)
        Self.sessionLogger.notice(
            "[Session] transition id=\(session.id.uuidString, privacy: .public) phase=\(phase.rawValue, privacy: .public) note=\(note ?? "none", privacy: .public)"
        )
    }

    func updateCurrentDictationSession(
        pipelineDecision: PipelineDecision? = nil,
        pipelineFallbackReason: FallbackReason? = nil,
        pipelineTrace: [StageTrace]? = nil,
        insertionStrategy: InsertionStrategy? = nil,
        insertionFallbackReason: FallbackReason? = nil,
        finalTextPreview: String? = nil,
        errorMessage: String? = nil
    ) {
        guard var session = currentDictationSession else { return }
        session.updatedAt = Date()
        if let pipelineDecision {
            session.pipelineDecision = pipelineDecision
        }
        if let pipelineFallbackReason {
            session.pipelineFallbackReason = pipelineFallbackReason
        }
        if let pipelineTrace {
            session.pipelineTrace = pipelineTrace
        }
        if let insertionStrategy {
            session.insertionStrategy = insertionStrategy
        }
        if let insertionFallbackReason {
            session.insertionFallbackReason = insertionFallbackReason
        }
        if let finalTextPreview {
            session.finalFormattedText = finalTextPreview
            session.finalTextPreview = String(finalTextPreview.prefix(140))
        }
        if let errorMessage {
            session.errorMessage = errorMessage
        }
        currentDictationSession = session
    }

    func presentDictationHUDMessage(_ message: String) {
        error = nil
        updateCurrentDictationSession(errorMessage: message)
    }

    func updateCurrentLiveTranscription(
        partialText: String? = nil,
        clearPartialText: Bool = false,
        finalText: String? = nil,
        mode: ASRTranscriptionMode? = nil
    ) {
        guard var session = currentDictationSession else { return }
        let now = Date()
        if let mode {
            session.liveTranscription.mode = mode
        }
        if clearPartialText {
            session.liveTranscription.partialText = nil
            session.liveTranscription.lastPartialAt = nil
        } else if let partialText {
            let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            session.liveTranscription.partialText = trimmed.isEmpty ? nil : trimmed
            session.liveTranscription.lastPartialAt = trimmed.isEmpty ? nil : now
        }
        if let finalText {
            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            session.liveTranscription.finalText = trimmed.isEmpty ? nil : trimmed
            session.liveTranscription.lastFinalAt = trimmed.isEmpty ? nil : now
        }
        session.updatedAt = now
        currentDictationSession = session
    }

    func finishCurrentDictationSession(
        phase: DictationSessionPhase,
        note: String? = nil,
        finalTextPreview: String? = nil,
        pipelineDecision: PipelineDecision? = nil,
        pipelineFallbackReason: FallbackReason? = nil,
        pipelineTrace: [StageTrace]? = nil,
        insertionStrategy: InsertionStrategy? = nil,
        insertionFallbackReason: FallbackReason? = nil,
        errorMessage: String? = nil
    ) {
        guard var session = currentDictationSession else { return }
        let now = Date()
        session.phase = phase
        session.updatedAt = now
        session.endedAt = now
        if let pipelineDecision {
            session.pipelineDecision = pipelineDecision
        }
        if let pipelineFallbackReason {
            session.pipelineFallbackReason = pipelineFallbackReason
        }
        if let pipelineTrace {
            session.pipelineTrace = pipelineTrace
        }
        if let insertionStrategy {
            session.insertionStrategy = insertionStrategy
        }
        if let insertionFallbackReason {
            session.insertionFallbackReason = insertionFallbackReason
        }
        if let finalTextPreview {
            session.finalFormattedText = finalTextPreview
            session.finalTextPreview = String(finalTextPreview.prefix(140))
        }
        if let errorMessage {
            session.errorMessage = errorMessage
            error = nil
        }
        session.transitions.append(
            DictationSessionTransition(phase: phase, timestamp: now, note: note)
        )
        lastCompletedDictationSession = session
        currentDictationSession = nil
        syncLegacyDictationState(for: phase, preview: session.finalTextPreview)
        Self.sessionLogger.notice(
            "[Session] finished id=\(session.id.uuidString, privacy: .public) phase=\(phase.rawValue, privacy: .public) decision=\(session.pipelineDecision?.rawValue ?? "none", privacy: .public) insertion=\(session.insertionStrategy?.rawValue ?? "none", privacy: .public) fallback=\(session.latestFallbackReason?.rawValue ?? "none", privacy: .public)"
        )
    }

    func resetLegacyDictationState() {
        dictationState = .idle
    }

    func activeOutputProfile(for bundleID: String?) -> OutputProfile {
        guard let bundleID else { return outputProfileOther }
        let lower = bundleID.lowercased()
        if lower.contains("mail") || lower.contains("outlook") ||
            lower.contains("mimestream") || lower.contains("spark") || lower.contains("airmail") {
            return outputProfileEmail
        }
        if lower.contains("messages") || lower.contains("whatsapp") ||
            lower.contains("telegram") || lower.contains("signal") || lower.contains("discord") {
            return outputProfilePersonal
        }
        if lower.contains("xcode") || lower.contains("code") ||
            lower.contains("jetbrains") || lower.contains("iterm") || lower.contains("terminal") ||
            lower.contains("warp") || lower.contains("zed") || lower.contains("cursor") ||
            lower.contains("nova") || lower.contains("slack") || lower.contains("teams") ||
            lower.contains("notion") || lower.contains("linear") || lower.contains("jira") ||
            lower.contains("confluence") || lower.contains("zoom") {
            return outputProfileWork
        }
        return outputProfileOther
    }

    private func syncLegacyDictationState(for phase: DictationSessionPhase, preview: String?) {
        switch phase {
        case .arming, .retrying, .transcribing, .inserting:
            dictationState = .processing
        case .recording:
            dictationState = .listening
        case .formatting:
            dictationState = .formatting
        case .success:
            dictationState = .done(text: preview ?? "")
        case .failure, .cancelled:
            dictationState = .idle
        }
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
