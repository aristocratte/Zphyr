import Foundation

enum ASRBackendKind: String, CaseIterable, Codable, Sendable {
    case appleSpeechAnalyzer
    case codexVoice
    case whisperKit
    case parakeet
}

struct ASRBackendDescriptor: Sendable, Equatable {
    let kind: ASRBackendKind
    let displayName: String
    let requiresModelInstall: Bool
    let modelSizeLabel: String?
    let onboardingSubtitle: String
    let approxModelBytes: Int64?
}

enum ASRBackendCatalog {
    nonisolated static let installOrder: [ASRBackendKind] = [
        .appleSpeechAnalyzer,
        .codexVoice,
        .whisperKit,
        .parakeet,
    ]

    nonisolated static var allDescriptors: [ASRBackendDescriptor] {
        installOrder.map(descriptor)
    }

    nonisolated static var descriptorsByKind: [ASRBackendKind: ASRBackendDescriptor] {
        Dictionary(uniqueKeysWithValues: allDescriptors.map { ($0.kind, $0) })
    }

    nonisolated static func descriptor(for kind: ASRBackendKind) -> ASRBackendDescriptor {
        switch kind {
        case .appleSpeechAnalyzer:
            return ASRBackendDescriptor(
                kind: .appleSpeechAnalyzer,
                displayName: "Apple Speech Analyzer",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "Apple Speech Analyzer runs locally with no model download.",
                approxModelBytes: nil
            )
        case .codexVoice:
            return ASRBackendDescriptor(
                kind: .codexVoice,
                displayName: "Codex Voice",
                requiresModelInstall: false,
                modelSizeLabel: nil,
                onboardingSubtitle: "Codex Voice uses your Codex account for transcription. No local model download.",
                approxModelBytes: nil
            )
        case .whisperKit:
            return ASRBackendDescriptor(
                kind: .whisperKit,
                displayName: "Whisper Large v3 Turbo",
                requiresModelInstall: true,
                modelSizeLabel: "~600 MB",
                onboardingSubtitle: "Whisper s'installe une seule fois (~600 Mo). Il s'exécute ensuite 100% en local.",
                approxModelBytes: 600 * 1_024 * 1_024
            )
        case .parakeet:
            return ASRBackendDescriptor(
                kind: .parakeet,
                displayName: "Parakeet v3 0.6B",
                requiresModelInstall: true,
                modelSizeLabel: "~640 MB",
                onboardingSubtitle: "Parakeet v3 s'installe une seule fois (~640 Mo). 25 langues, 100% local via MLX.",
                approxModelBytes: 640 * 1_024 * 1_024
            )
        }
    }

    @MainActor
    static func installURL(for kind: ASRBackendKind) -> URL? {
        switch kind {
        case .appleSpeechAnalyzer, .codexVoice:
            return nil
        case .whisperKit:
            return WhisperKitBackend.resolveInstallURL()
        case .parakeet:
            return ParakeetBackend.resolveInstallURL()
        }
    }

    @MainActor
    static func isInstalled(_ kind: ASRBackendKind) -> Bool {
        let descriptor = descriptor(for: kind)
        guard descriptor.requiresModelInstall else {
            switch kind {
            case .appleSpeechAnalyzer:
                return AppleSpeechAnalyzerBackend.isRuntimeSupported
            case .codexVoice:
                return CodexVoiceBackend.hasReadableCredentials()
            case .whisperKit, .parakeet:
                return true
            }
        }
        return installURL(for: kind) != nil
    }
}

/// Optional lifecycle hooks used by onboarding/settings for installable backends.
protocol ASRBackendLifecycle: AnyObject {
    var descriptor: ASRBackendDescriptor { get }

    var isLoaded: Bool { get }
    var isInstalling: Bool { get }
    var downloadProgress: Double { get }
    var installError: String? { get }
    var installPath: String? { get }
    var isPaused: Bool { get }

    func loadIfInstalled() async
    func installModel() async
    func cancelInstall()
    func pauseInstall()
    func resumeInstall()
    func uninstallModel()
}

extension ASRBackendLifecycle {
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
}

struct PreflightModelInstallPlan: Equatable, Sendable {
    let activeASRBackend: ASRBackendKind
    let asrBackendsToInstall: [ASRBackendKind]
    let formattingModelsToInstall: [FormattingModelID]

    var hasDownloads: Bool {
        !asrBackendsToInstall.isEmpty || !formattingModelsToInstall.isEmpty
    }

    init(
        preferredASRBackend: ASRBackendKind,
        selectedASRBackends: Set<ASRBackendKind>,
        selectedFormattingModels: Set<FormattingModelID>,
        availableASRDescriptors: [ASRBackendKind: ASRBackendDescriptor],
        availableFormattingModels: [FormattingModelID]
    ) {
        let asrOrder = ASRBackendCatalog.installOrder
        let selectedASRInOrder = asrOrder.filter { selectedASRBackends.contains($0) }

        if selectedASRBackends.isEmpty || selectedASRBackends.contains(preferredASRBackend) {
            activeASRBackend = preferredASRBackend
        } else {
            activeASRBackend = selectedASRInOrder.first ?? preferredASRBackend
        }

        asrBackendsToInstall = selectedASRInOrder.filter { kind in
            availableASRDescriptors[kind]?.requiresModelInstall == true
        }

        formattingModelsToInstall = availableFormattingModels.filter {
            selectedFormattingModels.contains($0)
        }
    }
}
