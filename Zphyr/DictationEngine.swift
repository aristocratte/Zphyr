//
//  DictationEngine.swift
//  Zphyr
//
//  Thin orchestrator: coordinates AudioCaptureService → ASROrchestrator →
//  TranscriptStabilizer → FormatterOrchestrator → InsertionEngine.
//  No external LLM. All processing is 100% local.
//
//  Extracted modules (Phase 1 refactor):
//    AudioCaptureService.swift  — AVAudioEngine, resampling, HUD
//    ASROrchestrator.swift      — VAD, multi-backend, quality gating
//    TranscriptStabilizer.swift — filler removal, list detection, tone
//    InsertionEngine.swift      — CGEvent injection, clipboard fallback
//    ModelManager.swift         — model download/load lifecycle
//    WhisperLanguage.swift      — language data model
//    LocalMetrics.swift         — privacy-safe timing metrics
//    CommandInterpreter.swift   — spoken command stub
//

import CryptoKit
import Foundation
@preconcurrency import AVFoundation
import AppKit
import Observation
import os

// WhisperLanguage, AudioSampleBuffer, LockedFlag, AudioFileLoadError
// are now in their respective extracted modules.

// MARK: - DictationEngine
@Observable
@MainActor
final class DictationEngine {
    static let shared = DictationEngine()
    private nonisolated static let learningLogger = Logger(subsystem: "com.zphyr.app", category: "DictionaryLearning")
    private nonisolated static let modelLogger = Logger(subsystem: "com.zphyr.app", category: "ModelLoad")
    private nonisolated static let pipelineLogger = Logger(subsystem: "com.zphyr.app", category: "DictationPipeline")
    private nonisolated static func debugPreview(_ text: String, limit: Int = 320) -> String {
        #if DEBUG
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else { return normalized }
        let remaining = normalized.count - limit
        return "\(normalized.prefix(limit))…(+\(remaining) chars)"
        #else
        // Production: never log dictation content. Length + truncated hash
        // is enough to correlate the same input across log lines without
        // exposing what the user said. (Logger sites still wrap this in
        // privacy: .public; the content itself is now redacted at source.)
        return "redacted len=\(text.count) hash=\(Self.contentHash(text))"
        #endif
    }

    nonisolated static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Extracted services (Phase 1 refactor)
    // These replace previously inlined logic in this file.
    private let audioCaptureService = AudioCaptureService()
    private let asrOrchestrator = ASROrchestrator()
    private let transcriptStabilizer = TranscriptStabilizer()
    private let formattingPipeline = FormattingPipeline()
    private let insertionEngineService = InsertionEngine()
    private let modelManager = ModelManager()

    /// Prevents overlapping dictation sessions (start/stop race conditions).
    private var isDictating: Bool = false
    /// Prevents re-entrant calls to startDictation() during the async mic-permission check.
    private var isArming: Bool = false

    /// True while a previous transcription/insertion is still in-flight.
    /// Prevents a new dictation from starting until the pipeline is fully done.
    private var isProcessing: Bool = false

    private let overlayController = DictationOverlayController()

    private struct RetryPayload {
        let audioSamples: [Float]
        let capturedSampleCount: Int
        let languageCode: String?
        let targetBundleID: String?
    }

    /// The app that was frontmost when the user started dictating.
    /// We restore focus to it before injecting text.
    private var targetApp: NSRunningApplication?
    private var lastRetryPayload: RetryPayload? {
        didSet {
            AppState.shared.retryLastSessionAvailable = lastRetryPayload != nil
        }
    }
    private var cancelledSessionIDs: Set<UUID> = []
    private var correctionMonitorTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var lastTranscriptionBackendName: String = "unknown"
    private var asrBackend: any ASRService
    private let ecoTextFormatter = EcoTextFormatter()
    private let proTextFormatter = ProTextFormatter()
    private let whisperBaseTranscriptionTimeoutSeconds: Double = 20.0
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

    private struct PostProcessResult {
        let text: String
        let listBlocksCount: Int
    }

