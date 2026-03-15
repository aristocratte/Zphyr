import Foundation

enum ASRBackendKind: String, CaseIterable, Codable, Sendable {
    case appleSpeechAnalyzer
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
