//
//  ModelManager.swift
//  Zphyr
//
//  Manages the lifecycle of ASR and formatter models: selection, download, install, unload.
//

import Foundation
import os

@MainActor
final class ModelManager {
    private let log = Logger(subsystem: "com.zphyr.app", category: "ModelManager")

    /// Current active backend (observable for UI).
    private(set) var currentBackend: (any ASRService)?

    private var modelLoadTask: Task<Void, Never>?

    // MARK: - Backend Selection

    func selectBackend(_ kind: ASRBackendKind) {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        currentBackend?.cancelInstall()

        let state = AppState.shared
        state.refreshPerformanceProfile()
        let effectivePreferred = PerformanceRouter.shared.effectiveASRBackend(
            preferred: kind,
            profile: state.performanceProfile
        )

        let backend = ASRBackendFactory.make(preferred: effectivePreferred)
        currentBackend = backend
        state.preferredASRBackend = effectivePreferred
        state.activeASRBackend = backend.descriptor.kind
        state.isDownloadPaused = false
        state.downloadStats = DownloadStats()
        state.modelInstallPath = backend.installPath
        if backend.descriptor.requiresModelInstall {
            state.modelStatus = backend.isLoaded ? .ready : .notDownloaded
        } else {
            state.modelStatus = .ready
        }
    }

    func refreshSelection() {
        AppState.shared.refreshPerformanceProfile()
        selectBackend(AppState.shared.preferredASRBackend)
    }

    // MARK: - Model Loading

    func loadModel() async {
        if let inFlight = modelLoadTask {
            if inFlight.isCancelled {
                modelLoadTask = nil
            } else {
                log.notice("[ModelManager] load already in progress; awaiting existing task")
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
        currentBackend?.cancelInstall()
        AppState.shared.isDownloadPaused = false
        if currentBackend?.descriptor.requiresModelInstall == true {
            AppState.shared.modelStatus = .notDownloaded
        } else {
            AppState.shared.modelStatus = .ready
        }
    }

    func pauseModelDownload() {
        guard case .downloading = AppState.shared.modelStatus else { return }
        AppState.shared.isDownloadPaused = true
        currentBackend?.pauseInstall()
        AppState.shared.downloadStats.speedBytesPerSec = 0
    }

    func resumeModelDownload() {
        AppState.shared.isDownloadPaused = false
        currentBackend?.resumeInstall()
    }

    func uninstallModel() {
        cancelModelDownload()
        currentBackend?.uninstallModel()
        AppState.shared.modelInstallPath = currentBackend?.installPath
        if currentBackend?.descriptor.requiresModelInstall == true {
            AppState.shared.modelStatus = .notDownloaded
        } else {
            AppState.shared.modelStatus = .ready
        }
    }

    func reinstallModel() async {
        uninstallModel()
        await loadModel()
    }

    // MARK: - Internal

    private func performModelLoad() async {
        let state = AppState.shared
        state.refreshPerformanceProfile()
        guard !Task.isCancelled else { return }
        let effectivePreferred = PerformanceRouter.shared.effectiveASRBackend(
            preferred: state.preferredASRBackend,
            profile: state.performanceProfile
        )
        if effectivePreferred != currentBackend?.descriptor.kind {
            selectBackend(effectivePreferred)
        }

        guard let backend = currentBackend else {
            log.error("[ModelManager] no backend selected")
            return
        }

        if state.modelStatus.isReady, backend.isLoaded {
            return
        }

        let descriptor = backend.descriptor
        state.activeASRBackend = descriptor.kind

        if !descriptor.requiresModelInstall {
            state.modelStatus = .loading
            await backend.loadIfInstalled()
            state.modelInstallPath = backend.installPath
            state.downloadStats = DownloadStats()
            state.modelStatus = .ready
            log.notice("[ModelManager] backend ready without install: \(descriptor.displayName, privacy: .public)")
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
            log.notice("[ModelManager] preparing backend \(descriptor.displayName, privacy: .public)")

            await backend.loadIfInstalled()
            if backend.isLoaded {
                state.modelInstallPath = backend.installPath
                state.downloadStats.bytesReceived = totalBytes
                state.modelStatus = .ready
                log.notice("[ModelManager] backend already installed and loaded")
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
            log.notice("[ModelManager] backend ready in \(elapsed, privacy: .public)s")
        } catch {
            if Task.isCancelled || error is CancellationError {
                log.notice("[ModelManager] cancelled")
                state.modelStatus = descriptor.requiresModelInstall ? .notDownloaded : .ready
            } else {
                log.error("[ModelManager] failed: \(error.localizedDescription, privacy: .public)")
                state.modelStatus = .failed(error.localizedDescription)
            }
        }
    }
}
