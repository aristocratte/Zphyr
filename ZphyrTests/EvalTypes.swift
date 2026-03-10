//
//  EvalTypes.swift
//  ZphyrTests
//
//  Core types for the Zphyr evaluation harness.
//  These are separate from production types so eval-specific metadata
//  does not bleed into the shipping pipeline.
//

@testable import Zphyr
import Foundation

// MARK: - Dataset Case

/// A single test case loaded from a JSONL dataset file.
struct EvalCase: Codable {
    let id: String
    let rawAsrText: String
    let literalReference: String
    let finalExpectedText: String
    let acceptableVariants: [String]
    let protectedTerms: [String]
    let extractedCommandExpected: String?    // nil means no command expected
    let rewriteAllowedLevel: String          // "none" | "light" | "full"
    let contextType: String
    let appType: String
    let formattingMode: String
    let language: String
    let notes: String?

    // Decode from the JSONL schema (snake_case keys → camelCase)
    enum CodingKeys: String, CodingKey {
        case id
        case rawAsrText               = "raw_asr_text"
        case literalReference         = "literal_reference"
        case finalExpectedText        = "final_expected_text"
        case acceptableVariants       = "acceptable_variants"
        case protectedTerms           = "protected_terms"
        case extractedCommandExpected = "extracted_command_expected"
        case rewriteAllowedLevel      = "rewrite_allowed_level"
        case contextType              = "context_type"
        case appType                  = "app_type"
        case formattingMode           = "formatting_mode"
        case language
        case notes
    }
}

// MARK: - Runtime Dimensions

enum EvalFormattingMode: String, CaseIterable {
    case deterministicOnly = "trigger"
    case advancedLLM       = "advanced"
}

// MARK: - Hard Failure Reasons

enum HardFailureReason: String, Codable {
    case protectedTermMissing
    case protectedTermCaseCorruption
    case malformedURL
    case malformedEmail
    case spuriousCommand          // command extracted when none expected
    case commandMismatch          // wrong command type
    case forbiddenRewrite         // content changed with rewrite_allowed_level = "none"
    case formattingPolicyViolation
    case numericCorruption        // number / date / version changed
}

// MARK: - Stage Execution Status

enum StageExecutionStatus: String, Codable {
    case ranNormally
    case skipped          // stage gated off (e.g. LLM not loaded)
    case failedClosed     // ran but fell back to input due to integrity failure
    case shortCircuited   // upstream cancel command aborted pipeline
}

// MARK: - Eval Stage Trace (extends StageTrace with eval metadata)

struct EvalStageTrace: Codable {
    let stageName: String
    let stageIndex: Int
    let inputPreview: String
    let outputPreview: String
    let inputLength: Int
    let outputLength: Int
    let durationMs: Double
    let transformations: [String]
    let isModelBased: Bool
    let executionStatus: StageExecutionStatus

    init(from trace: StageTrace, executionStatus: StageExecutionStatus) {
        self.stageName       = trace.stageName
        self.stageIndex      = trace.stageIndex
        self.inputPreview    = trace.inputPreview
        self.outputPreview   = trace.outputPreview
        self.inputLength     = trace.inputLength
        self.outputLength    = trace.outputLength
        self.durationMs      = trace.durationMs
        self.transformations = trace.transformations
        self.isModelBased    = trace.isModelBased
        self.executionStatus = executionStatus
    }
}

// MARK: - Eval Run Record (fully self-sufficient for debugging)

/// A single evaluated case record. Contains all inputs, outputs, and failure reasons.
/// Designed to be self-sufficient: this JSON artifact alone can drive all metric computation.
struct EvalRunRecord: Codable {
    // ── Case identity ──────────────────────────────────────────────────────
    let caseID: String
    let contextType: String
    let language: String
    let notes: String?

    // ── Runtime dimensions ─────────────────────────────────────────────────
    let formattingMode: String

    // ── Raw inputs (preserved verbatim for cross-case debugging) ───────────
    let rawAsrText: String
    let literalReference: String
    let finalExpectedText: String
    let acceptableVariants: [String]
    let protectedTerms: [String]
    let expectedCommand: String?   // nil = no command expected
    let rewriteAllowedLevel: String

    // ── Pipeline outputs ───────────────────────────────────────────────────
    let finalText: String
    let actualCommand: String      // "none" if no command extracted
    let rewriteStageRan: Bool
    let stageTraces: [EvalStageTrace]
    let totalDurationMs: Double

    // ── Hard failure reasons (empty = all hard checks passed) ──────────────
    let hardFailureReasons: [HardFailureReason]
}

// MARK: - Run Summary (aggregate over all records)

struct EvalRunSummary: Codable {
    let runDate: String            // ISO-8601
    let formattingMode: String
    let totalCases: Int
    let hardFailureCount: Int
    let hardFailureRate: Double    // 0.0–1.0
    let perCategory: [String: CategorySummary]
}

struct CategorySummary: Codable {
    let caseCount: Int
    let hardFailures: Int
    let meanDurationMs: Double
    let stageDurations: [String: Double]  // stageName → mean durationMs
}
