import Foundation

enum PerformanceTier: String, CaseIterable, Codable, Sendable {
    case eco
    case balanced
    case pro

    var displayName: String {
        switch self {
        case .eco: return "Eco"
        case .balanced: return "Balanced"
        case .pro: return "Pro"
        }
    }
}

struct PerformanceProfile: Sendable, Equatable {
    let tier: PerformanceTier
    let physicalMemoryBytes: UInt64

    var physicalMemoryGB: Int {
        Int(physicalMemoryBytes / 1_073_741_824)
    }

    var allowsProMode: Bool {
        tier == .pro
    }

    var allowsQwenASR: Bool {
        tier != .eco
    }

    var forcedASRBackendInTier: ASRBackendKind? {
        tier == .eco ? .appleSpeechAnalyzer : nil
    }

    var fallbackASRBackend: ASRBackendKind {
        .appleSpeechAnalyzer
    }

    func displayLabel(for languageCode: String) -> String {
        switch tier {
        case .eco:
            return L10n.ui(
                for: languageCode,
                fr: "Mode Éco (<= 8 Go)",
                en: "Eco mode (<= 8 GB)",
                es: "Modo Eco (<= 8 GB)",
                zh: "节能模式（<= 8 GB）",
                ja: "エコモード（<= 8GB）",
                ru: "Эко-режим (<= 8 ГБ)"
            )
        case .balanced:
            return L10n.ui(
                for: languageCode,
                fr: "Mode Standard (8–15 Go)",
                en: "Standard mode (8–15 GB)",
                es: "Modo Estándar (8–15 GB)",
                zh: "标准模式（8–15 GB）",
                ja: "標準モード（8〜15GB）",
                ru: "Стандартный режим (8–15 ГБ)"
            )
        case .pro:
            return L10n.ui(
                for: languageCode,
                fr: "Mode Pro (>= 16 Go)",
                en: "Pro mode (>= 16 GB)",
                es: "Modo Pro (>= 16 GB)",
                zh: "专业模式（>= 16 GB）",
                ja: "プロモード（>= 16GB）",
                ru: "Про-режим (>= 16 ГБ)"
            )
        }
    }
}

@MainActor
final class PerformanceRouter {
    static let shared = PerformanceRouter()

    private init() {}

    func currentProfile() -> PerformanceProfile {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let tier: PerformanceTier
        if physicalMemory <= 8 * 1_073_741_824 {
            tier = .eco
        } else if physicalMemory >= 16 * 1_073_741_824 {
            tier = .pro
        } else {
            tier = .balanced
        }
        return PerformanceProfile(tier: tier, physicalMemoryBytes: physicalMemory)
    }

    func effectiveASRBackend(preferred: ASRBackendKind, profile: PerformanceProfile? = nil) -> ASRBackendKind {
        let profile = profile ?? currentProfile()
        if let forced = profile.forcedASRBackendInTier {
            return forced
        }
        if !profile.allowsQwenASR, preferred == .qwenMLX {
            return profile.fallbackASRBackend
        }
        return preferred
    }

    func effectiveFormattingMode(preferred: FormattingMode, profile: PerformanceProfile? = nil) -> FormattingMode {
        let profile = profile ?? currentProfile()
        guard profile.allowsProMode else { return .trigger }
        return preferred
    }
}
