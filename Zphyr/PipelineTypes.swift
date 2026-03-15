//
//  PipelineTypes.swift
//  Zphyr
//
//  Core types for the layered post-ASR formatting pipeline.
//  All types are Sendable; StageTrace is Codable for evaluation export.
//

import Foundation

// MARK: - Runtime Decisions

enum PipelineDecision: String, Sendable, Codable {
    case commandShortCircuit
    case deterministicOnly
    case acceptedBaselineRound2
    case deterministicFallback
}

enum FallbackReason: String, Sendable, Codable {
    case abortCommandDetected
    case rewriteSkippedEmptyInput
    case rewriteSkippedMode
    case rewriteSkippedProLocked
    case rewriteModelUnavailable
    case selectedFormattingModelUnavailable
    case profileRewriteDisabledVerbatim
    case profileProtectedTermsRejected
    case profileValidationRejected
    case rewriteSanitizedInputEmpty
    case rewriteModelReturnedNil
    case rewriteIntroducedTokens
    case rewriteDroppedContent
    case rewriteLengthRatioExceeded
    case insertionAccessibilityUnavailable
    case insertionTargetNotFrontmost
}

// MARK: - Product Profiles

enum OutputProfile: String, CaseIterable, Identifiable, Sendable, Codable {
    case verbatim
    case clean
    case technical
    case email

    var id: String { rawValue }

    func displayName(for languageCode: String) -> String {
        switch self {
        case .verbatim:
            return L10n.ui(for: languageCode, fr: "Verbatim", en: "Verbatim", es: "Verbatim", zh: "原样", ja: "逐語", ru: "Дословно")
        case .clean:
            return L10n.ui(for: languageCode, fr: "Clean", en: "Clean", es: "Clean", zh: "清晰", ja: "クリーン", ru: "Чистый")
        case .technical:
            return L10n.ui(for: languageCode, fr: "Technique", en: "Technical", es: "Técnico", zh: "技术", ja: "技術", ru: "Технический")
        case .email:
            return L10n.ui(for: languageCode, fr: "Email", en: "Email", es: "Correo", zh: "邮件", ja: "メール", ru: "Почта")
        }
    }

    func subtitle(for languageCode: String) -> String {
        switch self {
        case .verbatim:
            return L10n.ui(for: languageCode, fr: "Correction minimale, conservation maximale.", en: "Minimal correction, maximum preservation.", es: "Corrección mínima, máxima preservación.", zh: "最少修正，最大保留。", ja: "最小限の補正で最大限保持。", ru: "Минимальная правка, максимальное сохранение.")
        case .clean:
            return L10n.ui(for: languageCode, fr: "Nettoyage léger et ponctuation utile.", en: "Light cleanup and useful punctuation.", es: "Limpieza ligera y puntuación útil.", zh: "轻度清理和实用标点。", ja: "軽い整形と適度な句読点。", ru: "Легкая очистка и полезная пунктуация.")
        case .technical:
            return L10n.ui(for: languageCode, fr: "Préservation stricte des tokens techniques.", en: "Strict preservation of technical tokens.", es: "Preservación estricta de tokens técnicos.", zh: "严格保留技术标记。", ja: "技術トークンを厳密に保持。", ru: "Строгое сохранение технических токенов.")
        case .email:
            return L10n.ui(for: languageCode, fr: "Formulation propre et sobre pour messages pro.", en: "Clean, restrained phrasing for email.", es: "Redacción limpia y sobria para correo.", zh: "适合邮件的整洁克制表达。", ja: "メール向けの整った自然な文面。", ru: "Аккуратная и сдержанная формулировка для писем.")
        }
    }
}

// MARK: - Formatting Model Catalog

/// Active formatting models exposed to the product.
/// Deprecated models (legacyZphyrV1, smolLM3_3b, gemma3_4b) have been removed.
/// Stored UserDefaults values that don’t match a valid case fall back to .qwen3_4b automatically.
enum FormattingModelID: String, CaseIterable, Identifiable, Sendable, Codable {
    case qwen3_4b = "qwen3_4b"

