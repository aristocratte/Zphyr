//
//  PipelineTypes.swift
//  Zphyr
//
//  Core types for the layered post-ASR formatting pipeline.
//  All types are Sendable; StageTrace is Codable for evaluation export.
//

import Foundation

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

    /// Creates a copy with updated text, preserving all other fields.
    func withText(_ newText: String) -> StageIO {
        var copy = self
        copy.text = newText
        return copy
    }

    /// Creates a copy with an extracted command.
    func withCommand(_ command: RecognizedCommand, text: String) -> StageIO {
        var copy = self
        copy.extractedCommand = command
        copy.text = text
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
@MainActor
protocol PipelineStage {
    var name: String { get }
    var isModelBased: Bool { get }
    func process(_ input: StageIO) async -> StageIO
}

extension PipelineStage {
    var isModelBased: Bool { false }
}
