//
//  ZphyrTests.swift
//  ZphyrTests
//
//  Created by Aristide Cordonnier on 01/03/2026.
//

import Testing
import Foundation
import AppKit
@testable import Zphyr

struct ZphyrTests {
    private final class HangingTimeoutBackend: ASRService {
        let descriptor = ASRBackendDescriptor(
            kind: .parakeet,
            displayName: "Hanging test backend",
            requiresModelInstall: false,
            modelSizeLabel: nil,
            onboardingSubtitle: "",
            approxModelBytes: nil
        )

        var cancelCallCount = 0
        private var continuation: CheckedContinuation<String, Error>?

        var isLoaded: Bool { true }
        var isInstalling: Bool { false }
        var downloadProgress: Double { 1.0 }
        var installError: String? { nil }
        var installPath: String? { nil }
        var isPaused: Bool { false }

        func loadIfInstalled() async {}
        func installModel() async {}
        func cancelInstall() {}
        func pauseInstall() {}
        func resumeInstall() {}
        func uninstallModel() {}

        func transcribe(audioBuffer: [Float]) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func cancelActiveTranscription() async {
            cancelCallCount += 1
            continuation?.resume(throwing: ASRBackendError.transcriptionFailed("forced_stop"))
            continuation = nil
        }
    }

    @Test func supportedUILanguageFallbackToEnglish() {
        let language = SupportedUILanguage.fromWhisperCode("de")
        #expect(language == .en)
    }

    @MainActor
    @Test func transcriptionRunnerTimesOutWithoutBlockingOnHungBackend() async {
        let backend = HangingTimeoutBackend()
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            _ = try await ASRTranscriptionRunner.transcribe(
                backend: backend,
                audio: [0.1, 0.2, 0.3],
                timeoutSeconds: 1.0
            ) {
                ASRBackendError.transcriptionFailed("timeout")
            }
            Issue.record("Expected timeout to throw")
        } catch {
            #expect(error.localizedDescription == "timeout")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        #expect(backend.cancelCallCount == 1)
        #expect(elapsed < 2.5)
    }