    var id: String { rawValue }

    func displayName(for languageCode: String) -> String {
        switch self {
        case .qwen3_4b:
            return L10n.ui(for: languageCode, fr: "Qwen3.5-4B", en: "Qwen3.5-4B", es: "Qwen3.5-4B", zh: "Qwen3.5-4B", ja: "Qwen3.5-4B", ru: "Qwen3.5-4B")
        }
    }

    func shortDescription(for languageCode: String) -> String {
        switch self {
        case .qwen3_4b:
            return L10n.ui(for: languageCode, fr: "Qwen3.5 local, très bon FR/EN et code technique.", en: "Local Qwen3.5, strong FR/EN and technical formatting.", es: "Qwen3.5 local, sólido en FR/EN y texto técnico.", zh: "本地 Qwen3.5，适合法英混合和技术文本。", ja: "ローカル Qwen3.5。FR/EN と技術文に強い。", ru: "Локальная Qwen3.5, сильная в FR/EN и техничном тексте.")
        }
    }

    func recommendedUsage(for languageCode: String) -> String {
        switch self {
        case .qwen3_4b:
            return L10n.ui(for: languageCode, fr: "Recommandé pour code, notes techniques et dictée FR/EN mixte.", en: "Recommended for code, technical notes, and FR/EN mixed dictation.", es: "Recomendado para código, notas técnicas y mezcla FR/EN.", zh: "推荐用于代码、技术笔记和法英混合口述。", ja: "コードや技術メモ、FR/EN 混在の音声入力向け。", ru: "Рекомендуется для кода, техничных заметок и смешанной FR/EN-диктовки.")
        }
    }

    var approxDiskBytes: Int64 {
        FormattingModelCatalog.descriptor(for: self).approximateBytes
    }
}

enum FormattingModelBackendKind: String, Sendable, Codable {
    case mlx
}

struct FormattingModelDescriptor: Identifiable, Equatable, Sendable, Codable {
    let id: FormattingModelID
    let backendKind: FormattingModelBackendKind
    let huggingFaceModelID: String
    let cacheNamespace: String
    let cacheSlug: String
    let cacheMatchHints: [String]
    let approximateBytes: Int64
    let prefersRawAlpacaPrompt: Bool
    let extraEOSTokens: [String]
}

enum FormattingModelCatalog {
    nonisolated static let all: [FormattingModelDescriptor] = [
        FormattingModelDescriptor(
            id: .qwen3_4b,
            backendKind: .mlx,
            huggingFaceModelID: "mlx-community/Qwen3.5-4B-MLX-4bit",
            cacheNamespace: "mlx-community",
            cacheSlug: "Qwen3.5-4B-MLX-4bit",
            cacheMatchHints: ["models--mlx-community--qwen3.5-4b-mlx-4bit", "qwen3.5-4b-mlx-4bit"],
            approximateBytes: 3_100 * 1_024 * 1_024,
            prefersRawAlpacaPrompt: false,
            extraEOSTokens: []
        )
    ]