    struct TranscriptionCandidate {
        let text: String
        let backendDisplayName: String
        let qualityIssue: String?
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
            refreshNonInstallBackendStatus(asrBackend)
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
            refreshNonInstallBackendStatus(asrBackend)
        }
    }

    private func refreshNonInstallBackendStatus(_ backend: any ASRService) {
        AppState.shared.modelStatus = backend.isLoaded
            ? .ready
            : .failed(backend.installError ?? "\(backend.descriptor.displayName) is not ready.")
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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Self.modelLogger.notice("[ModelLoad] skipping backend load under XCTest")
            return
        }

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

    /// Loads the selected backend only when its files are already present locally.
    /// This is used by launch/preflight paths so the app never downloads a model
    /// until the user explicitly presses an install/download action.
    func loadInstalledModelIfAvailable() async {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Self.modelLogger.notice("[ModelLoad] skipping installed-only backend load under XCTest")
            return
        }

        let state = AppState.shared
        state.refreshPerformanceProfile()
        let effectivePreferred = PerformanceRouter.shared.effectiveASRBackend(
            preferred: state.preferredASRBackend,
            profile: state.performanceProfile
        )
        if effectivePreferred != currentASRBackendKind {
            setASRBackend(effectivePreferred)
        }

        let backend = asrBackend
        state.activeASRBackend = backend.descriptor.kind

        if backend.descriptor.requiresModelInstall {
            await backend.loadIfInstalled()
            state.modelInstallPath = backend.installPath
            state.downloadStats = DownloadStats()
            state.isDownloadPaused = false
            state.modelStatus = backend.isLoaded ? .ready : .notDownloaded
            return
        }

        state.modelStatus = .loading
        await backend.loadIfInstalled()
        state.modelInstallPath = backend.installPath
        state.downloadStats = DownloadStats()
        state.isDownloadPaused = false
        refreshNonInstallBackendStatus(backend)
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
            refreshNonInstallBackendStatus(asrBackend)
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
            refreshNonInstallBackendStatus(asrBackend)
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
            refreshNonInstallBackendStatus(backend)
            if backend.isLoaded {
                Self.modelLogger.notice("[ModelLoad] backend ready without install: \(descriptor.displayName, privacy: .public)")
            } else {
                Self.modelLogger.warning("[ModelLoad] backend unavailable without install: \(descriptor.displayName, privacy: .public)")
            }
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
                if AppState.shared.advancedModeInstalled,
                   AppState.shared.formattingMode != .trigger,
                   !AdvancedLLMFormatter.shared.isModelLoaded {
                    Task {
                        await AdvancedLLMFormatter.shared.loadIfInstalled()
                        await AdvancedLLMFormatter.shared.warmup()
                    }
                }
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
                try await Task.sleep(for: .milliseconds(500))
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
            if AppState.shared.advancedModeInstalled,
               AppState.shared.formattingMode != .trigger,
               !AdvancedLLMFormatter.shared.isModelLoaded {
                Task {
                    await AdvancedLLMFormatter.shared.loadIfInstalled()
                    await AdvancedLLMFormatter.shared.warmup()
                }
            }
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
        guard !isDictating, !isArming else { return }
        // ── Guard: previous transcription still in-flight ────────────────────
        guard !isProcessing else { return }
        // Claim the slot immediately to prevent re-entry across async suspension points
        isArming = true
        defer { isArming = false }

        let state = AppState.shared
        targetApp = NSWorkspace.shared.frontmostApplication
        let transcriptionPlan = asrOrchestrator.liveTranscriptionPlan(for: asrBackend)
        let outputProfile = state.activeOutputProfile(for: targetApp?.bundleIdentifier)
        state.beginDictationSession(
            targetBundleID: targetApp?.bundleIdentifier,
            transcriptionMode: transcriptionPlan.mode,
            outputProfile: outputProfile
        )
        state.error = nil
        overlayController.show()

        // ── Guard: microphone ─────────────────────────────────────────────────
        // Only show the system dialog when permission is unknown/denied.
        // If already granted, skip the async call entirely to avoid a suspension
        // window where the key could be released before we even start the engine.
        if state.micPermission != .granted {
            let granted = await state.requestMicrophoneAccess()
            guard granted else {
                let errorMessage = L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Accès au microphone refusé. Autorisez Zphyr dans Réglages Système → Confidentialité → Microphone.",
                    en: "Microphone access denied. Allow Zphyr in System Settings → Privacy & Security → Microphone.",
                    es: "Acceso al micrófono denegado. Autoriza Zphyr en Ajustes del Sistema → Privacidad y seguridad → Micrófono.",
                    zh: "麦克风权限被拒绝。请在 系统设置 → 隐私与安全性 → 麦克风 中允许 Zphyr。",
                    ja: "マイクへのアクセスが拒否されました。システム設定 → プライバシーとセキュリティ → マイク で Zphyr を許可してください。",
                    ru: "Доступ к микрофону запрещен. Разрешите Zphyr в Системных настройках → Конфиденциальность и безопасность → Микрофон."
                )
                state.finishCurrentDictationSession(
                    phase: .failure,
                    note: "microphone_access_denied",
                    errorMessage: errorMessage
                )
                hideOverlay(for: .failure)
                targetApp = nil
                return
            }
            // After the async permission check, verify the key is still held.
            // The user may have released it while the dialog was showing.
            guard ShortcutManager.shared.isHolding else {
                state.finishCurrentDictationSession(
                    phase: .cancelled,
                    note: "key_released_during_arming"
                )
                hideOverlay(for: .cancelled)
                targetApp = nil
                return
            }
        }

        // ── Guard: ASR backend ready ──────────────────────────────────────────
        guard state.modelStatus.isReady, asrBackend.isLoaded else {
            let errorMessage = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Le moteur de dictée n'est pas encore prêt.",
                en: "The dictation backend is not ready yet.",
                es: "El backend de dictado aún no está listo.",
                zh: "听写后端尚未就绪。",
                ja: "音声入力バックエンドはまだ準備できていません。",
                ru: "Бэкенд диктовки еще не готов."
            )
            state.finishCurrentDictationSession(
                phase: .failure,
                note: "backend_not_ready",
                errorMessage: errorMessage
            )
            hideOverlay(for: .failure)
            targetApp = nil
            return
        }

        isDictating = true

        Self.pipelineLogger.notice("[Dictation] start; target app=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public)")

        guard audioCaptureService.startCapture(onLevels: { [weak self] levels in
            Task { @MainActor in self?.updateHUDLevels(levels) }
        }, onAudioChunk: nil) else {
            isDictating = false
            targetApp = nil
            let errorMessage = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Impossible de démarrer l'enregistrement audio.",
                en: "Unable to start audio capture.",
                es: "No se pudo iniciar la captura de audio.",
                zh: "无法启动音频采集。",
                ja: "音声収録を開始できませんでした。",
                ru: "Не удалось запустить захват аудио."
            )
            state.finishCurrentDictationSession(
                phase: .failure,
                note: "audio_capture_start_failed",
                errorMessage: errorMessage
            )
            hideOverlay(for: .failure)
            return
        }
        state.transitionCurrentDictationSession(to: .recording)
        playDictationStartSound()
    }

    func stopDictation() async {
        guard isDictating else { return }
        isDictating = false
        isProcessing = true

        let state = AppState.shared
        let speechEndedAt = Date()
        audioCaptureService.stopCapture()
        // Give CoreAudio a brief moment to flush the last callback before snapshotting.
        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms
        let capturedSamples = audioCaptureService.sampleCount
        let audioSnapshot = audioCaptureService.snapshotSamples()
        let languages = state.selectedLanguages
        let languageCode: String? = languages.count > 1 ? nil : (languages.first?.id ?? "fr")
        lastRetryPayload = audioSnapshot.isEmpty ? nil : RetryPayload(
            audioSamples: audioSnapshot,
            capturedSampleCount: capturedSamples,
            languageCode: languageCode,
            targetBundleID: targetApp?.bundleIdentifier
        )
        let sessionID = state.currentDictationSession?.id
        Self.pipelineLogger.notice("[Dictation] stop; captured samples=\(capturedSamples)")
        await processCapturedAudioSession(
            audioSnapshot: audioSnapshot,
            capturedSamples: capturedSamples,
            language: languageCode,
            sessionID: sessionID,
            isRetry: false,
            speechEndedAt: speechEndedAt
        )
    }

    func cancelCurrentSession(source: String = "unspecified") {
        let state = AppState.shared
        guard let session = state.currentDictationSession else { return }
        let currentEventSummary = Self.currentEventDebugSummary()

        // Log the call stack to debug unexpected cancellations
        let callStack = Thread.callStackSymbols.prefix(8).joined(separator: "\n  ")
        Self.pipelineLogger.notice(
            "[Dictation] cancelCurrentSession id=\(session.id.uuidString, privacy: .public) phase=\(session.phase.rawValue, privacy: .public) source=\(source, privacy: .public) isDictating=\(self.isDictating, privacy: .public) isProcessing=\(self.isProcessing, privacy: .public) target=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public) event=\(currentEventSummary, privacy: .public)\n  caller stack:\n  \(callStack, privacy: .public)"
        )

        // Guard: if transcription/formatting is in-flight (isProcessing == true,
        // isDictating == false), reject the cancel to prevent the LiveDictationBanner's
        // X button from accidentally killing a running pipeline.
        if isProcessing && !isDictating {
            Self.pipelineLogger.warning("[Dictation] cancelCurrentSession BLOCKED — pipeline is processing; ignoring cancel request")
            return
        }

        cancelledSessionIDs.insert(session.id)

        if isDictating {
            audioCaptureService.stopCapture()
            audioCaptureService.resetBuffer()
            isDictating = false
            isProcessing = false
        }

        state.finishCurrentDictationSession(
            phase: .cancelled,
            note: "user_cancelled"
        )
        playDictationEndSound()
        hideOverlay(for: .cancelled)
        targetApp = nil
    }

    private static func currentEventDebugSummary() -> String {
        guard let event = NSApp.currentEvent else { return "none" }
        let characters = event.charactersIgnoringModifiers?.replacingOccurrences(of: "\n", with: "\\n") ?? "nil"
        return "type=\(event.type.rawValue) keyCode=\(event.keyCode) chars=\(characters) clickCount=\(event.clickCount) window=\(event.windowNumber)"
    }

    func retryLastSession() async {
        let state = AppState.shared
        guard !isDictating, !isProcessing else {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Une dictée est déjà en cours.",
                en: "A dictation session is already running.",
                es: "Ya hay una sesión de dictado en curso.",
                zh: "已有听写会话正在进行中。",
                ja: "すでに音声入力セッションが実行中です。",
                ru: "Сеанс диктовки уже выполняется."
            )
            return
        }
        guard let payload = lastRetryPayload else {
            state.error = L10n.ui(
                for: state.selectedLanguage.id,
                fr: "Aucun buffer audio disponible pour relancer la dernière dictée.",
                en: "No audio buffer is available to retry the last dictation.",
                es: "No hay buffer de audio disponible para reintentar el último dictado.",
                zh: "没有可用于重试上次听写的音频缓冲区。",
                ja: "前回の音声入力を再試行するための音声バッファがありません。",
                ru: "Нет аудиобуфера для повторного запуска последней диктовки."
            )
            return
        }

        isProcessing = true
        targetApp = payload.targetBundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        } ?? NSWorkspace.shared.frontmostApplication

        let transcriptionPlan = asrOrchestrator.liveTranscriptionPlan(for: asrBackend)
        state.beginDictationSession(
            targetBundleID: payload.targetBundleID ?? targetApp?.bundleIdentifier,
            transcriptionMode: transcriptionPlan.mode,
            outputProfile: state.activeOutputProfile(for: payload.targetBundleID ?? targetApp?.bundleIdentifier)
        )
        state.transitionCurrentDictationSession(to: .retrying, note: "retry_last_session")
        overlayController.show()

        await processCapturedAudioSession(
            audioSnapshot: payload.audioSamples,
            capturedSamples: payload.capturedSampleCount,
            language: payload.languageCode,
            sessionID: state.currentDictationSession?.id,
            isRetry: true
        )
    }

    private func processCapturedAudioSession(
        audioSnapshot: [Float],
        capturedSamples: Int,
        language: String?,
        sessionID: UUID?,
        isRetry: Bool,
        speechEndedAt: Date? = nil
    ) async {
        let state = AppState.shared
        let transcriptionPlan = asrOrchestrator.liveTranscriptionPlan(for: asrBackend)
        let effectiveTranscriptionMode: ASRTranscriptionMode = {
            if transcriptionPlan.mode == .streamingPartials,
               asrOrchestrator.makeStreamingSession(for: asrBackend, language: language) != nil {
                return .streamingPartials
            }
            return .finalOnly
        }()

        state.updateCurrentLiveTranscription(clearPartialText: true, mode: effectiveTranscriptionMode)
        state.transitionCurrentDictationSession(to: .transcribing)

        var metrics = DictationSessionMetrics()
        metrics.sessionID = sessionID ?? metrics.sessionID
        metrics.capturedSampleCount = capturedSamples
        metrics.transcriptionMode = effectiveTranscriptionMode
        metrics.partialUpdatesCount = 0
        metrics.retriedFromBuffer = isRetry
        metrics.speechEndedAt = speechEndedAt

        if shouldAbortProcessing(for: sessionID) {
            return
        }

        metrics.asrStartedAt = Date()
        Self.pipelineLogger.notice(
            "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=asr_start speechToAsr=\(metrics.speechEndToASRStartMs, privacy: .public)ms"
        )
        let asrStartedAt = CFAbsoluteTimeGetCurrent()
        let rawText = await runASRTranscription(audioSnapshot: audioSnapshot, language: language)
        Self.pipelineLogger.notice(
            "[Dictation] ASR raw preview=\"\(Self.debugPreview(rawText), privacy: .public)\""
        )
        metrics.rawTranscriptReadyAt = Date()
        metrics.asrDurationMs = Int((CFAbsoluteTimeGetCurrent() - asrStartedAt) * 1_000)
        Self.pipelineLogger.notice(
            "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=raw_transcript_ready asrToRaw=\(metrics.asrToRawTranscriptMs, privacy: .public)ms"
        )
        metrics.rawCharacterCount = rawText.count
        metrics.backendName = lastTranscriptionBackendName
        metrics.outputProfile = state.currentDictationSession?.outputProfile.rawValue ?? ""
        state.updateCurrentLiveTranscription(
            clearPartialText: true,
            finalText: rawText,
            mode: effectiveTranscriptionMode
        )

        if shouldAbortProcessing(for: sessionID) {
            return
        }

        let pipelineInput = TranscriptionInput(
            rawText: rawText,
            languageCode: state.selectedLanguage.id,
            targetBundleID: targetApp?.bundleIdentifier
        )
        if !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.transitionCurrentDictationSession(to: .formatting)
        }
        let pipelineResult = await formattingPipeline.run(pipelineInput)

        if shouldAbortProcessing(for: sessionID) {
            return
        }

        metrics.formattingCompletedAt = Date()
        let finalText = pipelineResult.finalText
        let formatterDurationMs = Int(
            pipelineResult.trace
                .filter(\.isModelBased)
                .map(\.durationMs)
                .reduce(0, +)
                .rounded()
        )
        metrics.stabilizeDurationMs = max(0, Int(pipelineResult.totalDurationMs.rounded()) - formatterDurationMs)
        metrics.listBlocksDetected = pipelineResult.listBlocksCount
        metrics.formatterDurationMs = formatterDurationMs
        metrics.finalCharacterCount = finalText.count
        metrics.formatterMode = state.formattingMode.rawValue
        metrics.pipelineDecision = pipelineResult.decision
        metrics.pipelineFallbackReason = pipelineResult.fallbackReason
        metrics.usedFormatterFallback = pipelineResult.decision == .deterministicFallback
        Self.pipelineLogger.notice(
            "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=formatting_complete rawToFinal=\(metrics.rawTranscriptToFormattingFinalMs, privacy: .public)ms"
        )
        state.updateCurrentDictationSession(
            pipelineDecision: pipelineResult.decision,
            pipelineFallbackReason: pipelineResult.fallbackReason,
            pipelineTrace: pipelineResult.trace,
            finalTextPreview: finalText
        )

        let recognizedCommand = pipelineResult.extractedCommand
        if recognizedCommand == .cancelLast {
            Self.pipelineLogger.notice("[Dictation] cancel command detected — discarding")
            metrics.sessionCompletedAt = Date()
            Self.pipelineLogger.notice(
                "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=session_complete e2e=\(metrics.endToEndDurationMs, privacy: .public)ms speechToAsr=\(metrics.speechEndToASRStartMs, privacy: .public)ms asrToRaw=\(metrics.asrToRawTranscriptMs, privacy: .public)ms rawToFinal=\(metrics.rawTranscriptToFormattingFinalMs, privacy: .public)ms finalToInsert=\(metrics.formattingFinalToInsertionMs, privacy: .public)ms"
            )
            LocalMetricsRecorder.shared.record(metrics)
            state.finishCurrentDictationSession(
                phase: .cancelled,
                note: "cancel_command_detected",
                finalTextPreview: finalText,
                pipelineDecision: pipelineResult.decision,
                pipelineFallbackReason: pipelineResult.fallbackReason,
                pipelineTrace: pipelineResult.trace
            )
            targetApp = nil
            playDictationEndSound()
            hideOverlay(for: .cancelled)
            isProcessing = false
            return
        }

        Self.pipelineLogger.notice(
            "[Dictation] pipeline completed preview=\"\(Self.debugPreview(finalText), privacy: .public)\" dur=\(String(format: "%.1f", pipelineResult.totalDurationMs), privacy: .public)ms stages=\(pipelineResult.trace.count, privacy: .public)"
        )
        Self.pipelineLogger.notice(
            "[Dictation] pipeline decision=\(pipelineResult.decision.rawValue, privacy: .public) fallbackReason=\(pipelineResult.fallbackReason?.rawValue ?? "none", privacy: .public)"
        )
        Self.pipelineLogger.notice("[Dictation] transcription lengths raw=\(rawText.count) final=\(finalText.count)")

        state.lastTranscription = finalText

        if !finalText.isEmpty {
            let shouldCopyOnly = recognizedCommand == .copyOnly || !state.autoInsert
            let insertionStartedAt = CFAbsoluteTimeGetCurrent()
            let insertionOutcome: InsertionOutcome
            state.transitionCurrentDictationSession(to: .inserting)
            if shouldCopyOnly {
                insertionOutcome = insertionEngineService.copyToClipboard(
                    finalText,
                    strategy: .clipboardOnly
                )
                Self.pipelineLogger.notice("[Dictation] copied to clipboard (\(recognizedCommand == .copyOnly ? "copyOnly command" : "autoInsert=off", privacy: .public))")
            } else {
                insertionOutcome = await insertionEngineService.insert(finalText, into: targetApp)
            }

            if shouldAbortProcessing(for: sessionID) {
                return
            }

            metrics.insertionDurationMs = Int((CFAbsoluteTimeGetCurrent() - insertionStartedAt) * 1_000)
            metrics.insertionCompletedAt = Date()
            metrics.insertionTargetFamily = insertionOutcome.targetFamily.rawValue
            metrics.insertionStrategy = insertionOutcome.strategy.rawValue
            metrics.insertionFallbackReason = insertionOutcome.fallbackReason
            Self.pipelineLogger.notice(
                "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=insertion_complete finalToInsert=\(metrics.formattingFinalToInsertionMs, privacy: .public)ms"
            )
            state.updateCurrentDictationSession(
                insertionStrategy: insertionOutcome.strategy,
                insertionFallbackReason: insertionOutcome.fallbackReason
            )
            state.finishCurrentDictationSession(
                phase: .success,
                finalTextPreview: finalText,
                pipelineDecision: pipelineResult.decision,
                pipelineFallbackReason: pipelineResult.fallbackReason,
                pipelineTrace: pipelineResult.trace,
                insertionStrategy: insertionOutcome.strategy,
                insertionFallbackReason: insertionOutcome.fallbackReason
            )
        } else {
            Self.pipelineLogger.notice("[Dictation] no transcription text — bufferCount=\(capturedSamples, privacy: .public) rawText.count=\(rawText.count, privacy: .public)")
            let surfacedError = state.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionErrorMessage = state.currentDictationSession?.errorMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorMessage = ((surfacedError?.isEmpty == false) ? surfacedError : nil)
            ?? ((sessionErrorMessage?.isEmpty == false) ? sessionErrorMessage : nil)
            ?? {
                if capturedSamples < 1600 {
                    return L10n.ui(
                        for: state.selectedLanguage.id,
                        fr: "Enregistrement trop court. Maintiens la touche et parle, puis relâche.",
                        en: "Recording too short. Hold the key while speaking, then release.",
                        es: "Grabación demasiado corta. Mantén la tecla mientras hablas.",
                        zh: "录音太短，请按住按键说话再松开。",
                        ja: "録音が短すぎます。キーを押しながら話し、離してください。",
                        ru: "Запись слишком короткая. Удерживайте клавишу пока говорите."
                    )
                }
                return L10n.ui(
                    for: state.selectedLanguage.id,
                    fr: "Aucun texte détecté (\(capturedSamples/16)ms audio). Parle plus fort ou plus longtemps.",
                    en: "No text detected (\(capturedSamples/16)ms audio). Speak louder or longer.",
                    es: "No se detectó texto (\(capturedSamples/16)ms audio). Habla más fuerte o más tiempo.",
                    zh: "未检测到文本（\(capturedSamples/16)ms 音频）。请说得更大声或更长。",
                    ja: "テキストが検出されませんでした（\(capturedSamples/16)ms の音声）。もっと大きく、または長く話してください。",
                    ru: "Текст не распознан (\(capturedSamples/16) мс аудио). Говорите громче или дольше."
                )
            }()
            state.finishCurrentDictationSession(
                phase: .failure,
                note: "empty_final_text",
                pipelineDecision: pipelineResult.decision,
                pipelineFallbackReason: pipelineResult.fallbackReason,
                pipelineTrace: pipelineResult.trace,
                errorMessage: errorMessage
            )
        }

        metrics.sessionCompletedAt = Date()
        Self.pipelineLogger.notice(
            "[Latency] session=\(metrics.sessionID.uuidString, privacy: .public) stage=session_complete e2e=\(metrics.endToEndDurationMs, privacy: .public)ms speechToAsr=\(metrics.speechEndToASRStartMs, privacy: .public)ms asrToRaw=\(metrics.asrToRawTranscriptMs, privacy: .public)ms rawToFinal=\(metrics.rawTranscriptToFormattingFinalMs, privacy: .public)ms finalToInsert=\(metrics.formattingFinalToInsertionMs, privacy: .public)ms"
        )
        LocalMetricsRecorder.shared.record(metrics)
        targetApp = nil
        playDictationEndSound()
        hideOverlayForLatestSession()

        try? await Task.sleep(for: .milliseconds(600))
        state.resetLegacyDictationState()
        isProcessing = false
    }

    private func shouldAbortProcessing(for sessionID: UUID?) -> Bool {
        guard let sessionID else { return false }
        guard cancelledSessionIDs.contains(sessionID) else { return false }
        cancelledSessionIDs.remove(sessionID)
        Self.pipelineLogger.notice("[Dictation] aborted processing for cancelled session id=\(sessionID.uuidString, privacy: .public)")
        targetApp = nil
        isProcessing = false
        return true
    }

    private func hideOverlay(for phase: DictationSessionPhase) {
        overlayController.hide(after: overlayHideDelay(for: phase))
    }

    private func hideOverlayForLatestSession() {
        let phase = AppState.shared.latestDictationSession?.phase ?? .success
        hideOverlay(for: phase)
    }

    private func overlayHideDelay(for phase: DictationSessionPhase) -> TimeInterval {
        switch phase {
        case .failure:
            return 2.4
        default:
            return 0.6
        }
    }

    // MARK: - Text Formatter Pipeline

    // MARK: - Legacy Post-ASR Helpers

    // These helpers are no longer on the active runtime path.
    // FormattingPipeline.run(_:) is the single source of truth for live dictation.
    // Keep this section read-only until the legacy implementation is fully removed.
    private func applyFormattingPipeline(
        rawASRText: String,
        normalizedText: String,
        listBlocksCount: Int
    ) async -> String {
        guard !normalizedText.isEmpty else {
            Self.pipelineLogger.notice("[Formatting] skipped: normalized text is empty")
            return normalizedText
        }

        let state = AppState.shared
        state.refreshPerformanceProfile()
        let effectiveMode = PerformanceRouter.shared.effectiveFormattingMode(
            preferred: state.formattingMode,
            profile: state.performanceProfile
        )
        let llmRuntimeLoaded = AdvancedLLMFormatter.shared.isModelLoaded(modelID: state.activeFormattingModel)
        Self.pipelineLogger.notice(
            "[Formatting] mode selection preferred=\(state.formattingMode.rawValue, privacy: .public) effective=\(effectiveMode.rawValue, privacy: .public) formatterModel=\(state.activeFormattingModel.rawValue, privacy: .public) proUnlocked=\(state.isProModeUnlocked, privacy: .public) advancedInstalled=\(state.advancedModeInstalled, privacy: .public) llmLoaded=\(llmRuntimeLoaded, privacy: .public) tier=\(state.performanceProfile.tier.rawValue, privacy: .public)"
        )
        let context = TextFormatterContext(
            rawASRText: rawASRText,
            normalizedText: normalizedText,
            languageCode: state.selectedLanguage.id,
            outputProfile: state.activeOutputProfile(for: targetApp?.bundleIdentifier),
            formattingModelID: state.activeFormattingModel,
            protectedTerms: DictionaryStore.shared.sortedProtectedTerms,
            defaultCodeStyle: state.defaultCodeStyle,
            preferredMode: effectiveMode
        )
        let sanitizedLLMInput = ProTextFormatter.llmInput(for: context)

        let formatter: any TextFormatter
        if effectiveMode == .advanced && state.isProModeUnlocked {
            state.dictationState = .formatting
            formatter = proTextFormatter
            Self.pipelineLogger.notice("[Formatting] ✅ using PRO formatter (LLM) — mode=\(effectiveMode.rawValue, privacy: .public) proUnlocked=true tier=\(state.performanceProfile.tier.rawValue, privacy: .public)")
        } else {
            formatter = ecoTextFormatter
            var reasons: [String] = []
            if effectiveMode != .advanced { reasons.append("effectiveMode=\(effectiveMode.rawValue)") }
            if !state.isProModeUnlocked { reasons.append("proUnlocked=false") }
            if !state.advancedModeInstalled { reasons.append("advancedInstalled=false") }
            let reasonText = reasons.isEmpty ? "none" : reasons.joined(separator: ",")
            Self.pipelineLogger.notice("[Formatting] ⚠️ using ECO formatter (regex only) — preferredMode=\(state.formattingMode.rawValue, privacy: .public) effectiveMode=\(effectiveMode.rawValue, privacy: .public) proUnlocked=\(state.isProModeUnlocked, privacy: .public) tier=\(state.performanceProfile.tier.rawValue, privacy: .public) advancedInstalled=\(state.advancedModeInstalled, privacy: .public) reason=\(reasonText, privacy: .public)")
        }
        Self.pipelineLogger.notice(
            "[Formatting] input rawLen=\(rawASRText.count, privacy: .public) postLen=\(normalizedText.count, privacy: .public) listBlocksCount=\(listBlocksCount, privacy: .public) backend=\(self.lastTranscriptionBackendName, privacy: .public)"
        )
        Self.pipelineLogger.notice(
            "[Formatting] input rawPreview=\"\(Self.debugPreview(rawASRText), privacy: .public)\" postPreview=\"\(Self.debugPreview(normalizedText), privacy: .public)\""
        )
        if effectiveMode == .advanced && state.isProModeUnlocked {
            Self.pipelineLogger.notice(
                "[Formatting] llm input sanitizedLen=\(sanitizedLLMInput.count, privacy: .public) sanitizedPreview=\"\(Self.debugPreview(sanitizedLLMInput), privacy: .public)\""
            )
        }

        let result = await formatter.format(context)
        let llmAttempted = result.llmInputLength != nil
        let llmReturnedText = result.llmOutputLength != nil
        let pipelineDecision: String
        if !llmAttempted {
            pipelineDecision = "regex-only"
        } else if !result.usedDeterministicFallback {
            pipelineDecision = "accepted-llm-output"
        } else if result.llmInputLength == 0 {
            pipelineDecision = "fallback-sanitized-input-empty"
        } else if llmReturnedText {
            pipelineDecision = "fallback-replaced-llm-output"
        } else {
            pipelineDecision = "fallback-after-llm-nil"
        }
        Self.pipelineLogger.notice(
            "[Formatting] decision=\(pipelineDecision, privacy: .public) llmAttempted=\(llmAttempted, privacy: .public) llmReturnedText=\(llmReturnedText, privacy: .public) usedFallback=\(result.usedDeterministicFallback, privacy: .public)"
        )
        if result.usedDeterministicFallback {
            Self.pipelineLogger.notice("[Formatting] result: deterministic fallback (rejectedTokens=\(result.rejectedIntroducedTokens.count, privacy: .public))")
        } else {
            Self.pipelineLogger.notice("[Formatting] result: LLM text accepted")
        }
        Self.pipelineLogger.notice(
            "[Formatting] metrics llmInLen=\(result.llmInputLength ?? -1, privacy: .public) llmOutLen=\(result.llmOutputLength ?? -1, privacy: .public) recall=\(result.llmRecall ?? -1, privacy: .public) validationDecision=\(result.llmValidationDecision ?? "none", privacy: .public)"
        )
        if result.usedDeterministicFallback, !result.rejectedIntroducedTokens.isEmpty {
            Self.pipelineLogger.warning(
                "[Dictation] integrity fallback triggered; rejected tokens=\(result.rejectedIntroducedTokens.joined(separator: ","), privacy: .private(mask: .hash))"
            )
        }
        if result.usedDeterministicFallback, llmReturnedText {
            Self.pipelineLogger.warning(
                "[Formatting] fallback replaced LLM output after downstream validation finalPreview=\"\(Self.debugPreview(result.text), privacy: .public)\""
            )
        }
        Self.pipelineLogger.notice(
            "[Formatting] output preview=\"\(Self.debugPreview(result.text), privacy: .public)\""
        )
        return result.text
    }

    // MARK: - Audio Capture (delegated to AudioCaptureService)

    /// Called from AudioCaptureService's onLevels callback to push HUD updates.
    private func updateHUDLevels(_ levels: [Float]) {
        AppState.shared.updateAudioLevels(levels)
    }

    // MARK: - Transcription

    private func runASRTranscription() async -> String {
        let audioSnapshot = audioCaptureService.snapshotSamples()
        let languages = AppState.shared.selectedLanguages
        let lang: String? = languages.count > 1 ? nil : (languages.first?.id ?? "fr")
        return await runASRTranscription(audioSnapshot: audioSnapshot, language: lang)
    }

    private func runASRTranscription(
        audioSnapshot: [Float],
        language lang: String?
    ) async -> String {
        await transcribeAudioSamples(audioSnapshot, language: lang, surfaceErrorsModally: false)
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
            samples = try await Task.detached(priority: .userInitiated) {
                try AudioCaptureService.loadAudioFile(at: url)
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

        let rawText = await transcribeAudioSamples(samples, language: language.id, surfaceErrorsModally: true)
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
        language lang: String?,
        surfaceErrorsModally: Bool
    ) async -> String {
        let vad = VoiceActivityDetector(sampleRate: AudioCaptureService.sampleRate)
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
            let errorMessage = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "Aucune voix détectée dans l'audio. Réessaie en parlant plus près du micro.",
                en: "No voice detected in the audio. Try speaking closer to the microphone.",
                es: "No se detectó voz en el audio. Intenta hablar más cerca del micrófono.",
                zh: "音频中未检测到语音。请靠近麦克风重试。",
                ja: "音声が検出されませんでした。マイクに近づいて再試行してください。",
                ru: "В аудио не обнаружен голос. Попробуйте говорить ближе к микрофону."
            )
            await surfaceASRError(errorMessage, modally: surfaceErrorsModally)
            Self.pipelineLogger.error("[Dictation] VAD rejected audio: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        let durationMs = Int(Double(processedAudio.count) / 16.0)
        let primaryBackendName = asrBackend.descriptor.displayName
        let primaryLoaded = asrBackend.isLoaded
        lastTranscriptionBackendName = primaryBackendName
        Self.pipelineLogger.notice("[Dictation] transcribeAudioSamples: samples=\(processedAudio.count, privacy: .public) (~\(durationMs, privacy: .public)ms) lang=\(lang ?? "auto", privacy: .public) backend=\(primaryBackendName, privacy: .public) loaded=\(primaryLoaded, privacy: .public)")

        guard !processedAudio.isEmpty else {
            Self.pipelineLogger.error("[Dictation] audioSnapshot is EMPTY — no audio was captured")
            return ""
        }

        let candidates = transcriptionCandidatesForCurrentRequest()
        let orderedNames = candidates.map { $0.descriptor.displayName }.joined(separator: " -> ")
        Self.pipelineLogger.notice("[Dictation] decoding candidates=\(orderedNames, privacy: .public)")

        var lastFailure: Error?
        var successfulCandidates: [TranscriptionCandidate] = []
        for (index, backend) in candidates.enumerated() {
            let descriptor = backend.descriptor

            if descriptor.requiresModelInstall && !backend.isLoaded {
                Self.pipelineLogger.error("[Dictation] decoding skipped attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) reason=backend not loaded")
                continue
            }

            let timeout = dynamicTranscriptionTimeout(
                for: descriptor.kind,
                durationMs: durationMs
            )
            Self.pipelineLogger.notice("[Dictation] decoding attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) timeout=\(timeout, privacy: .public)s")

            do {
                let raw = try await transcribeWithTimeout(
                    backend: backend,
                    audio: processedAudio,
                    timeoutSeconds: timeout
                )
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw ASRBackendError.emptyResult }

                let qualityIssue = Self.transcriptionQualityIssue(result, durationMs: durationMs)
                if let qualityIssue {
                    Self.pipelineLogger.warning("[Dictation] candidate quality warning backend=\(descriptor.displayName, privacy: .public) issue=\(qualityIssue, privacy: .public)")
                }
                if Self.isCatastrophicTranscription(result) {
                    throw TranscriptionAttemptError.lowQuality("catastrophic_markup_corruption")
                }

                if descriptor.kind != self.asrBackend.descriptor.kind {
                    let primaryName = self.asrBackend.descriptor.displayName
                    Self.pipelineLogger.notice("[Dictation] fallback backend succeeded primary=\(primaryName, privacy: .public) used=\(descriptor.displayName, privacy: .public)")
                }
                Self.pipelineLogger.notice("[Dictation] backend result chars=\(result.count, privacy: .public)")
                if qualityIssue == nil {
                    lastTranscriptionBackendName = descriptor.displayName
                    Self.pipelineLogger.notice(
                        "[Dictation] accepting candidate immediately backend=\(descriptor.displayName, privacy: .public) reason=clean_result"
                    )
                    return result
                }
                successfulCandidates.append(
                    TranscriptionCandidate(
                        text: result,
                        backendDisplayName: descriptor.displayName,
                        qualityIssue: qualityIssue
                    )
                )
            } catch {
                lastFailure = error
                Self.pipelineLogger.error("[Dictation] decoding failed attempt=\(index + 1, privacy: .public) backend=\(descriptor.displayName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        if let selected = Self.rankTranscriptionCandidates(successfulCandidates) {
            lastTranscriptionBackendName = selected.backendDisplayName
            Self.pipelineLogger.notice(
                "[Dictation] selected candidate backend=\(selected.backendDisplayName, privacy: .public) score=\(Self.completenessScore(for: selected.text), privacy: .public) issue=\(selected.qualityIssue ?? "none", privacy: .public)"
            )
            return selected.text
        }

        let errorMessage = L10n.ui(
            for: AppState.shared.selectedLanguage.id,
            fr: "La transcription a échoué. Réessayez après rechargement du moteur.",
            en: "Transcription failed. Retry after reloading the backend.",
            es: "La transcripción falló. Vuelve a intentarlo tras recargar el backend.",
            zh: "转写失败。请重新加载后端后重试。",
            ja: "文字起こしに失敗しました。バックエンド再読み込み後に再試行してください。",
            ru: "Сбой транскрибации. Повторите после перезагрузки бэкенда."
        )
        await surfaceASRError(errorMessage, modally: surfaceErrorsModally)
        if let lastFailure {
            Self.pipelineLogger.error("[Dictation] all backend attempts failed; last error=\(lastFailure.localizedDescription, privacy: .public)")
        } else {
            Self.pipelineLogger.error("[Dictation] all backend attempts failed; no backend available")
        }
        return ""
    }

    @MainActor
    private func surfaceASRError(_ message: String, modally: Bool) {
        if modally {
            AppState.shared.error = message
        } else {
            AppState.shared.updateCurrentDictationSession(errorMessage: message)
        }
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
        let kind = asrBackend.descriptor.kind
        // Parakeet: native inference not yet implemented.
        // Prefer WhisperKit (high quality, long-form) if already loaded,
        // then Apple Speech Analyzer, then Parakeet itself as last resort.
        if kind == .parakeet {
            var candidates: [any ASRService] = []
            if WhisperKitBackend.shared.isLoaded {
                candidates.append(WhisperKitBackend.shared)
            }
            if AppleSpeechAnalyzerBackend.isRuntimeSupported {
                candidates.append(AppleSpeechAnalyzerBackend())
            }
            candidates.append(asrBackend)
            return candidates
        }
        // Whisper is primary — Apple Speech Analyzer is fallback only (it truncates at ~30s).
        guard kind == .whisperKit, AppleSpeechAnalyzerBackend.isRuntimeSupported else {
            return [asrBackend]
        }
        return [asrBackend, AppleSpeechAnalyzerBackend()]
    }

    private func transcribeWithTimeout(
        backend: any ASRService,
        audio: [Float],
        timeoutSeconds: Double
    ) async throws -> String {
        try await ASRTranscriptionRunner.transcribe(
            backend: backend,
            audio: audio,
            timeoutSeconds: timeoutSeconds
        ) {
            TranscriptionAttemptError.timedOut(seconds: timeoutSeconds)
        }
    }

    private func dynamicTranscriptionTimeout(
        for kind: ASRBackendKind,
        durationMs: Int
    ) -> Double {
        let audioSeconds = max(0.5, Double(durationMs) / 1_000.0)
        switch kind {
        case .whisperKit:
            // Whisper can be slower on long dictations; keep enough headroom to avoid truncation by timeout.
            return min(120.0, max(whisperBaseTranscriptionTimeoutSeconds, audioSeconds * 2.2 + 8.0))
        case .appleSpeechAnalyzer:
            return min(60.0, max(15.0, audioSeconds * 1.4 + 6.0))
        case .codexVoice:
            return min(180.0, max(30.0, audioSeconds * 1.6 + 15.0))
        case .parakeet:
            return min(90.0, max(15.0, audioSeconds * 1.8 + 6.0))
        }
    }

    private nonisolated static func transcriptionQualityIssue(_ text: String, durationMs: Int) -> String? {
        _ = durationMs
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty_result" }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace })

        let longTokenCount = words.filter { $0.count >= 48 }.count
        if longTokenCount >= 4 {
            return "too_many_long_tokens=\(longTokenCount)"
        }

        var frequencies: [Substring: Int] = [:]
        for token in words where token.count >= 4 {
            frequencies[token, default: 0] += 1
        }
        if let repeated = frequencies.first(where: { $0.value >= 14 }) {
            return "repeated_token=\(repeated.key)"
        }

        let lower = trimmed.lowercased()
        let suspiciousMarkers = ["<footer", "<header", "{%", "_increment", "_magic", "extends"]
        let markerHits = suspiciousMarkers.reduce(0) { partial, marker in
            partial + (lower.contains(marker) ? 1 : 0)
        }
        if markerHits >= 1 {
            return "suspicious_markup_markers=\(markerHits)"
        }

        return nil
    }

    private nonisolated static func isCatastrophicTranscription(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let catastrophicMarkers = ["<footer", "<header", "{%", "</", "_increment", "_magic", "extends"]
        let markerHits = catastrophicMarkers.reduce(0) { partial, marker in
            partial + (lowered.contains(marker) ? 1 : 0)
        }
        if markerHits >= 3 { return true }

        let words = lowered.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hugeTokens = words.filter { $0.count >= 72 }
        if hugeTokens.count >= 2 { return true }

        // Foreign script pollution: if >15% of characters are from scripts
        // that don't match the user's selected languages, the ASR hallucinated.
        let expectedScripts = Self.expectedScriptsForSelectedLanguages()
        var foreignCount = 0
        var totalLetters = 0
        for scalar in text.unicodeScalars {
            guard scalar.properties.isAlphabetic else { continue }
            totalLetters += 1
            if !Self.scalarBelongsToScripts(scalar, scripts: expectedScripts) {
                foreignCount += 1
            }
        }
        if totalLetters > 4, Double(foreignCount) / Double(totalLetters) > 0.15 {
            return true
        }

        // Degenerate repetition: same 2-6 char pattern repeated 4+ times
        if text.range(of: #"(.{2,6})\1{3,}"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    /// Returns the set of expected Unicode script tags for the user's selected languages.
    private nonisolated static func expectedScriptsForSelectedLanguages() -> Set<String> {
        let langs = MainActor.assumeIsolated { AppState.shared.selectedLanguages.map(\.id) }
        var scripts: Set<String> = ["latin"] // Latin is always expected (URLs, tech terms)
        for lang in langs {
            switch lang.lowercased().prefix(2) {
            case "fr", "en", "es", "de", "it", "pt", "nl", "ro", "sv", "da", "no", "pl", "cs", "fi":
                scripts.insert("latin")
            case "zh", "yue":
                scripts.formUnion(["cjk", "latin"])
            case "ja":
                scripts.formUnion(["cjk", "hiragana", "katakana", "latin"])
            case "ko":
                scripts.formUnion(["hangul", "latin"])
            case "ru", "uk", "bg":
                scripts.formUnion(["cyrillic", "latin"])
            case "ar", "he":
                scripts.formUnion(["arabic", "hebrew", "latin"])
            case "th":
                scripts.formUnion(["thai", "latin"])
            case "hi":
                scripts.formUnion(["devanagari", "latin"])
            default:
                scripts.insert("latin")
            }
        }
        return scripts
    }

    /// Checks whether a Unicode scalar belongs to any of the expected script categories.
    private nonisolated static func scalarBelongsToScripts(_ scalar: Unicode.Scalar, scripts: Set<String>) -> Bool {
        let v = scalar.value
        if v < 0x0080 { return scripts.contains("latin") }
        if (0x0080...0x024F).contains(v) || (0x1E00...0x1EFF).contains(v) { return scripts.contains("latin") }
        if (0x0400...0x052F).contains(v) { return scripts.contains("cyrillic") }
        if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) { return scripts.contains("arabic") }
        if (0x0590...0x05FF).contains(v) { return scripts.contains("hebrew") }
        if (0x0E00...0x0E7F).contains(v) { return scripts.contains("thai") }
        if (0x0900...0x097F).contains(v) { return scripts.contains("devanagari") }
        if (0x3040...0x309F).contains(v) { return scripts.contains("hiragana") }
        if (0x30A0...0x30FF).contains(v) { return scripts.contains("katakana") }
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v) { return scripts.contains("cjk") }
        if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) { return scripts.contains("hangul") }
        // Unknown script: allow (conservative)
        return true
    }

    nonisolated static func completenessScore(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Int.min }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let sentenceDelimiters = trimmed.filter { ".!?".contains($0) }.count
        let punctuationBonus = min(20, sentenceDelimiters * 2)
        return trimmed.count * 2 + words * 5 + punctuationBonus
    }

    nonisolated static func rankTranscriptionCandidates(
        _ candidates: [TranscriptionCandidate]
    ) -> TranscriptionCandidate? {
        candidates.max { lhs, rhs in
            let leftScore = completenessScore(for: lhs.text) - (lhs.qualityIssue == nil ? 0 : 120)
            let rightScore = completenessScore(for: rhs.text) - (rhs.qualityIssue == nil ? 0 : 120)
            if leftScore == rightScore {
                return lhs.text.count < rhs.text.count
            }
            return leftScore < rightScore
        }
    }

    // loadAudioSamples moved to AudioCaptureService.loadAudioFile(at:)

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

    /// Full post-processing pipeline (non-destructive):
    ///   filler removal → structural list annotation/rendering → style formatting.
    private func postProcess(_ text: String) -> PostProcessResult {
        guard !text.isEmpty else {
            return PostProcessResult(text: text, listBlocksCount: 0)
        }
        let languageCode = AppState.shared.selectedLanguage.id

        // ── Phase A: non-destructive cleanup ───────────────────────────────────
        var cleaned = text
        for regex in fillerRemovalRegexes(for: languageCode) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let smart = smartFormatter.run(cleaned, languageCode: languageCode)
        cleaned = smart.cleanedText
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Phase B: structural annotation → mixed text + inline lists ────────
        var result = Self.renderDetectedListBlocksInline(cleaned, blocks: smart.detectedListBlocks)

        // Keep contextual substitutions after list rendering (ranges are based on cleaned text).
        result = applyDictionaryPronunciationMappings(to: result)
        result = applyContextualLinkSnippets(to: result, bundleID: activeBundleIdentifier())

        // ── Phase C: tone formatting with list-line preservation ───────────────
        let tone = activeTone()
        result = applyToneFormattingPreservingLists(result, tone: tone, languageCode: languageCode)
        result = normalizeWhitespacePreservingParagraphs(in: result)

        return PostProcessResult(
            text: result,
            listBlocksCount: smart.detectedListBlocks.count
        )
    }

    nonisolated static func renderDetectedListBlocksInline(
        _ text: String,
        blocks: [SmartTextFormatter.DetectedListBlock]
    ) -> String {
        guard !blocks.isEmpty else { return text }
        var result = text
        let sorted = blocks.sorted { $0.sourceStart > $1.sourceStart }

        for block in sorted {
            let nsResult = result as NSString
            let location = block.sourceStart
            let length = block.sourceEnd - block.sourceStart
            guard location >= 0, length > 0, location + length <= nsResult.length else { continue }

            let replacementLines = block.items.compactMap { item -> String? in
                let normalized = item
                    .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return nil }
                return "- " + normalized
            }
            guard !replacementLines.isEmpty else { continue }

            var replacement = replacementLines.joined(separator: "\n")
            if location > 0 {
                let previousChar = nsResult.substring(with: NSRange(location: location - 1, length: 1))
                if previousChar != "\n" {
                    replacement = "\n" + replacement
                }
            }
            if location + length < nsResult.length {
                let nextChar = nsResult.substring(with: NSRange(location: location + length, length: 1))
                if nextChar != "\n" {
                    replacement += "\n"
                }
            }

            let range = NSRange(location: location, length: length)
            result = nsResult.replacingCharacters(in: range, with: replacement)
        }
        return result
    }

    private func applyToneFormattingPreservingLists(
        _ text: String,
        tone: WritingTone,
        languageCode: String
    ) -> String {
        guard !text.isEmpty else { return text }

        let lines = text.components(separatedBy: "\n")
        var chunks: [(isList: Bool, lines: [String])] = []
        chunks.reserveCapacity(max(1, lines.count / 2))

        for line in lines {
            let isList = isListLine(line)
            if var last = chunks.last, last.isList == isList {
                last.lines.append(line)
                chunks[chunks.count - 1] = last
            } else {
                chunks.append((isList: isList, lines: [line]))
            }
        }

        let transformed: [String] = chunks.map { chunk in
            if chunk.isList {
                return chunk.lines
                    .map(normalizeListLine)
                    .joined(separator: "\n")
            }
            let prose = chunk.lines.joined(separator: "\n")
            return applyToneFormattingToProse(prose, tone: tone, languageCode: languageCode)
        }

        return transformed.joined(separator: "\n")
    }

    private func applyToneFormattingToProse(
        _ text: String,
        tone: WritingTone,
        languageCode: String
    ) -> String {
        var result = text
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        switch tone {
        case .formal:
            result = applyFormalPunctuation(to: result, languageCode: languageCode)
            result = insertTransitionSentenceBoundaries(in: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .casual:
            result = applyLightPunctuation(to: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            // Keep casual tone but still split dense dictation into readable paragraphs.
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .veryCasual:
            result = result.lowercased()
            if result.hasSuffix(".") { result = String(result.dropLast()) }
            result = result.replacingOccurrences(of: "[!;:]", with: "", options: .regularExpression)
        }

        return result
    }

    private func isListLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
    }

    private func normalizeListLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let payload: String
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            payload = String(trimmed.dropFirst(2))
        } else {
            payload = trimmed
        }
        let normalized = payload
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        guard !normalized.isEmpty else { return "" }
        return "- " + normalized.prefix(1).uppercased() + normalized.dropFirst()
    }

    // MARK: - Internal Test Hooks

    func debugApplyToneForTesting(_ text: String, tone: WritingTone, languageCode: String) -> String {
        applyToneFormattingToProse(text, tone: tone, languageCode: languageCode)
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

        for rule in DictionaryStore.shared.pronunciationReplacementRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacementTemplate
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

    // MARK: - Legacy Text Injection

    // These helpers are no longer on the live runtime path.
    // InsertionEngine is the source of truth for runtime insertion behavior.

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