    @Test func triggerKeyCodesAreUnique() {
        let codes = TriggerKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func modifierKeyCodeMappingRecognizesLeftAndRightOption() {
        #expect(ShortcutManager.modifierFlagForKeyCode(58) == .option)
        #expect(ShortcutManager.modifierFlagForKeyCode(61) == .option)
        #expect(ShortcutManager.modifierDisplayTextForKeyCode(58) == "⌥ Left Option")
        #expect(ShortcutManager.modifierDisplayTextForKeyCode(61) == "⌥ Right Option")
    }

    @Test func modifierOnlyShortcutDetectionMatchesRecordedModifier() {
        let leftOptionOnly = RecordedShortcut(
            keyCode: 58,
            modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
            displayText: "⌥ Left Option"
        )
        #expect(ShortcutManager.isModifierOnlyShortcut(leftOptionOnly))

        let leftCommandOnly = RecordedShortcut(
            keyCode: 55,
            modifierRawValue: NSEvent.ModifierFlags.command.rawValue,
            displayText: "⌘ Left Command"
        )
        #expect(ShortcutManager.isModifierOnlyShortcut(leftCommandOnly))

        let optionPlusLetter = RecordedShortcut(
            keyCode: 0,
            modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
            displayText: "⌥A"
        )
        #expect(!ShortcutManager.isModifierOnlyShortcut(optionPlusLetter))
    }

    @Test func updateCheckerVersionComparisonHandlesPrereleases() {
        #expect(UpdateChecker._test_isNewerVersion("1.0.2-beta", than: "1.0.1"))
        #expect(!UpdateChecker._test_isNewerVersion("1.0.1-beta", than: "1.0.1"))
        #expect(UpdateChecker._test_isNewerVersion("v1.0.2", than: "1.0.1"))
    }

    @Test func updateCheckerStableChannelPrefersLatestNonPrerelease() {
        let releases = [
            GitHubRelease(
                tagName: "v1.1.0-beta",
                draft: false,
                prerelease: true,
                publishedAt: "2026-03-16T10:00:00Z",
                assets: []
            ),
            GitHubRelease(
                tagName: "v1.0.5",
                draft: false,
                prerelease: false,
                publishedAt: "2026-03-15T10:00:00Z",
                assets: []
            )
        ]

        #expect(UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: false) == "v1.0.5")
        #expect(UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: true) == "v1.1.0-beta")
    }

    @Test func updateCheckerAssetSelectionPrefersArchitectureCompatibleDmg() {
        let assets = [
            GitHubAsset(
                name: "Zphyr-debug.dmg",
                browserDownloadURL: "https://example.com/debug.dmg",
                downloadCount: 1,
                digest: nil
            ),
            GitHubAsset(
                name: "Zphyr-arm64.dmg",
                browserDownloadURL: "https://example.com/arm64.dmg",
                downloadCount: 10,
                digest: nil
            ),
            GitHubAsset(
                name: "Zphyr-universal.dmg",
                browserDownloadURL: "https://example.com/universal.dmg",
                downloadCount: 20,
                digest: nil
            )
        ]

        #expect(UpdateChecker._test_preferredDMGAssetName(from: assets, architectureHint: "arm64") == "Zphyr-arm64.dmg")
        #expect(UpdateChecker._test_preferredDMGAssetName(from: assets, architectureHint: "x86_64") == "Zphyr-universal.dmg")
    }

    @Test func secureStoreMigratesPlaintextToEncrypted() {
        let suiteName = "zphyr.tests.\(UUID().uuidString)"
        let storageKey = "sample.key"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let payload = Data("hello zphyr".utf8)
        defaults.set(payload, forKey: storageKey)
        SecureLocalDataStore.setEncryptionEnabled(true, defaults: defaults)

        let loaded = SecureLocalDataStore.load(forKey: storageKey, defaults: defaults)
        #expect(loaded == payload)
        #expect(defaults.data(forKey: storageKey) == nil)
        #expect(defaults.data(forKey: "\(storageKey).enc") != nil)
    }

    @Test func dictionaryLearningDetectsSingleWordReplacement() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Le modèle quen est rapide.",
            to: "Le modèle qwen est rapide."
        )
        #expect(suggestion?.mistakenWord == "quen")
        #expect(suggestion?.correctedWord == "qwen")
    }

    @Test func dictionaryLearningDetectsInWordCharacterCorrection() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Version en cours: qun3.",
            to: "Version en cours: qwen3."
        )
        #expect(suggestion?.mistakenWord == "qun3")
        #expect(suggestion?.correctedWord == "qwen3")
    }

    @Test func dictionaryLearningRejectsMultiWordEdits() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Bonjour monde",
            to: "Bonjour beau monde"
        )
        #expect(suggestion == nil)
    }

    @Test func dictionaryLearningTokenBoundaryMatch() {
        #expect(DictationEngine._test_containsLearningToken("quen", in: "Le mot quen a été dicté."))
        #expect(!DictationEngine._test_containsLearningToken("quen", in: "Le mot quentin a été dicté."))
    }

    @Test func insertionStrategyPrefersTypingForShortSingleLineText() {
        let strategy = InsertionEngine.recommendedStrategy(for: "short note")
        #expect(strategy == .typingEvents)
    }

    @Test func insertionStrategyPrefersPasteForLongText() {
        let strategy = InsertionEngine.recommendedStrategy(
            for: "This is a much longer dictated message that should be pasted rather than typed character by character into the target application."
        )
        #expect(strategy == .pasteWithClipboardRestore)
    }

    @Test func insertionStrategyPrefersPasteForMultilineText() {
        let strategy = InsertionEngine.recommendedStrategy(for: "line one\nline two")
        #expect(strategy == .pasteWithClipboardRestore)
    }

    @Test func insertionStrategyPrefersPasteForBrowserApps() {
        let strategy = InsertionEngine.recommendedStrategy(
            for: "short note",
            bundleID: "com.google.Chrome"
        )
        #expect(strategy == .pasteWithClipboardRestore)
    }

    @Test func formattingModelCatalogContainsQwenOnly() {
        let ids = FormattingModelCatalog.all.map(\.id)
        #expect(ids == [.qwen3_4b])
        #expect(FormattingModelCatalog.descriptor(for: .qwen3_4b).huggingFaceModelID.contains("Qwen3.5-4B-MLX-4bit"))
    }

    @Test func preflightInstallPlanDoesNotDownloadWhenSelectionIsEmpty() {
        let descriptors: [ASRBackendKind: ASRBackendDescriptor] = [
            .appleSpeechAnalyzer: ASRBackendDescriptor(
                kind: .appleSpeechAnalyzer,
                displayName: "Apple",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "",
                approxModelBytes: nil
            ),
            .whisperKit: ASRBackendDescriptor(
                kind: .whisperKit,
                displayName: "Whisper",
                requiresModelInstall: true,
                modelSizeLabel: "~600 MB",
                onboardingSubtitle: "",
                approxModelBytes: 600
            ),
        ]

        let plan = PreflightModelInstallPlan(
            preferredASRBackend: .appleSpeechAnalyzer,
            selectedASRBackends: [],
            selectedFormattingModels: [],
            availableASRDescriptors: descriptors,
            availableFormattingModels: [.qwen3_4b]
        )

        #expect(plan.asrBackendsToInstall.isEmpty)
        #expect(plan.formattingModelsToInstall.isEmpty)
        #expect(!plan.hasDownloads)
        #expect(plan.activeASRBackend == .appleSpeechAnalyzer)
    }

    @Test func preflightInstallPlanOnlyInstallsExplicitlySelectedInstallableModels() {
        let descriptors: [ASRBackendKind: ASRBackendDescriptor] = [
            .appleSpeechAnalyzer: ASRBackendDescriptor(
                kind: .appleSpeechAnalyzer,
                displayName: "Apple",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "",
                approxModelBytes: nil
            ),
            .whisperKit: ASRBackendDescriptor(
                kind: .whisperKit,
                displayName: "Whisper",
                requiresModelInstall: true,
                modelSizeLabel: "~600 MB",
                onboardingSubtitle: "",
                approxModelBytes: 600
            ),
            .parakeet: ASRBackendDescriptor(
                kind: .parakeet,
                displayName: "Parakeet",
                requiresModelInstall: true,
                modelSizeLabel: "~640 MB",
                onboardingSubtitle: "",
                approxModelBytes: 640
            ),
        ]

        let plan = PreflightModelInstallPlan(
            preferredASRBackend: .whisperKit,
            selectedASRBackends: [.appleSpeechAnalyzer, .whisperKit],
            selectedFormattingModels: [.qwen3_4b],
            availableASRDescriptors: descriptors,
            availableFormattingModels: [.qwen3_4b]
        )

        #expect(plan.asrBackendsToInstall == [.whisperKit])
        #expect(plan.formattingModelsToInstall == [.qwen3_4b])
        #expect(plan.hasDownloads)
        #expect(plan.activeASRBackend == .whisperKit)
    }

    @Test func preflightInstallPlanKeepsCodexVoiceAsNoDownloadProvider() {
        let descriptors: [ASRBackendKind: ASRBackendDescriptor] = [
            .appleSpeechAnalyzer: ASRBackendDescriptor(
                kind: .appleSpeechAnalyzer,
                displayName: "Apple",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "",
                approxModelBytes: nil
            ),
            .codexVoice: ASRBackendDescriptor(
                kind: .codexVoice,
                displayName: "Codex",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "",
                approxModelBytes: nil
            ),
            .whisperKit: ASRBackendDescriptor(
                kind: .whisperKit,
                displayName: "Whisper",
                requiresModelInstall: true,
                modelSizeLabel: "~600 MB",
                onboardingSubtitle: "",
                approxModelBytes: 600
            ),
        ]

        let plan = PreflightModelInstallPlan(
            preferredASRBackend: .codexVoice,
            selectedASRBackends: [.codexVoice],
            selectedFormattingModels: [],
            availableASRDescriptors: descriptors,
            availableFormattingModels: [.qwen3_4b]
        )

        #expect(plan.activeASRBackend == .codexVoice)
        #expect(plan.asrBackendsToInstall.isEmpty)
        #expect(!plan.hasDownloads)
    }

    @MainActor
    @Test func performanceRouterDoesNotForceCodexVoiceOutOfEcoProfile() {
        let profile = PerformanceProfile(tier: .eco, physicalMemoryBytes: 8 * 1_073_741_824)

        #expect(PerformanceRouter.shared.effectiveASRBackend(preferred: .codexVoice, profile: profile) == .codexVoice)
        #expect(PerformanceRouter.shared.effectiveASRBackend(preferred: .whisperKit, profile: profile) == .appleSpeechAnalyzer)
    }

    @MainActor
    @Test func activeFormattingModelPersistsAndReflectsInstallState() throws {
        let appState = AppState.shared
        let previousModel = appState.activeFormattingModel
        let previousInstalled = appState.advancedModeInstalled
        let previousOverrides = AdvancedLLMFormatter.overrideInstallURLs

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zphyr-formatter-installed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("model.safetensors").path, contents: Data("weights".utf8))

        defer {
            appState.activeFormattingModel = previousModel
            appState.advancedModeInstalled = previousInstalled
            AdvancedLLMFormatter.overrideInstallURLs = previousOverrides
            try? FileManager.default.removeItem(at: tempDir)
        }

        AdvancedLLMFormatter.overrideInstallURLs[.qwen3_4b] = tempDir
        appState.activeFormattingModel = .qwen3_4b

        #expect(appState.activeFormattingModel == .qwen3_4b)
        #expect(UserDefaults.standard.string(forKey: "zphyr.formatter.activeModel") == FormattingModelID.qwen3_4b.rawValue)
        #expect(appState.advancedModeInstalled)
        #expect(AdvancedLLMFormatter.shared.installStatus(for: .qwen3_4b).isInstalled)
    }

    @MainActor
    @Test func contextualRewriteFallsBackWhenSelectedFormattingModelIsUnavailable() async {
        let previousOverrides = AdvancedLLMFormatter.overrideInstallURLs
        let formatter = AdvancedLLMFormatter.shared
        formatter.unload()
        defer {
            AdvancedLLMFormatter.overrideInstallURLs = previousOverrides
            formatter.unload()
        }

        let emptyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zphyr-formatter-empty-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        AdvancedLLMFormatter.overrideInstallURLs[.qwen3_4b] = emptyDir

        let stage = ContextualRewriteStage()
        let io = StageIO(
            text: "please keep this sentence intact",
            extractedCommand: .none,
            metadata: PipelineMetadata(
                languageCode: "en",
                targetBundleID: nil,
                tone: .casual,
                outputProfile: .clean,
                formattingModelID: .qwen3_4b,
                protectedTerms: [],
                defaultCodeStyle: .camel,
                formattingMode: .advanced,
                isProModeUnlocked: true,
                isLLMLoaded: false
            )
        )

        let result = await stage.process(io)

        #expect(result.text == "please keep this sentence intact")
        #expect(result.pipelineDecision == .deterministicFallback)
        #expect(result.fallbackReason == .selectedFormattingModelUnavailable)

        try? FileManager.default.removeItem(at: emptyDir)
    }

    @MainActor
    @Test func debugExportWritesJsonAndSummary() throws {
        let appState = AppState.shared
        let previousSession = appState.lastCompletedDictationSession
        let previousCurrent = appState.currentDictationSession
        let recorder = LocalMetricsRecorder.shared
        let previousMetrics = recorder.lastSession
        let previousHistory = recorder.sessionHistory

        defer {
            appState.currentDictationSession = previousCurrent
            appState.lastCompletedDictationSession = previousSession
            recorder.clearHistory()
            if let previousMetrics {
                recorder.record(previousMetrics)
            }
            for metric in previousHistory where metric.sessionID != previousMetrics?.sessionID {
                recorder.record(metric)
            }
        }

        let sessionID = UUID()
        appState.lastCompletedDictationSession = DictationSession(
            id: sessionID,
            startedAt: Date(),
            updatedAt: Date(),
            endedAt: Date(),
            targetBundleID: "com.apple.TextEdit",
            phase: .success,
            outputProfile: .technical,
            liveTranscription: LiveTranscriptionState(
                mode: .finalOnly,
                partialText: nil,
                finalText: "raw transcript",
                lastPartialAt: nil,
                lastFinalAt: Date()
            ),
            pipelineDecision: .deterministicFallback,
            pipelineFallbackReason: .profileProtectedTermsRejected,
            pipelineTrace: [
                StageTrace.record(name: "FormattingNormalization", index: 0, input: "a", output: "b", durationMs: 1.2)
            ],
            insertionStrategy: .pasteWithClipboardRestore,
            insertionFallbackReason: nil,
            finalTextPreview: "Formatted output",
            finalFormattedText: "Formatted output",
            errorMessage: nil,
            transitions: [DictationSessionTransition(phase: .success)]
        )
        recorder.clearHistory()
        recorder.record(
            DictationSessionMetrics(
                sessionID: sessionID,
                capturedSampleCount: 100,
                asrDurationMs: 10,
                transcriptionMode: .finalOnly,
                partialUpdatesCount: 0,
                retriedFromBuffer: false,
                vadTrimmedLeadingMs: 0,
                vadTrimmedTrailingMs: 0,
                stabilizeDurationMs: 11,
                formatterDurationMs: 12,
                insertionDurationMs: 13,
                rawCharacterCount: 14,
                finalCharacterCount: 15,
                backendName: "TestASR",
                formatterMode: "advanced",
                outputProfile: "technical",
                pipelineDecision: .deterministicFallback,
                pipelineFallbackReason: .profileProtectedTermsRejected,
                usedFormatterFallback: true,
                listBlocksDetected: 0,
                insertionTargetFamily: "editorOrCode",
                insertionStrategy: "pasteWithClipboardRestore",
                insertionFallbackReason: nil
            )
        )

        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zphyr-debug-test-\(sessionID.uuidString)")
        let exportURL = try SessionDebugExporter.shared.exportLatestSession(to: baseURL)
        let jsonURL = exportURL.appendingPathComponent("session.json")
        let summaryURL = exportURL.appendingPathComponent("summary.md")

        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(FileManager.default.fileExists(atPath: summaryURL.path))
    }

}
