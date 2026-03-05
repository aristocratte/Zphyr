//
//  DictationEngine.swift
//  Zphyr
//
//  Audio capture → ASR backend transcription → post-processing → injection.
//  No external LLM. All processing is 100% local.
//

import Foundation
@preconcurrency import AVFoundation
import AppKit
import Observation
import os

private final class AudioSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    enum AppendStatus {
        case appended
        case truncated
        case full
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func reserveCapacity(_ capacity: Int) {
        guard capacity > 0 else { return }
        lock.lock()
        samples.reserveCapacity(capacity)
        lock.unlock()
    }

    func append(_ chunk: [Float], maxSamples: Int) -> AppendStatus {
        chunk.withUnsafeBufferPointer { pointer in
            append(pointer, maxSamples: maxSamples)
        }
    }

    func append(_ chunk: UnsafeBufferPointer<Float>, maxSamples: Int) -> AppendStatus {
        guard !chunk.isEmpty else { return .appended }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, maxSamples - samples.count)
        guard remaining > 0 else { return .full }
        if chunk.count <= remaining {
            samples.append(contentsOf: chunk)
            return .appended
        }
        let prefix = chunk.prefix(remaining)
        samples.append(contentsOf: prefix)
        return .truncated
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

// MARK: - Supported Languages
struct WhisperLanguage: Identifiable, Hashable {
    // Kept as `WhisperLanguage` for API compatibility across the app.
    let id: String        // BCP-47 dictation language code
    let name: String
    let flag: String

    enum Tier { case excellent, good }
    let tier: Tier
}

extension WhisperLanguage {
    static let all: [WhisperLanguage] = [
        // Qwen3-ASR supported languages (30)
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

// MARK: - DictationEngine
@Observable
@MainActor
final class DictationEngine {
    static let shared = DictationEngine()
    private nonisolated static let learningLogger = Logger(subsystem: "com.zphyr.app", category: "DictionaryLearning")
    private nonisolated static let modelLogger = Logger(subsystem: "com.zphyr.app", category: "ModelLoad")
    private nonisolated static let pipelineLogger = Logger(subsystem: "com.zphyr.app", category: "DictationPipeline")

    private enum AudioFileLoadError: Error {
        case invalidBuffer
        case conversionFailed(String)
        case emptyAudio
    }

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let audioSampleBuffer = AudioSampleBuffer()

    /// Prevents overlapping dictation sessions (start/stop race conditions).
    private var isDictating: Bool = false

    /// True while a previous transcription/insertion is still in-flight.
    /// Prevents a new dictation from starting until the pipeline is fully done.
    private var isProcessing: Bool = false

    private let overlayController = DictationOverlayController()

    /// The app that was frontmost when the user started dictating.
    /// We restore focus to it before injecting text.
    private var targetApp: NSRunningApplication?
    private var correctionMonitorTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var didHitAudioCaptureLimit = false
    private var asrBackend: any ASRService
    private let ecoTextFormatter = EcoTextFormatter()
    private let proTextFormatter = ProTextFormatter()
    private let qwenTranscriptionTimeoutSeconds: Double = 8.0
    private var fillerRegexCache: [String: [NSRegularExpression]] = [:]
    private var transitionRuleCache: [String: [TransitionBoundaryRule]] = [:]
    private var formalPunctuationRuleCache: [String: [(regex: NSRegularExpression, replacement: String)]] = [:]
    private let properNounRules: [(regex: NSRegularExpression, replacement: String)] = {
        let entries: [(String, String)] = [
            ("\\bpython\\b", "Python"),
            ("\\bswift\\b", "Swift"),
            ("\\bjavascript\\b", "JavaScript"),
            ("\\btypescript\\b", "TypeScript"),
            ("\\bkotlin\\b", "Kotlin"),
            ("\\brust\\b", "Rust"),
            ("\\bgolang\\b", "Go"),
        ]
        return entries.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, replacement)
        }
    }()
    private let spaceBeforePunctuationRegex = try? NSRegularExpression(pattern: "\\s+([,;:.!?\\)])")
    private let missingSpaceAfterPunctuationRegex = try? NSRegularExpression(pattern: "([,;:.!?])([^\\s])")
    private let spaceAfterOpenParenRegex = try? NSRegularExpression(pattern: "\\(\\s+")
    private let dashSpacingRegex = try? NSRegularExpression(pattern: "\\s*—\\s*")

    var currentASRDescriptor: ASRBackendDescriptor { asrBackend.descriptor }
    var currentASRBackendKind: ASRBackendKind { asrBackend.descriptor.kind }

    private struct TransitionBoundaryRule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private init() {
        let state = AppState.shared
        state.refreshPerformanceProfile()
        let router = PerformanceRouter.shared
        let preferred = router.effectiveASRBackend(
            preferred: state.preferredASRBackend,
            profile: state.performanceProfile
        )
        self.asrBackend = ASRBackendFactory.make(preferred: preferred)
        state.preferredASRBackend = preferred
        state.activeASRBackend = asrBackend.descriptor.kind
        if !asrBackend.descriptor.requiresModelInstall {
            state.modelStatus = .ready
        }
    }

    func refreshASRBackendSelection() {
        AppState.shared.refreshPerformanceProfile()
        setASRBackend(AppState.shared.preferredASRBackend)
    }

    func setASRBackend(_ preferred: ASRBackendKind) {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        asrBackend.cancelInstall()

        let state = AppState.shared
        state.refreshPerformanceProfile()
        let effectivePreferred = PerformanceRouter.shared.effectiveASRBackend(
            preferred: preferred,
            profile: state.performanceProfile
        )

        asrBackend = ASRBackendFactory.make(preferred: effectivePreferred)
        state.preferredASRBackend = effectivePreferred
        state.activeASRBackend = asrBackend.descriptor.kind
        state.isDownloadPaused = false
        state.downloadStats = DownloadStats()
        state.modelInstallPath = asrBackend.installPath
        if asrBackend.descriptor.requiresModelInstall {
            state.modelStatus = asrBackend.isLoaded ? .ready : .notDownloaded
        } else {
            state.modelStatus = .ready
        }
    }

    // MARK: - Sound Effects

    private func playDictationStartSound() {
        guard AppState.shared.soundEffectsEnabled else { return }
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.volume = 0.5
            sound.play()
        }
    }