    nonisolated static func descriptor(for id: FormattingModelID) -> FormattingModelDescriptor {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

// MARK: - Transcription Input

/// Input to the formatting pipeline.
/// Designed for future extension to a full TranscriptionRequest contract
/// (e.g. surrounding text, cursor position, prior context).
struct TranscriptionInput: Sendable {
    let rawText: String
    let languageCode: String
    let targetBundleID: String?
}

// MARK: - Pipeline Metadata

/// Immutable snapshot of app state captured at pipeline start.
/// Stages read from this instead of reaching into global singletons.
struct PipelineMetadata: Sendable {
    let languageCode: String
    let targetBundleID: String?
    let tone: WritingTone
    let outputProfile: OutputProfile
    let formattingModelID: FormattingModelID
    let protectedTerms: [String]
    let defaultCodeStyle: CodeStyle
    let formattingMode: FormattingMode
    let isProModeUnlocked: Bool
    let isLLMLoaded: Bool
}

// MARK: - Stage I/O

/// Mutable state flowing through the pipeline.
struct StageIO {
    var text: String
    var extractedCommand: RecognizedCommand
    let metadata: PipelineMetadata
    var pipelineDecision: PipelineDecision = .deterministicOnly
    var fallbackReason: FallbackReason?
    var stageTransformations: [String] = []
    var stageWasSkipped: Bool = false

    /// Creates a copy with updated text, preserving all other fields.
    func withText(
        _ newText: String,
        stageTransformations: [String] = [],
        stageWasSkipped: Bool = false,
        pipelineDecision: PipelineDecision? = nil,
        fallbackReason: FallbackReason? = nil,
        clearFallbackReason: Bool = false
    ) -> StageIO {
        var copy = self
        copy.text = newText
        copy.stageTransformations = stageTransformations
        copy.stageWasSkipped = stageWasSkipped
        if let pipelineDecision {
            copy.pipelineDecision = pipelineDecision
        }
        if clearFallbackReason {
            copy.fallbackReason = nil
        } else if let fallbackReason {
            copy.fallbackReason = fallbackReason
        }
        return copy
    }

    /// Creates a copy with an extracted command.
    func withCommand(
        _ command: RecognizedCommand,
        text: String,
        stageTransformations: [String] = [],
        stageWasSkipped: Bool = false,
        pipelineDecision: PipelineDecision? = nil,
        fallbackReason: FallbackReason? = nil,
        clearFallbackReason: Bool = false
    ) -> StageIO {
        var copy = self
        copy.extractedCommand = command
        copy.text = text
        copy.stageTransformations = stageTransformations
        copy.stageWasSkipped = stageWasSkipped
        if let pipelineDecision {
            copy.pipelineDecision = pipelineDecision
        }
        if clearFallbackReason {
            copy.fallbackReason = nil
        } else if let fallbackReason {
            copy.fallbackReason = fallbackReason
        }
        return copy
    }

    /// Clears per-stage metadata before the next stage runs.
    func clearingStageMetadata() -> StageIO {
        var copy = self
        copy.stageTransformations = []
        copy.stageWasSkipped = false
        return copy
    }
}

// MARK: - Stage Trace (Codable for evaluation harness)

struct StageTrace: Sendable, Codable {
    let stageName: String
    let stageIndex: Int
    let inputPreview: String
    let outputPreview: String
    let inputLength: Int
    let outputLength: Int
    let durationMs: Double
    let transformations: [String]
    let isModelBased: Bool
    let wasSkipped: Bool

    static func record(
        name: String,
        index: Int,
        input: String,
        output: String,
        durationMs: Double,
        transformations: [String] = [],
        isModelBased: Bool = false,
        wasSkipped: Bool = false,
        previewLength: Int = 200
    ) -> StageTrace {
        StageTrace(
            stageName: name,
            stageIndex: index,
            inputPreview: String(input.prefix(previewLength)),
            outputPreview: String(output.prefix(previewLength)),
            inputLength: input.count,
            outputLength: output.count,
            durationMs: durationMs,
            transformations: transformations,
            isModelBased: isModelBased,
            wasSkipped: wasSkipped
        )
    }
}

// MARK: - Pipeline Result

struct PipelineResult: Sendable {
    let finalText: String
    let extractedCommand: RecognizedCommand
    let decision: PipelineDecision
    let fallbackReason: FallbackReason?
    let trace: [StageTrace]
    let totalDurationMs: Double
    let listBlocksCount: Int

    /// Exports all traces as JSON Data for evaluation harnesses.
    func exportTraceJSON() -> Data? {
        try? JSONEncoder().encode(trace)
    }
}

// MARK: - Pipeline Stage Protocol

/// A single composable stage in the post-ASR pipeline.
/// Stages must not perform destructive operations (lowercasing, punctuation stripping)
/// unless explicitly appropriate for that stage's purpose.
protocol PipelineStage {
    var name: String { get }
    var isModelBased: Bool { get }
    func process(_ input: StageIO) async -> StageIO
}

extension PipelineStage {
    var isModelBased: Bool { false }
}