    private func playDictationEndSound() {
        guard AppState.shared.soundEffectsEnabled else { return }
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.volume = 0.4
            sound.play()
        }
    }

    // MARK: - Model Loading

    /// Loads the currently-selected ASR backend.
    /// For installable backends, this also drives download progress in AppState.
    func loadModel() async {
        if let inFlight = modelLoadTask {
            if inFlight.isCancelled {
                // Old task was cancelled but may still be running; don't await it.
                modelLoadTask = nil
            } else {
                Self.modelLogger.notice("[ModelLoad] load already in progress; awaiting existing task")
                await inFlight.value
                return
            }
        }

        let task = Task { [self] in
            await performModelLoad()
        }
        modelLoadTask = task
        await task.value
        modelLoadTask = nil
    }

    func cancelModelDownload() {
        let existing = modelLoadTask
        existing?.cancel()
        modelLoadTask = nil
        asrBackend.cancelInstall()
        AppState.shared.isDownloadPaused = false
        if asrBackend.descriptor.requiresModelInstall {
            AppState.shared.modelStatus = .notDownloaded
        } else {
            AppState.shared.modelStatus = .ready
        }
    }

    func pauseModelDownload() {
        guard case .downloading = AppState.shared.modelStatus else { return }
        AppState.shared.isDownloadPaused = true
        asrBackend.pauseInstall()
        AppState.shared.downloadStats.speedBytesPerSec = 0
    }

    func resumeModelDownload() {
        AppState.shared.isDownloadPaused = false
        asrBackend.resumeInstall()
    }

    func uninstallModel() {
        cancelModelDownload()
        asrBackend.uninstallModel()
        AppState.shared.modelInstallPath = asrBackend.installPath
        if asrBackend.descriptor.requiresModelInstall {
            AppState.shared.modelStatus = .notDownloaded
        } else {
            AppState.shared.modelStatus = .ready
        }
    }

    func reinstallModel() async {
        uninstallModel()
        await loadModel()
    }

    private func performModelLoad() async {
        let state = AppState.shared
        state.refreshPerformanceProfile()
        guard !Task.isCancelled else { return }
        let effectivePreferred = PerformanceRouter.shared.effectiveASRBackend(
            preferred: state.preferredASRBackend,
            profile: state.performanceProfile
        )
        if effectivePreferred != currentASRBackendKind {
            setASRBackend(effectivePreferred)
        }

        if state.modelStatus.isReady, asrBackend.isLoaded {
            return
        }

        let backend = asrBackend
        let descriptor = backend.descriptor
        state.activeASRBackend = descriptor.kind

        if !descriptor.requiresModelInstall {
            state.modelStatus = .loading
            await backend.loadIfInstalled()
            state.modelInstallPath = backend.installPath
            state.downloadStats = DownloadStats()
            state.modelStatus = .ready
            Self.modelLogger.notice("[ModelLoad] backend ready without install: \(descriptor.displayName, privacy: .public)")
            return
        }

        let totalBytes = descriptor.approxModelBytes ?? 0
        state.downloadStats = DownloadStats(bytesReceived: 0, totalBytes: totalBytes, speedBytesPerSec: 0, startedAt: Date())
        state.modelStatus = .downloading(progress: max(0.0, min(backend.downloadProgress, 1.0)))
        state.isDownloadPaused = backend.isPaused

        let startedAt = Date()
        var lastProgress: Double = 0
        var lastTime = Date()

        do {
            Self.modelLogger.notice("[ModelLoad] preparing backend \(descriptor.displayName, privacy: .public)")

            await backend.loadIfInstalled()
            if backend.isLoaded {
                state.modelInstallPath = backend.installPath
                state.downloadStats.bytesReceived = totalBytes
                state.modelStatus = .ready
                Self.modelLogger.notice("[ModelLoad] backend already installed and loaded")
                return
            }

            let installTask = Task {
                await backend.installModel()
            }

            while !installTask.isCancelled {
                if Task.isCancelled {
                    installTask.cancel()
                    backend.cancelInstall()
                    throw CancellationError()
                }

                let progress = max(0.0, min(backend.downloadProgress, 1.0))
                if backend.isInstalling {
                    state.modelStatus = .downloading(progress: progress)
                }

                state.downloadStats.totalBytes = totalBytes
                state.downloadStats.bytesReceived = Int64(Double(totalBytes) * progress)

                let now = Date()
                let dt = now.timeIntervalSince(lastTime)
                if dt >= 0.5 && !state.isDownloadPaused {
                    let dp = progress - lastProgress
                    let bytesDelta = Int64(dp * Double(totalBytes))
                    let rawSpeed = max(0, Double(bytesDelta) / dt)
                    let prev = state.downloadStats.speedBytesPerSec
                    state.downloadStats.speedBytesPerSec = prev == 0 ? rawSpeed : (prev * 0.6 + rawSpeed * 0.4)
                    lastProgress = progress
                    lastTime = now
                } else if backend.isPaused {
                    // Reset baseline so speed doesn't spike on resume
                    lastProgress = progress
                    lastTime = now
                }
                state.isDownloadPaused = backend.isPaused

                if !backend.isInstalling {
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }

            await installTask.value
            guard !Task.isCancelled else { throw CancellationError() }

            state.modelStatus = .loading
            if !backend.isLoaded {
                await backend.loadIfInstalled()
            }
            guard backend.isLoaded else {
                let reason = backend.installError ?? L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Le moteur ASR n'a pas pu être chargé.",
                    en: "The ASR backend could not be loaded.",
                    es: "No se pudo cargar el backend ASR.",
                    zh: "无法加载 ASR 后端。",
                    ja: "ASR バックエンドを読み込めませんでした。",
                    ru: "Не удалось загрузить ASR-бэкенд."
                )
                throw NSError(domain: "ASRBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])
            }

            state.modelInstallPath = backend.installPath
            state.downloadStats.bytesReceived = totalBytes
            state.modelStatus = .ready

            let elapsed = Date().timeIntervalSince(startedAt)
            Self.modelLogger.notice("[ModelLoad] backend ready in \(elapsed, privacy: .public)s")
        } catch {
            if Task.isCancelled || error is CancellationError {
                Self.modelLogger.notice("[ModelLoad] cancelled")
                state.modelStatus = descriptor.requiresModelInstall ? .notDownloaded : .ready
            } else {
                Self.modelLogger.error("[ModelLoad] failed: \(error.localizedDescription, privacy: .public)")
                state.modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Dictation Pipeline

    func startDictation() async {
        // ── Guard: no overlapping sessions ───────────────────────────────────
        guard !isDictating else { return }
        // ── Guard: previous transcription still in-flight ────────────────────
        guard !isProcessing else { return }

        let state = AppState.shared

        // ── Guard: microphone ─────────────────────────────────────────────────
        // Only show the system dialog when permission is unknown/denied.
        // If already granted, skip the async call entirely to avoid a suspension
        // window where the key could be released before we even start the engine.
        if state.micPermission != .granted {
            let granted = await state.requestMicrophoneAccess()
            guard granted else {
                state.error = L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Accès au microphone refusé. Autorisez Zphyr dans Réglages Système → Confidentialité → Microphone.",
                    en: "Microphone access denied. Allow Zphyr in System Settings → Privacy & Security → Microphone.",
                    es: "Acceso al micrófono denegado. Autoriza Zphyr en Ajustes del Sistema → Privacidad y seguridad → Micrófono.",
                    zh: "麦克风权限被拒绝。请在 系统设置 → 隐私与安全性 → 麦克风 中允许 Zphyr。",
                    ja: "マイクへのアクセスが拒否されました。システム設定 → プライバシーとセキュリティ → マイク で Zphyr を許可してください。",
                    ru: "Доступ к микрофону запрещен. Разрешите Zphyr в Системных настройках → Конфиденциальность и безопасность → Микрофон."
                )
                return
            }
            // After the async permission check, verify the key is still held.
            // The user may have released it while the dialog was showing.
            guard ShortcutManager.shared.isHolding else { return }
        }

        // ── Guard: ASR backend ready ──────────────────────────────────────────
        guard state.modelStatus.isReady, asrBackend.isLoaded else {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Le moteur de dictée n'est pas encore prêt.",
                en: "The dictation backend is not ready yet.",
                es: "El backend de dictado aún no está listo.",
                zh: "听写后端尚未就绪。",
                ja: "音声入力バックエンドはまだ準備できていません。",
                ru: "Бэкенд диктовки еще не готов."
            )
            return
        }

        isDictating = true

        // Capture the frontmost app BEFORE we start (it may lose focus once we activate)
        targetApp = NSWorkspace.shared.frontmostApplication
        Self.pipelineLogger.notice("[Dictation] start; target app=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public)")

        audioSampleBuffer.reset()
        // Pre-allocate enough for long dictations to avoid repeated reallocations on the realtime audio thread.
        let preallocatedSamples = min(maxDictationSamples, Int(whisperSampleRate * 120))
        audioSampleBuffer.reserveCapacity(preallocatedSamples)
        didHitAudioCaptureLimit = false
        state.dictationState = .listening
        overlayController.show()
        guard startAudioCapture() else {
            // Ensure the session is fully rolled back when audio init fails.
            isDictating = false
            targetApp = nil
            state.dictationState = .idle
            overlayController.hide()
            return
        }
        playDictationStartSound()
    }

    func stopDictation() async {
        guard isDictating else { return }
        isDictating = false
        isProcessing = true

        let state = AppState.shared
        stopAudioCapture()
        // Give CoreAudio a brief moment to flush the last callback before snapshotting.
        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        state.dictationState = .processing
        let capturedSamples = audioSampleBuffer.count()
        Self.pipelineLogger.notice("[Dictation] stop; captured samples=\(capturedSamples)")

        let asrStartedAt = CFAbsoluteTimeGetCurrent()
        let rawText = await runASRTranscription()
        let asrDurationMs = Int((CFAbsoluteTimeGetCurrent() - asrStartedAt) * 1_000)

        let postProcessStartedAt = CFAbsoluteTimeGetCurrent()
        let normalizedText = postProcess(rawText)
        let postProcessDurationMs = Int((CFAbsoluteTimeGetCurrent() - postProcessStartedAt) * 1_000)

        let formatterStartedAt = CFAbsoluteTimeGetCurrent()
        var finalText = await applyFormattingPipeline(rawASRText: rawText, normalizedText: normalizedText)
        let formatterDurationMs = Int((CFAbsoluteTimeGetCurrent() - formatterStartedAt) * 1_000)
        finalText = capitalizeProperNouns(in: finalText)
        Self.pipelineLogger.notice("[Dictation] transcription lengths raw=\(rawText.count) final=\(finalText.count)")
        Self.pipelineLogger.notice(
            "[Dictation] stage timings asr=\(asrDurationMs, privacy: .public)ms post=\(postProcessDurationMs, privacy: .public)ms format=\(formatterDurationMs, privacy: .public)ms"
        )

        state.lastTranscription = finalText
        state.dictationState = .done(text: finalText)

        if !finalText.isEmpty {
            if state.autoInsert {
                await insertIntoTargetApp(finalText)
            } else {
                copyTextToClipboard(finalText)
                Self.pipelineLogger.notice("[Dictation] autoInsert=off; copied transcription to clipboard")
            }
        } else {
            let bufferCount = capturedSamples
            Self.pipelineLogger.notice("[Dictation] no transcription text — bufferCount=\(bufferCount, privacy: .public) rawText.count=\(rawText.count, privacy: .public)")
            if bufferCount < 1600 {
                // Buffer too short: less than 0.1s of audio at 16kHz
                state.error = L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Enregistrement trop court. Maintiens la touche et parle, puis relâche.",
                    en: "Recording too short. Hold the key while speaking, then release.",
                    es: "Grabación demasiado corta. Mantén la tecla mientras hablas.",
                    zh: "录音太短，请按住按键说话再松开。",
                    ja: "録音が短すぎます。キーを押しながら話し、離してください。",
                    ru: "Запись слишком короткая. Удерживайте клавишу пока говорите."
                )
            } else {
                state.error = L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Aucun texte détecté (\(bufferCount/16)ms audio). Parle plus fort ou plus longtemps.",
                    en: "No text detected (\(bufferCount/16)ms audio). Speak louder or longer.",
                    es: "No se detectó texto (\(bufferCount/16)ms audio). Habla más fuerte o más tiempo.",
                    zh: "未检测到文本（\(bufferCount/16)ms 音频）。请说得更大声或更长。",
                    ja: "テキストが検出されませんでした（\(bufferCount/16)ms の音声）。もっと大きく、または長く話してください。",
                    ru: "Текст не распознан (\(bufferCount/16) мс аудио). Говорите громче или дольше."
                )
            }
        }

        targetApp = nil
        playDictationEndSound()
        overlayController.hide()

        try? await Task.sleep(for: .milliseconds(600))
        state.dictationState = .idle
        isProcessing = false
    }

    // MARK: - Text Formatter Pipeline

    private func applyFormattingPipeline(rawASRText: String, normalizedText: String) async -> String {
        guard !normalizedText.isEmpty else { return normalizedText }

        let state = AppState.shared
        state.refreshPerformanceProfile()
        let effectiveMode = PerformanceRouter.shared.effectiveFormattingMode(
            preferred: state.formattingMode,
            profile: state.performanceProfile
        )
        let context = TextFormatterContext(
            rawASRText: rawASRText,
            normalizedText: normalizedText,
            languageCode: state.selectedLanguage.id,
            defaultCodeStyle: state.defaultCodeStyle,
            preferredMode: effectiveMode
        )

        let formatter: any TextFormatter
        if effectiveMode == .advanced && state.isProModeUnlocked {
            state.dictationState = .formatting
            formatter = proTextFormatter
            Self.pipelineLogger.notice("[Formatting] using PRO formatter (mode=\(effectiveMode.rawValue, privacy: .public) proUnlocked=true)")
        } else {
            formatter = ecoTextFormatter
            Self.pipelineLogger.notice("[Formatting] using ECO formatter (mode=\(effectiveMode.rawValue, privacy: .public) proUnlocked=\(state.isProModeUnlocked, privacy: .public))")
        }

        let result = await formatter.format(context)
        if result.usedDeterministicFallback {
            Self.pipelineLogger.notice("[Formatting] result: deterministic fallback (rejectedTokens=\(result.rejectedIntroducedTokens.count, privacy: .public))")
        } else {
            Self.pipelineLogger.notice("[Formatting] result: LLM text accepted")
        }
        if result.usedDeterministicFallback, !result.rejectedIntroducedTokens.isEmpty {
            Self.pipelineLogger.warning(
                "[Dictation] integrity fallback triggered; introduced tokens=\(result.rejectedIntroducedTokens.joined(separator: ","), privacy: .public)"
            )
        }
        return result.text
    }

    // MARK: - Audio Capture

    /// The ASR engine expects 16 kHz mono Float32 PCM.
    private let whisperSampleRate: Double = 16_000
    /// Hard cap to avoid unbounded memory growth if key-up is missed.
    private let maxDictationDurationSeconds: Double = 300
    private var maxDictationSamples: Int {
        Int(whisperSampleRate * maxDictationDurationSeconds)
    }

    @discardableResult
    private func startAudioCapture() -> Bool {
        // Always tear down any previous engine (safety net for race conditions).
        stopAudioCapture()

        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        self.inputNode = inputNode

        // Native hardware format (e.g. 44100 or 48000 Hz, possibly multi-channel)
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16 kHz, mono, Float32 — expected by ASR
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "Impossible de créer le format audio 16kHz.",
                en: "Unable to create 16kHz audio format.",
                es: "No se pudo crear el formato de audio 16kHz.",
                zh: "无法创建 16kHz 音频格式。",
                ja: "16kHz オーディオ形式を作成できませんでした。",
                ru: "Не удалось создать аудиоформат 16 кГц."
            )
            return false
        }

        // Build a converter from hardware format → 16kHz mono
        guard let converter = AVAudioConverter(from: hwFormat, to: whisperFormat) else {
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "Impossible de créer le convertisseur audio.",
                en: "Unable to create audio converter.",
                es: "No se pudo crear el convertidor de audio.",
                zh: "无法创建音频转换器。",
                ja: "オーディオコンバータを作成できませんでした。",
                ru: "Не удалось создать аудиоконвертер."
            )
            return false
        }

        // Tap on the hardware format, convert each buffer to 16kHz
        var lastHUDLevelPushAt = CFAbsoluteTimeGetCurrent()
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] hwBuffer, _ in
            guard let self else { return }
            autoreleasepool {
                // Compute how many output frames correspond to this input buffer
                let inputFrames = AVAudioFrameCount(hwBuffer.frameLength)
                let ratio = self.whisperSampleRate / hwFormat.sampleRate
                let outputFrames = AVAudioFrameCount(Double(inputFrames) * ratio + 1)

                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outputFrames) else { return }

                var conversionError: NSError?
                var consumed = false
                let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return hwBuffer
                }

                guard status != .error, let channelData = outBuffer.floatChannelData?[0] else { return }
                let frameCount = Int(outBuffer.frameLength)
                guard frameCount > 0 else { return }
                let samplePointer = UnsafeBufferPointer(start: channelData, count: frameCount)
                let appendStatus = self.audioSampleBuffer.append(samplePointer, maxSamples: self.maxDictationSamples)
                if appendStatus != .appended && !self.didHitAudioCaptureLimit {
                    self.didHitAudioCaptureLimit = true
                    if appendStatus == .truncated {
                        Self.pipelineLogger.warning("[Dictation] audio capture reached max duration (\(Int(self.maxDictationDurationSeconds), privacy: .public)s); truncating additional samples")
                    } else {
                        Self.pipelineLogger.warning("[Dictation] audio capture reached max duration (\(Int(self.maxDictationDurationSeconds), privacy: .public)s); dropping additional samples")
                    }
                }

                // RMS spectrum for HUD (computed on the original hwBuffer for responsiveness)
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastHUDLevelPushAt >= 0.10 else { return }
                lastHUDLevelPushAt = now

                guard let hwChannel = hwBuffer.floatChannelData?[0] else { return }
                let hwFrames = Int(hwBuffer.frameLength)
                guard hwFrames > 0 else { return }
                let bandSize = max(1, hwFrames / 28)
                var levels: [Float] = []
                levels.reserveCapacity(28)
                for i in 0..<28 {
                    let start = i * bandSize
                    let end = min(start + bandSize, hwFrames)
                    guard start < end else {
                        levels.append(0.1)
                        continue
                    }
                    let slice = UnsafeBufferPointer(start: hwChannel + start, count: end - start)
                    var peak: Float = 0
                    for sample in slice {
                        peak = max(peak, abs(sample))
                    }
                    levels.append(min(1.0, sqrt(min(1.0, peak * 18))))
                }
                Task { @MainActor in
                    AppState.shared.updateAudioLevels(levels)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            AppState.shared.error = "Démarrage audio échoué : \(error.localizedDescription)"
            stopAudioCapture()
            return false
        }
        return true
    }

    private func stopAudioCapture() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }

    // MARK: - Transcription

    private func runASRTranscription() async -> String {
        let audioSnapshot = audioSampleBuffer.snapshot()
        let languages = AppState.shared.selectedLanguages
        let lang: String? = languages.count > 1 ? nil : (languages.first?.id ?? "fr")
        return await transcribeAudioSamples(audioSnapshot, language: lang)
    }

    func transcribeAudioFile(at url: URL, language: WhisperLanguage) async -> String {
        let state = AppState.shared
        guard state.modelStatus.isReady, asrBackend.isLoaded else {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Le moteur de dictée n'est pas encore prêt.",
                en: "The dictation backend is not ready yet.",
                es: "El backend de dictado aún no está listo.",
                zh: "听写后端尚未就绪。",
                ja: "音声入力バックエンドはまだ準備できていません。",
                ru: "Бэкенд диктовки еще не готов."
            )
            return ""
        }

        let samples: [Float]
        do {
            let sampleRate = whisperSampleRate
            samples = try await Task.detached(priority: .userInitiated) {
                try Self.loadAudioSamples(from: url, targetSampleRate: sampleRate)
            }.value
        } catch {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Impossible de lire ce fichier audio : \(error.localizedDescription)",
                en: "Unable to read this audio file: \(error.localizedDescription)",
                es: "No se pudo leer este archivo de audio: \(error.localizedDescription)",
                zh: "无法读取该音频文件：\(error.localizedDescription)",
                ja: "この音声ファイルを読み込めませんでした: \(error.localizedDescription)",
                ru: "Не удалось прочитать аудиофайл: \(error.localizedDescription)"
            )
            return ""
        }

        let rawText = await transcribeAudioSamples(samples, language: language.id)
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        state.lastTranscription = trimmed
        if trimmed.isEmpty {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Aucun texte détecté dans ce fichier audio.",
                en: "No text detected in this audio file.",
                es: "No se detectó texto en este archivo de audio.",
                zh: "在该音频文件中未检测到文本。",
                ja: "この音声ファイルからテキストが検出されませんでした。",
                ru: "В этом аудиофайле текст не распознан."
            )
        }
        return trimmed
    }

    private func transcribeAudioSamples(
        _ audioSnapshot: [Float],
        language lang: String?
    ) async -> String {
        let vad = VoiceActivityDetector(sampleRate: whisperSampleRate)
        let processedAudio: [Float]
        do {
            let result = try vad.trim(audioSnapshot)
            processedAudio = result.trimmedBuffer
            let leadingMs = Int(Double(result.leadingTrimmedSamples) / 16.0)
            let trailingMs = Int(Double(result.trailingTrimmedSamples) / 16.0)
            if leadingMs > 0 || trailingMs > 0 {
                Self.pipelineLogger.notice(
                    "[Dictation] VAD trim applied; lead=\(leadingMs, privacy: .public)ms tail=\(trailingMs, privacy: .public)ms threshold=\(Double(result.threshold), privacy: .public)"
                )
            }
        } catch {
            await MainActor.run {
                AppState.shared.error = L10n.ui(
                    for: AppState.shared.selectedLanguage.id,
                    fr: "Aucune voix détectée dans l'audio. Réessaie en parlant plus près du micro.",
                    en: "No voice detected in the audio. Try speaking closer to the microphone.",
                    es: "No se detectó voz en el audio. Intenta hablar más cerca del micrófono.",
                    zh: "音频中未检测到语音。请靠近麦克风重试。",
                    ja: "音声が検出されませんでした。マイクに近づいて再試行してください。",
                    ru: "В аудио не обнаружен голос. Попробуйте говорить ближе к микрофону."
                )
            }
            Self.pipelineLogger.error("[Dictation] VAD rejected audio: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        let durationMs = Int(Double(processedAudio.count) / 16.0)
        let primaryBackendName = asrBackend.descriptor.displayName
        let primaryLoaded = asrBackend.isLoaded
        Self.pipelineLogger.notice("[Dictation] transcribeAudioSamples: samples=\(processedAudio.count, privacy: .public) (~\(durationMs, privacy: .public)ms) lang=\(lang ?? "auto", privacy: .public) backend=\(primaryBackendName, privacy: .public) loaded=\(primaryLoaded, privacy: .public)")

        guard !processedAudio.isEmpty else {
            Self.pipelineLogger.error("[Dictation] audioSnapshot is EMPTY — no audio was captured")
            return ""
        }

        let candidates = transcriptionCandidatesForCurrentRequest()
        let orderedNames = candidates.map { $0.descriptor.displayName }.joined(separator: " -> ")
        Self.pipelineLogger.notice("[Dictation] decoding candidates=\(orderedNames, privacy: .public)")

        var lastFailure: Error?
        for (index, backend) in candidates.enumerated() {
            let descriptor = backend.descriptor

            if descriptor.requiresModelInstall && !backend.isLoaded {
                Self.pipelineLogger.error("[Dictation] decoding skipped attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) reason=backend not loaded")
                continue
            }

            let timeout = descriptor.kind == .qwenMLX ? qwenTranscriptionTimeoutSeconds : 15.0
            Self.pipelineLogger.notice("[Dictation] decoding attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) timeout=\(timeout, privacy: .public)s")

            do {
                let raw = try await transcribeWithTimeout(
                    backend: backend,
                    audio: processedAudio,
                    timeoutSeconds: timeout
                )
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw ASRBackendError.emptyResult }

                if let qualityIssue = Self.transcriptionQualityIssue(result, durationMs: durationMs) {
                    throw TranscriptionAttemptError.lowQuality(qualityIssue)
                }

                if descriptor.kind != self.asrBackend.descriptor.kind {
                    let primaryName = self.asrBackend.descriptor.displayName
                    Self.pipelineLogger.notice("[Dictation] fallback backend succeeded primary=\(primaryName, privacy: .public) used=\(descriptor.displayName, privacy: .public)")
                }
                Self.pipelineLogger.notice("[Dictation] backend result chars=\(result.count, privacy: .public)")
                return result
            } catch {
                lastFailure = error
                Self.pipelineLogger.error("[Dictation] decoding failed attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        await MainActor.run {
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "La transcription a échoué. Réessayez après rechargement du moteur.",
                en: "Transcription failed. Retry after reloading the backend.",
                es: "La transcripción falló. Vuelve a intentarlo tras recargar el backend.",
                zh: "转写失败。请重新加载后端后重试。",
                ja: "文字起こしに失敗しました。バックエンド再読み込み後に再試行してください。",
                ru: "Сбой транскрибации. Повторите после перезагрузки бэкенда."
            )
        }
        if let lastFailure {
            Self.pipelineLogger.error("[Dictation] all backend attempts failed; last error=\(lastFailure.localizedDescription, privacy: .public)")
        } else {
            Self.pipelineLogger.error("[Dictation] all backend attempts failed; no backend available")
        }
        return ""
    }

    private enum TranscriptionAttemptError: LocalizedError {
        case timedOut(seconds: Double)
        case lowQuality(String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds):
                return "Transcription timed out after \(Int(seconds.rounded()))s."
            case .lowQuality(let reason):
                return "Transcription rejected due to low-quality output (\(reason))."
            }
        }
    }

    private func transcriptionCandidatesForCurrentRequest() -> [any ASRService] {
        guard asrBackend.descriptor.kind == .qwenMLX, AppleSpeechAnalyzerBackend.isRuntimeSupported else {
            return [asrBackend]
        }

        // Qwen fallback strategy: prioritize Apple Speech when available,
        // then keep Qwen as backup.
        return [AppleSpeechAnalyzerBackend(), asrBackend]
    }

    private func transcribeWithTimeout(
        backend: any ASRService,
        audio: [Float],
        timeoutSeconds: Double
    ) async throws -> String {
        let timeoutNanos = UInt64(max(1.0, timeoutSeconds) * 1_000_000_000)
        return try await withThrowingTaskGroup(of: String.self, returning: String.self) { group in
            group.addTask {
                try await backend.transcribe(audioBuffer: audio)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw TranscriptionAttemptError.timedOut(seconds: timeoutSeconds)
            }
            guard let firstCompleted = try await group.next() else {
                throw ASRBackendError.transcriptionFailed("No transcription result produced.")
            }
            group.cancelAll()
            return firstCompleted
        }
    }

    private nonisolated static func transcriptionQualityIssue(_ text: String, durationMs: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty_result" }

        let durationSeconds = max(Double(durationMs) / 1_000.0, 0.25)
        let charsPerSecond = Double(trimmed.count) / durationSeconds
        if charsPerSecond > 45.0 {
            return "chars_per_second=\(Int(charsPerSecond.rounded()))"
        }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        let wordsPerSecond = Double(words.count) / durationSeconds
        if wordsPerSecond > 8.0 {
            return "words_per_second=\(Int(wordsPerSecond.rounded()))"
        }

        let longTokenCount = words.filter { $0.count >= 48 }.count
        if longTokenCount >= 2 {
            return "too_many_long_tokens=\(longTokenCount)"
        }

        var frequencies: [Substring: Int] = [:]
        for token in words where token.count >= 4 {
            frequencies[token, default: 0] += 1
        }
        if let repeated = frequencies.first(where: { $0.value >= 8 }) {
            return "repeated_token=\(repeated.key)"
        }

        let lower = trimmed.lowercased()
        let suspiciousMarkers = ["<footer", "<header", "{%", "_increment", "_magic", "extends"]
        let markerHits = suspiciousMarkers.reduce(0) { partial, marker in
            partial + (lower.contains(marker) ? 1 : 0)
        }
        if markerHits >= 2 {
            return "suspicious_markup_markers=\(markerHits)"
        }

        return nil
    }

    private nonisolated static func loadAudioSamples(from url: URL, targetSampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        guard file.length > 0 else {
            throw AudioFileLoadError.emptyAudio
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileLoadError.invalidBuffer
        }

        let inputFrameCount = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            throw AudioFileLoadError.invalidBuffer
        }
        try file.read(into: inputBuffer)

        if inputFormat.sampleRate == targetSampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32,
           let channelData = inputBuffer.floatChannelData?[0] {
            let frameCount = Int(inputBuffer.frameLength)
            guard frameCount > 0 else {
                throw AudioFileLoadError.emptyAudio
            }
            return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioFileLoadError.conversionFailed("converter unavailable")
        }

        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1024)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw AudioFileLoadError.invalidBuffer
        }

        var conversionError: NSError?
        var didConsumeInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didConsumeInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didConsumeInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error else {
            throw AudioFileLoadError.conversionFailed(conversionError?.localizedDescription ?? "conversion error")
        }
        guard let outputData = outputBuffer.floatChannelData?[0] else {
            throw AudioFileLoadError.invalidBuffer
        }
        let outputFrameCount = Int(outputBuffer.frameLength)
        guard outputFrameCount > 0 else {
            throw AudioFileLoadError.emptyAudio
        }
        return Array(UnsafeBufferPointer(start: outputData, count: outputFrameCount))
    }

    // MARK: - Post-processing

    /// Returns the WritingTone for the app that was frontmost when recording started.
    private func activeTone() -> WritingTone {
        let state = AppState.shared
        guard let bundleID = activeBundleIdentifier() else {
            return state.styleOther
        }
        // Mail clients → email tone
        if bundleID.contains("mail") || bundleID.contains("Mail") ||
           bundleID.contains("mimestream") || bundleID.contains("Airmail") ||
           bundleID.contains("Spark") {
            return state.styleEmail
        }
        // Messaging apps → personal tone
        if bundleID.contains("Messages") || bundleID.contains("WhatsApp") ||
           bundleID.contains("Telegram") || bundleID.contains("Signal") ||
           bundleID.contains("Discord") {
            return state.stylePersonal
        }
        // Work / productivity apps → work tone
        if bundleID.contains("Slack") || bundleID.contains("Teams") ||
           bundleID.contains("notion") || bundleID.contains("Linear") ||
           bundleID.contains("Jira") || bundleID.contains("Confluence") ||
           bundleID.contains("zoom") || bundleID.contains("Zoom") {
            return state.styleWork
        }
        return state.styleOther
    }

    private func activeBundleIdentifier() -> String? {
        (targetApp ?? NSWorkspace.shared.frontmostApplication)?.bundleIdentifier
    }

    private let smartFormatter = SmartTextFormatter()

    /// Full post-processing pipeline:
    ///   filler removal → repetition cleanup → list/todo detection → tone formatting → dictionary/snippets
    private func postProcess(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let languageCode = AppState.shared.selectedLanguage.id

        var result = text

        // ── 1. Filler word removal ────────────────────────────────────────────
        for regex in fillerRemovalRegexes(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // ── 2. Smart formatting (repetitions, list, todos) ────────────────────
        let sf = smartFormatter.run(result, languageCode: languageCode)
        result = sf.text
        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // ── 3. Dictionary mappings & snippet macros ───────────────────────────
        result = applyDictionaryPronunciationMappings(to: result)
        result = applyContextualLinkSnippets(to: result, bundleID: activeBundleIdentifier())

        // ── 4. If a list was detected, minimal formatting then done ───────────
        if sf.isList {
            var finalList = result
            if !sf.todos.isEmpty {
                finalList = SmartTextFormatter.todoBlock(from: sf.todos) + "\n\n" + finalList
            }
            return normalizeWhitespacePreservingParagraphs(in: finalList)
        }

        // ── 5. Tone-based formatting ──────────────────────────────────────────
        let tone = activeTone()

        switch tone {
        case .formal:
            result = applyFormalPunctuation(to: result, languageCode: languageCode)
            result = insertTransitionSentenceBoundaries(in: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .casual:
            // Inject sentence boundaries before known transition words, then capitalize
            result = applyLightPunctuation(to: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)

        case .veryCasual:
            result = result.lowercased()
            if result.hasSuffix(".") { result = String(result.dropLast()) }
            result = result.replacingOccurrences(of: "[!;:]", with: "", options: .regularExpression)
        }

        // ── 6. Prepend TODO checklist if any tasks were extracted ─────────────
        if !sf.todos.isEmpty {
            let block = SmartTextFormatter.todoBlock(from: sf.todos)
            result = result.isEmpty ? block : block + "\n\n" + result
        }

        result = normalizeWhitespacePreservingParagraphs(in: result)
        return result
    }

    /// Shared helper: inserts ". Transition" before known sentence-starting transition words
    /// so that `capitalizeSentences` can capitalize mid-text sentences naturally.
    /// Called by both casual (`applyLightPunctuation`) and formal tone paths.
    private func insertTransitionSentenceBoundaries(in text: String, languageCode: String) -> String {
        var result = text
        for rule in transitionBoundaryRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )
        }
        return result
    }

    /// Casual-tone punctuation: inserts sentence boundaries then adds final period.
    private func applyLightPunctuation(to text: String, languageCode: String) -> String {
        var result = insertTransitionSentenceBoundaries(in: text, languageCode: languageCode)

        // Capitalise first letter
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }

        // Add closing period to substantial texts (≥ 5 words) that lack one
        let wordCount = result.split(separator: " ").count
        if wordCount >= 5, let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }

    /// Capitalises programming language names that appear as plain words in the output.
    private func capitalizeProperNouns(in text: String) -> String {
        var result = text
        for rule in properNounRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )
        }
        return result
    }

    /// Applies punctuation-oriented formatting for formal tone.
    /// Converts common dictated punctuation keywords into symbols and normalizes spacing.
    private func applyFormalPunctuation(to text: String, languageCode: String) -> String {
        var result = text

        for item in formalPunctuationRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = item.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: item.replacement
            )
        }

        // Remove spaces before punctuation.
        if let spaceBeforePunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceBeforePunctuationRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1"
            )
        }
        // Ensure one space after punctuation when followed by text.
        if let missingSpaceAfterPunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = missingSpaceAfterPunctuationRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1 $2"
            )
        }
        // Normalize spaces around opening parenthesis and em dash.
        if let spaceAfterOpenParenRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceAfterOpenParenRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "("
            )
        }
        if let dashSpacingRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = dashSpacingRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " — "
            )
        }

        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If the user did not dictate final punctuation, close sentence with a period.
        if let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }

    private func formalPunctuationRules(for languageCode: String) -> [(regex: NSRegularExpression, replacement: String)] {
        if let cached = formalPunctuationRuleCache[languageCode] {
            return cached
        }

        let replacements = formalPunctuationReplacements(for: languageCode) + [
            // French keywords
            ("\\bpoint\\s+virgule\\b", ";"),
            ("\\bdeux\\s+points\\b", ":"),
            ("\\bpoint\\s+d['’]interrogation\\b", "?"),
            ("\\bpoint\\s+d['’]exclamation\\b", "!"),
            ("\\bpoint\\b", "."),
            ("\\bvirgule\\b", ","),
            ("\\btiret\\b", "—"),
            ("\\bouvrir\\s+parenth[èe]se\\b", "("),
            ("\\bfermer\\s+parenth[èe]se\\b", ")"),

            // English keywords
            ("\\bsemicolon\\b", ";"),
            ("\\bcolon\\b", ":"),
            ("\\bquestion\\s+mark\\b", "?"),
            ("\\bexclamation\\s+mark\\b", "!"),
            ("\\bperiod\\b", "."),
            ("\\bfull\\s+stop\\b", "."),
            ("\\bcomma\\b", ","),
            ("\\bdash\\b", "—"),
            ("\\bopen\\s+parenthesis\\b", "("),
            ("\\bclose\\s+parenthesis\\b", ")")
        ]

        let compiled = replacements.compactMap { pattern, replacement -> (regex: NSRegularExpression, replacement: String)? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, replacement)
        }
        formalPunctuationRuleCache[languageCode] = compiled
        return compiled
    }

    private func fillerRemovalRegexes(for languageCode: String) -> [NSRegularExpression] {
        if let cached = fillerRegexCache[languageCode] {
            return cached
        }
        let compiled = fillerWords(for: languageCode).compactMap { filler -> NSRegularExpression? in
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            return try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive])
        }
        fillerRegexCache[languageCode] = compiled
        return compiled
    }

    private func transitionBoundaryRules(for languageCode: String) -> [TransitionBoundaryRule] {
        if let cached = transitionRuleCache[languageCode] {
            return cached
        }

        let rules = transitionStarters(for: languageCode).compactMap { starter -> TransitionBoundaryRule? in
            let escaped = NSRegularExpression.escapedPattern(for: starter)
            // Match: word (possibly with comma) + spaces + starter keyword
            // Only when the preceding token is NOT already followed by sentence-terminal punctuation
            let pattern = "(?i)([A-Za-zÀ-ÿ0-9_]{2,})([,]?\\s+)(\(escaped))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let replacement = "$1. \(starter.prefix(1).uppercased())\(starter.dropFirst())"
            return TransitionBoundaryRule(regex: regex, replacement: replacement)
        }

        transitionRuleCache[languageCode] = rules
        return rules
    }

    private func transitionStarters(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["ensuite", "puis", "cependant", "néanmoins", "toutefois",
                    "par conséquent", "donc", "ainsi", "de plus", "par ailleurs",
                    "en revanche", "en fait", "d'ailleurs"]
        case "es":
            return ["luego", "después", "sin embargo", "no obstante",
                    "por lo tanto", "así que", "además"]
        case "de":
            return ["dann", "jedoch", "außerdem", "deshalb", "danach"]
        default:
            return ["then", "however", "therefore", "moreover", "furthermore",
                    "subsequently", "additionally", "besides", "nonetheless"]
        }
    }

    private func fillerWords(for languageCode: String) -> [String] {
        let common = ["hmm", "hm", "mhm"]
        let fr = [
            "euh", "euh,", "euh.", "bah", "bah,", "ben", "ben,",
            "voilà,", "voilà.", "voilà", "donc,", "alors,", "enfin,",
            "genre,", "genre", "hein,", "hein", "quoi,",
        ]
        let en = ["uh", "um", "uh,", "um,", "like,", "you know,", "you know", "right,", "so,"]
        let es = ["eh", "eh,", "eh.", "emm", "este", "pues", "o sea", "bueno,"]
        let zh = ["嗯", "呃", "那个", "就是", "然后"]
        let ja = ["えー", "えっと", "あの", "その", "まあ"]
        let ru = ["ээ", "эм", "ну", "как бы", "это"]

        switch SupportedUILanguage.fromWhisperCode(languageCode) {
        case .fr: return fr + common
        case .en: return en + common
        case .es: return es + common
        case .zh: return zh + common
        case .ja: return ja + common
        case .ru: return ru + common
        }
    }

    private func formalPunctuationReplacements(for languageCode: String) -> [(pattern: String, replacement: String)] {
        switch SupportedUILanguage.fromWhisperCode(languageCode) {
        case .es:
            return [
                ("\\bpunto\\s+y\\s+coma\\b", ";"),
                ("\\bdos\\s+puntos\\b", ":"),
                ("\\bsigno\\s+de\\s+interrogación\\b", "?"),
                ("\\bsigno\\s+de\\s+exclamación\\b", "!"),
                ("\\bpunto\\b", "."),
                ("\\bcoma\\b", ","),
                ("\\bguion\\b", "—")
            ]
        case .zh:
            return [
                ("分号", ";"),
                ("冒号", ":"),
                ("问号", "?"),
                ("感叹号", "!"),
                ("句号", "."),
                ("逗号", ",")
            ]
        case .ja:
            return [
                ("句点", "."),
                ("読点", ","),
                ("コロン", ":"),
                ("セミコロン", ";"),
                ("疑問符", "?"),
                ("感嘆符", "!")
            ]
        case .ru:
            return [
                ("\\bточка\\s+с\\s+запятой\\b", ";"),
                ("\\bдвоеточие\\b", ":"),
                ("\\bвопросительный\\s+знак\\b", "?"),
                ("\\bвосклицательный\\s+знак\\b", "!"),
                ("\\bточка\\b", "."),
                ("\\bзапятая\\b", ","),
                ("\\bтире\\b", "—")
            ]
        case .fr, .en:
            return []
        }
    }

    /// Capitalizes the first character of each sentence.
    private func capitalizeSentences(in text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var shouldCapitalize = true

        for ch in text {
            if shouldCapitalize, ch.isLetter {
                result.append(contentsOf: String(ch).uppercased())
                shouldCapitalize = false
            } else {
                result.append(ch)
            }

            if ".!?".contains(ch) {
                shouldCapitalize = true
            }
        }

        return result
    }

    /// Automatic paragraph formatting for formal mode.
    /// Multilingual sentence segmentation uses Foundation sentence boundaries.
    private func applyAutomaticFormalParagraphFormatting(to text: String, languageCode: String) -> String {
        let cleaned = normalizeWhitespacePreservingParagraphs(in: text)
        guard !cleaned.isEmpty else { return cleaned }

        let sentences = sentenceChunks(from: cleaned)
        guard !sentences.isEmpty else { return cleaned }

        let maxSentencesPerParagraph = 3
        let maxWordsPerParagraph = 70
        let maxCharsPerParagraph = 360
        let markers = paragraphBreakMarkers(for: languageCode)

        var paragraphs: [String] = []
        var current: [String] = []
        var currentWords = 0
        var currentChars = 0

        for sentence in sentences {
            let sentenceWords = sentence.split(whereSeparator: \.isWhitespace).count
            let sentenceChars = sentence.count
            let startsMarker = startsWithParagraphBreakMarker(sentence, markers: markers)

            let shouldBreakBefore = !current.isEmpty && (
                startsMarker ||
                current.count >= maxSentencesPerParagraph ||
                currentWords + sentenceWords > maxWordsPerParagraph ||
                currentChars + sentenceChars > maxCharsPerParagraph
            )

            if shouldBreakBefore {
                paragraphs.append(current.joined(separator: " "))
                current = []
                currentWords = 0
                currentChars = 0
            }

            current.append(sentence)
            currentWords += sentenceWords
            currentChars += sentenceChars
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func sentenceChunks(from text: String) -> [String] {
        var chunks: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            guard let raw = substring else { return }
            let sentence = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                chunks.append(sentence)
            }
        }
        if !chunks.isEmpty {
            return chunks
        }

        let fallback = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func paragraphBreakMarkers(for languageCode: String) -> [String] {
        switch languageCode.lowercased() {
        case "fr":
            return ["de plus", "en outre", "par ailleurs", "cependant", "toutefois", "enfin", "en conclusion", "cordialement", "bien à vous"]
        case "en":
            return ["moreover", "furthermore", "however", "therefore", "meanwhile", "in conclusion", "best regards", "kind regards", "sincerely"]
        case "es":
            return ["además", "sin embargo", "por lo tanto", "mientras tanto", "en conclusión", "saludos"]
        case "zh":
            return ["此外", "另外", "然而", "因此", "总之", "最后", "此致", "敬礼"]
        case "ja":
            return ["さらに", "一方で", "しかし", "そのため", "結論として", "最後に", "よろしくお願いいたします"]
        case "ru":
            return ["кроме того", "однако", "поэтому", "между тем", "в заключение", "с уважением"]
        case "de":
            return ["außerdem", "jedoch", "deshalb", "inzwischen", "abschließend", "mit freundlichen grüßen"]
        case "it":
            return ["inoltre", "tuttavia", "pertanto", "nel frattempo", "in conclusione", "cordiali saluti"]
        case "pt":
            return ["além disso", "no entanto", "portanto", "enquanto isso", "em conclusão", "atenciosamente"]
        default:
            return ["however", "therefore", "in conclusion", "best regards", "sincerely"]
        }
    }

    private func startsWithParagraphBreakMarker(_ sentence: String, markers: [String]) -> Bool {
        let normalized = sentence
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’([{"))
        return markers.contains { normalized.hasPrefix($0) }
    }

    private func normalizeWhitespacePreservingParagraphs(in text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        normalized = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrites known spoken aliases to their canonical dictionary forms.
    private func applyDictionaryPronunciationMappings(to text: String) -> String {
        var result = text

        let mappings = DictionaryStore.shared.entries
            .compactMap { entry -> (spoken: String, written: String)? in
                let spoken = entry.spokenAs.trimmingCharacters(in: .whitespacesAndNewlines)
                let written = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty, !written.isEmpty else { return nil }
                return (spoken: spoken, written: written)
            }
            .sorted { $0.spoken.count > $1.spoken.count }

        for mapping in mappings {
            let escaped = NSRegularExpression.escapedPattern(for: mapping.spoken)
            let pattern = "\\b\(escaped)\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: mapping.written,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    // MARK: - Contextual Snippets

    private enum SnippetContext {
        case email
        case social
        case general
    }

    private struct ContextualSnippetRule {
        let pattern: String
        let replacement: String
    }

    /// Replaces spoken social/contact intents with links, adapting output to context.
    /// Links are configurable via UserDefaults:
    /// - AppState.snippetLinkedInURLKey
    /// - AppState.snippetSocialURLKey
    /// - AppState.snippetContactEmailKey
    private func applyContextualLinkSnippets(to text: String, bundleID: String?) -> String {
        var result = text
        let languageCode = AppState.shared.selectedLanguage.id
        let context = snippetContext(for: bundleID)
        let links = snippetLinks()
        let flags = snippetFeatureFlags()
        let triggers = snippetTriggerPhrases(languageCode: languageCode)

        let linkedInReplacement: String
        let socialReplacement: String
        let mailReplacement: String

        switch context {
        case .email:
            if flags.verboseInEmail {
                linkedInReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur LinkedIn : \(links.linkedinURL)",
                    en: "Find us on LinkedIn: \(links.linkedinURL)",
                    es: "Encuéntranos en LinkedIn: \(links.linkedinURL)",
                    zh: "在 LinkedIn 上找到我们：\(links.linkedinURL)",
                    ja: "LinkedInはこちら: \(links.linkedinURL)",
                    ru: "Найдите нас в LinkedIn: \(links.linkedinURL)"
                )
                socialReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur nos réseaux sociaux : \(links.socialURL)",
                    en: "Find us on social media: \(links.socialURL)",
                    es: "Encuéntranos en redes sociales: \(links.socialURL)",
                    zh: "在社交媒体找到我们：\(links.socialURL)",
                    ja: "SNSはこちら: \(links.socialURL)",
                    ru: "Найдите нас в соцсетях: \(links.socialURL)"
                )
                mailReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Contactez-nous : \(links.mailtoLink)",
                    en: "Contact us: \(links.mailtoLink)",
                    es: "Contáctanos: \(links.mailtoLink)",
                    zh: "联系我们：\(links.mailtoLink)",
                    ja: "お問い合わせ: \(links.mailtoLink)",
                    ru: "Свяжитесь с нами: \(links.mailtoLink)"
                )
            } else {
                linkedInReplacement = links.linkedinURL
                socialReplacement = links.socialURL
                mailReplacement = links.mailtoLink
            }
        case .social, .general:
            linkedInReplacement = links.linkedinURL
            socialReplacement = links.socialURL
            mailReplacement = links.mailtoLink
        }

        var rules: [ContextualSnippetRule] = []
        if flags.linkedInEnabled {
            rules.append(contentsOf: triggers.linkedIn.map {
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: linkedInReplacement
                )
            })
        }
        if flags.socialEnabled {
            rules.append(contentsOf: triggers.social.map {
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: socialReplacement
                )
            })
        }
        if flags.gmailEnabled {
            rules.append(contentsOf: triggers.gmail.map {
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: mailReplacement
                )
            })
        }

        for rule in rules {
            let replacement = "$1\(escapedRegexReplacement(rule.replacement))"
            result = result.replacingOccurrences(
                of: rule.pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return result
    }

    private func snippetContext(for bundleID: String?) -> SnippetContext {
        guard let bundleID else { return .general }
        let lower = bundleID.lowercased()

        // Email compose contexts
        if lower.contains("mail") ||
            lower.contains("outlook") ||
            lower.contains("mimestream") ||
            lower.contains("spark") ||
            lower.contains("airmail") {
            return .email
        }

        // Social media contexts
        if lower.contains("linkedin") ||
            lower.contains("twitter") ||
            lower.contains("facebook") ||
            lower.contains("instagram") ||
            lower.contains("threads") {
            return .social
        }

        return .general
    }

    private func snippetLinks() -> (linkedinURL: String, socialURL: String, mailtoLink: String) {
        let defaults = UserDefaults.standard

        let linkedin = cleanedSnippetValue(defaults.string(forKey: AppState.snippetLinkedInURLKey))
            ?? AppState.snippetLinkedInDefaultURL

        let social = cleanedSnippetValue(defaults.string(forKey: AppState.snippetSocialURLKey))
            ?? AppState.snippetSocialDefaultURL

        let email = cleanedSnippetValue(defaults.string(forKey: AppState.snippetContactEmailKey))
            ?? AppState.snippetContactDefaultEmail

        let mailto = email.lowercased().hasPrefix("mailto:") ? email : "mailto:\(email)"
        return (linkedinURL: linkedin, socialURL: social, mailtoLink: mailto)
    }

    private func snippetTriggerPhrases(languageCode: String) -> (linkedIn: [String], social: [String], gmail: [String]) {
        let defaults = UserDefaults.standard

        let linkedIn = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetLinkedInTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .linkedIn, languageCode: languageCode)
        )
        let social = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetSocialTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .social, languageCode: languageCode)
        )
        let gmail = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetGmailTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .gmail, languageCode: languageCode)
        )

        return (linkedIn, social, gmail)
    }

    private func parsedTriggerPhrases(_ rawText: String?, fallbackText: String) -> [String] {
        let source = cleanedSnippetValue(rawText).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackText
        let parts = source.components(separatedBy: CharacterSet(charactersIn: "\n,;"))

        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            let normalized = part
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private func snippetPattern(for phrase: String) -> String {
        var escaped = NSRegularExpression.escapedPattern(for: phrase)
        escaped = escaped.replacingOccurrences(of: "\\ ", with: "\\s+")
        escaped = escaped.replacingOccurrences(of: "\\-", with: "[-\\s]?")
        return "(?i)(^|[^\\p{L}\\p{N}_])\(escaped)(?=$|[^\\p{L}\\p{N}_])"
    }

    private func escapedRegexReplacement(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    private func snippetFeatureFlags() -> (
        linkedInEnabled: Bool,
        socialEnabled: Bool,
        gmailEnabled: Bool,
        verboseInEmail: Bool
    ) {
        let defaults = UserDefaults.standard
        let linkedInEnabled = defaults.object(forKey: AppState.snippetLinkedInEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetLinkedInEnabledKey)
        let socialEnabled = defaults.object(forKey: AppState.snippetSocialEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetSocialEnabledKey)
        let gmailEnabled = defaults.object(forKey: AppState.snippetGmailEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetGmailEnabledKey)
        let verboseInEmail = defaults.object(forKey: AppState.snippetVerboseInEmailKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetVerboseInEmailKey)
        return (linkedInEnabled, socialEnabled, gmailEnabled, verboseInEmail)
    }

    private func cleanedSnippetValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Text Injection

    /// Activates the target app, waits for it to become frontmost, then inserts text via synthesized key events.
    private func insertIntoTargetApp(_ text: String) async {
        guard AXIsProcessTrusted() else {
            copyTextToClipboard(text)
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "Accès Accessibilité manquant. Le texte a été copié dans le presse-papiers.",
                en: "Accessibility access is missing. Text was copied to the clipboard.",
                es: "Falta acceso de Accesibilidad. El texto se copió al portapapeles.",
                zh: "缺少辅助功能权限。文本已复制到剪贴板。",
                ja: "アクセシビリティ権限がありません。テキストをクリップボードにコピーしました。",
                ru: "Нет доступа к Спецвозможностям. Текст скопирован в буфер обмена."
            )
            Self.pipelineLogger.error("[Insert] accessibility not trusted; used clipboard fallback")
            return
        }

        Self.pipelineLogger.notice("[Insert] preparing secure text injection; textLength=\(text.count) target=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public)")

        if let app = targetApp, !app.isTerminated {
            let activated = app.activate()
            Self.pipelineLogger.notice("[Insert] activate target app result=\(activated ? "success" : "failed", privacy: .public)")

            var didBecomeFrontmost = false
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    didBecomeFrontmost = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            Self.pipelineLogger.notice("[Insert] target frontmost=\(didBecomeFrontmost ? "yes" : "no", privacy: .public)")
            if !didBecomeFrontmost {
                copyTextToClipboard(text)
                AppState.shared.error = L10n.ui(
                    for: AppState.shared.selectedLanguage.id,
                    fr: "Impossible de revenir à l'application cible. Le texte a été copié dans le presse-papiers.",
                    en: "Could not focus the target app. The text was copied to the clipboard.",
                    es: "No se pudo enfocar la app de destino. El texto se copió al portapapeles.",
                    zh: "无法切回目标应用，文本已复制到剪贴板。",
                    ja: "対象アプリに戻れなかったため、テキストをクリップボードにコピーしました。",
                    ru: "Не удалось вернуть фокус целевому приложению. Текст скопирован в буфер обмена."
                )
                Self.pipelineLogger.error("[Insert] aborting simulated typing: target app did not become frontmost")
                return
            }
            try? await Task.sleep(for: .milliseconds(140))
        }

        Self.pipelineLogger.notice("[Insert] posting secure typing events")
        simulateTyping(text)
        startCorrectionLearningMonitor(originalInsertedText: text)
    }

    /// Inserts text at cursor without using the global clipboard.
    func insertTextAtCursor(_ text: String) {
        simulateTyping(text)
        startCorrectionLearningMonitor(originalInsertedText: text)
    }

    private func copyTextToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Monitors focused text changes shortly after insertion and proposes dictionary learning
    /// when a single word is replaced by the user.
    private func startCorrectionLearningMonitor(originalInsertedText: String) {
        guard AXIsProcessTrusted() else { return }
        guard !originalInsertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        correctionMonitorTask?.cancel()
        correctionMonitorTask = Task {
            Self.learningLogger.notice("[DictionaryLearning] monitor started")
            Self.learningLogger.notice("[DictionaryLearning] AX trusted: \(AXIsProcessTrusted() ? "yes" : "no", privacy: .public)")
            let sandboxContainer = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
            Self.learningLogger.notice("[DictionaryLearning] sandbox active: \(sandboxContainer == nil ? "no" : "yes", privacy: .public)")
            if let app = NSWorkspace.shared.frontmostApplication {
                Self.learningLogger.notice("[DictionaryLearning] frontmost app: \(app.bundleIdentifier ?? "unknown", privacy: .public)")
            }

            // Let the paste operation settle first.
            try? await Task.sleep(for: .milliseconds(800))

            var baseline: String?
            for attempt in 1...6 {
                Self.learningLogger.notice("[DictionaryLearning] baseline attempt \(attempt)")
                let value = await MainActor.run {
                    Self.focusedTextValue(debugLabel: "baseline#\(attempt)", verbose: attempt == 1)
                }
                if let value {
                    baseline = value
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let baseline else {
                Self.learningLogger.notice("[DictionaryLearning] baseline read failed (AX value unavailable)")
                return
            }
            Self.learningLogger.notice("[DictionaryLearning] baseline length: \(baseline.count)")
            var previousValue = baseline
            var consecutiveReadFailures = 0
            let monitorStartedAt = Date()
            var lastTextChangeAt = Date()
            var lastAnalyzedValue: String?
            let stabilizationDelay: TimeInterval = 1.0
            let inactivityTimeout: TimeInterval = 12
            let maxMonitorDuration: TimeInterval = 25
            let monitoredPID = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))

                let now = Date()
                if now.timeIntervalSince(monitorStartedAt) >= maxMonitorDuration {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: max monitor duration reached")
                    return
                }
                if now.timeIntervalSince(lastTextChangeAt) >= inactivityTimeout {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: inactivity timeout")
                    return
                }

                let currentPID = await MainActor.run {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                }
                if let monitoredPID, currentPID != monitoredPID {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: frontmost app changed")
                    return
                }

                let currentValue = await MainActor.run {
                    Self.focusedTextValue(debugLabel: "poll", verbose: false)
                }
                guard let currentValue else {
                    consecutiveReadFailures += 1
                    if consecutiveReadFailures >= 3 {
                        Self.learningLogger.notice("[DictionaryLearning] stopped: repeated AX read failures; collecting verbose diagnostics")
                        _ = await MainActor.run {
                            Self.focusedTextValue(debugLabel: "poll-diagnostics", verbose: true)
                        }
                        return
                    }
                    continue
                }
                consecutiveReadFailures = 0
                if currentValue != previousValue {
                    previousValue = currentValue
                    lastTextChangeAt = Date()
                    lastAnalyzedValue = nil
                    Self.learningLogger.notice("[DictionaryLearning] text changed; waiting for stabilization")
                    continue
                }

                guard now.timeIntervalSince(lastTextChangeAt) >= stabilizationDelay else { continue }
                guard lastAnalyzedValue != currentValue else { continue }
                lastAnalyzedValue = currentValue
                Self.learningLogger.notice("[DictionaryLearning] text stabilized; running replacement detection")

                if let suggestion = Self.detectWordReplacement(from: baseline, to: currentValue) {
                    if Self.containsLearningToken(suggestion.mistakenWord, in: originalInsertedText) {
                        Self.learningLogger.notice("[DictionaryLearning] suggestion detected: \(suggestion.mistakenWord, privacy: .private(mask: .hash)) -> \(suggestion.correctedWord, privacy: .private(mask: .hash))")
                        await MainActor.run {
                            AppState.shared.proposeDictionarySuggestion(
                                mistakenWord: suggestion.mistakenWord,
                                correctedWord: suggestion.correctedWord
                            )
                        }
                        return
                    } else {
                        Self.learningLogger.notice("[DictionaryLearning] ignored suggestion: mistaken word not found in original transcription")
                    }
                }
            }
            Self.learningLogger.notice("[DictionaryLearning] stopped: task cancelled")
        }
    }

    private nonisolated static func focusedTextValue(debugLabel: String, verbose: Bool) -> String? {
        guard let focusedElement = focusedElement(verbose: verbose) else {
            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) failed: no focused element")
            }
            return nil
        }

        if verbose {
            let role = stringAttribute(from: focusedElement, attribute: kAXRoleAttribute as CFString) ?? "unknown-role"
            let subrole = stringAttribute(from: focusedElement, attribute: kAXSubroleAttribute as CFString) ?? "unknown-subrole"
            let attributes = attributeNames(of: focusedElement).joined(separator: ",")
            let paramAttributes = parameterizedAttributeNames(of: focusedElement).joined(separator: ",")
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) focused role=\(role, privacy: .public) subrole=\(subrole, privacy: .public)")
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) attrs=[\(attributes, privacy: .public)]")
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) paramAttrs=[\(paramAttributes, privacy: .public)]")
        }

        if let direct = readableText(from: focusedElement, verbose: verbose, debugLabel: "\(debugLabel)-self") {
            return direct
        }

        // Some editors (including Xcode source editor views) expose readable text
        // on a parent accessibility node rather than the focused leaf node.
        var current: AXUIElement = focusedElement
        for depth in 1...8 {
            guard let parent = parentElement(of: current) else { break }
            if verbose {
                let role = stringAttribute(from: parent, attribute: kAXRoleAttribute as CFString) ?? "unknown-role"
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) trying parent depth=\(depth) role=\(role, privacy: .public)")
            }
            if let text = readableText(from: parent, verbose: verbose, debugLabel: "\(debugLabel)-parent\(depth)") {
                return text
            }
            current = parent
        }

        if verbose {
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no readable AX text found")
        }
        return nil
    }

    private nonisolated static func focusedElement(verbose: Bool) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, 1.5)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        if focusResult == .success, let element = focusedElement {
            return axElement(from: element)
        }

        if verbose {
            Self.learningLogger.notice("[DictionaryLearning] AX focus read failed: \(focusResult.rawValue)")
            if focusResult == .cannotComplete {
                Self.learningLogger.notice("[DictionaryLearning] AX cannot complete. In Debug, disable App Sandbox or add accessibility entitlement and re-authorize Zphyr in System Settings > Privacy & Security > Accessibility.")
            }
        }

        // Fallback: query focused element through the frontmost app AX object.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 1.5)
            var appFocused: AnyObject?
            let appFocusResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocused
            )
            if appFocusResult == .success, let appFocused {
                if verbose {
                    Self.learningLogger.notice("[DictionaryLearning] AX focus fallback via app succeeded")
                }
                return axElement(from: appFocused)
            }

            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] AX app fallback failed: \(appFocusResult.rawValue)")
            }
        }

        return nil
    }

    private nonisolated static func stringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }

        if let text = value as? String {
            return text
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private nonisolated static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return axElement(from: value)
    }

    private nonisolated static func readableText(from element: AXUIElement, verbose: Bool, debugLabel: String) -> String? {
        if let value = stringAttribute(from: element, attribute: kAXValueAttribute as CFString), !value.isEmpty {
            Self.learningLogger.notice("[DictionaryLearning] AX text source: kAXValueAttribute")
            return value
        } else if verbose {
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXValueAttribute")
        }
        if let selected = stringAttribute(from: element, attribute: kAXSelectedTextAttribute as CFString), !selected.isEmpty {
            Self.learningLogger.notice("[DictionaryLearning] AX text source: kAXSelectedTextAttribute")
            return selected
        } else if verbose {
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXSelectedTextAttribute")
        }
        if let ranged = textFromRangeAPI(element, verbose: verbose, debugLabel: debugLabel), !ranged.isEmpty {
            Self.learningLogger.notice("[DictionaryLearning] AX text source: kAXStringForRangeParameterizedAttribute")
            return ranged
        } else if verbose {
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXStringForRangeParameterizedAttribute")
        }
        return nil
    }

    /// Reads text through parameterized range API. This is often available when `kAXValueAttribute`
    /// is not (e.g. some rich editors).
    private nonisolated static func textFromRangeAPI(_ element: AXUIElement, verbose: Bool, debugLabel: String) -> String? {
        var charCountObject: AnyObject?
        let countResult = AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &charCountObject
        )
        guard countResult == .success else {
            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXNumberOfCharactersAttribute failed: \(countResult.rawValue)")
            }
            return nil
        }

        let charCount: Int
        if let number = charCountObject as? NSNumber {
            charCount = number.intValue
        } else {
            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXNumberOfCharactersAttribute returned non-number")
            }
            return nil
        }
        guard charCount > 0 else {
            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) character count is 0")
            }
            return nil
        }

        var range = CFRange(location: 0, length: min(charCount, 12_000))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var outValue: AnyObject?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &outValue
        )
        guard result == .success else {
            if verbose {
                Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXStringForRangeParameterizedAttribute failed: \(result.rawValue)")
            }
            return nil
        }

        if let text = outValue as? String {
            return text
        }
        if let attributed = outValue as? NSAttributedString {
            return attributed.string
        }
        if verbose {
            Self.learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) range API returned unsupported value type")
        }
        return nil
    }

    private nonisolated static func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success, let array = names as? [String] else { return [] }
        return array
    }

    private nonisolated static func parameterizedAttributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(element, &names)
        guard result == .success, let array = names as? [String] else { return [] }
        return array
    }

    private nonisolated static func axElement(from value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private nonisolated static func detectWordReplacement(from oldText: String, to newText: String) -> DictionarySuggestion? {
        let oldChars = Array(oldText)
        let newChars = Array(newText)

        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldChars.count - prefix,
              suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        let oldStart = prefix
        let oldEnd = oldChars.count - suffix
        let newStart = prefix
        let newEnd = newChars.count - suffix

        guard oldStart < oldEnd, newStart < newEnd else { return nil }

        let oldSegment = String(oldChars[oldStart..<oldEnd])
        let newSegment = String(newChars[newStart..<newEnd])

        // Fast path: direct replacement segment is itself a full token.
        var oldToken = canonicalLearningToken(from: oldSegment)
        var newToken = canonicalLearningToken(from: newSegment)

        // Fallback: if user changed characters inside a word (e.g. "quen" -> "qwen"),
        // expand to full word boundaries and compare full words.
        if oldToken.isEmpty || newToken.isEmpty {
            if let oldRange = expandedWordRange(in: oldChars, start: oldStart, end: oldEnd),
               let newRange = expandedWordRange(in: newChars, start: newStart, end: newEnd) {
                oldToken = canonicalLearningToken(from: String(oldChars[oldRange]))
                newToken = canonicalLearningToken(from: String(newChars[newRange]))
            }
        }

        guard !oldToken.isEmpty, !newToken.isEmpty else { return nil }
        guard oldToken.caseInsensitiveCompare(newToken) != .orderedSame else { return nil }

        return DictionarySuggestion(mistakenWord: oldToken, correctedWord: newToken)
    }

    private nonisolated static func canonicalLearningToken(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        let tokens = cleaned.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1 else { return "" }
        let token = String(tokens[0]).trimmingCharacters(in: CharacterSet.punctuationCharacters)
        guard token.count >= 2 else { return "" }
        return token
    }

    private nonisolated static func expandedWordRange(
        in chars: [Character],
        start: Int,
        end: Int
    ) -> Range<Int>? {
        guard !chars.isEmpty else { return nil }

        var left = max(0, min(start, chars.count - 1))
        var right = max(0, min(end, chars.count))

        while left > 0 && isWordCharacter(chars[left - 1]) {
            left -= 1
        }
        while right < chars.count && isWordCharacter(chars[right]) {
            right += 1
        }

        guard left < right else { return nil }
        return left..<right
    }

    private nonisolated static func isWordCharacter(_ char: Character) -> Bool {
        if char.isLetter || char.isNumber {
            return true
        }
        return char == "'" || char == "’" || char == "-" || char == "_"
    }

    private nonisolated static func containsLearningToken(_ token: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "(^|[^\\p{L}\\p{N}_'’-])\(escaped)(?=$|[^\\p{L}\\p{N}_'’-])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

#if DEBUG
    nonisolated static func _test_detectWordReplacement(from oldText: String, to newText: String) -> DictionarySuggestion? {
        detectWordReplacement(from: oldText, to: newText)
    }

    nonisolated static func _test_containsLearningToken(_ token: String, in text: String) -> Bool {
        containsLearningToken(token, in: text)
    }
#endif

    private func simulateTyping(_ text: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for scalar in text.unicodeScalars {
            let codeUnit = UniChar(scalar.value)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            var mutable = codeUnit
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
