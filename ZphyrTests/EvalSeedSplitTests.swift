//
//  EvalSeedSplitTests.swift
//  ZphyrTests
//
//  Evaluation harness for the new 300-example seed split.
//  This evaluates the current checkpoint on the 45-example test split
//  to determine if patch fine-tuning is warranted.
//
//  Usage:
//    xcodebuild test -scheme Zphyr \
//      -only-testing:ZphyrTests/EvalSeedSplitTests \
//      EVAL_MODE=advanced
//
//  Output: Evals/reports/seed_split_{mode}_L2.json

@testable import Zphyr
import XCTest
import Foundation

// MARK: - Seed Split Dataset Schema

/// Schema for the new seed split format (Evals/datasets/splits/test.jsonl)
struct SeedSplitCase: Codable {
    let id: String
    let rawAsrText: String
    let finalExpectedText: String
    let category: String
    let subcategory: String
    let language: String
    let rewriteAllowedLevel: String
    let isNullEdit: Bool
    let difficulty: String
    let severityIfWrong: String
    let protectedTerms: [String]
    let noTranslation: Bool
    let notes: String

    // Decode from snake_case keys
    enum CodingKeys: String, CodingKey {
        case id
        case rawAsrText               = "raw_asr_text"
        case finalExpectedText        = "final_expected_text"
        case category
        case subcategory
        case language
        case rewriteAllowedLevel      = "rewrite_allowed_level"
        case isNullEdit               = "is_null_edit"
        case difficulty
        case severityIfWrong          = "severity_if_wrong"
        case protectedTerms           = "protected_terms"
        case noTranslation            = "no_translation"
        case notes
    }
}

// MARK: - Seed Split Evaluation Record

/// Result record for a single seed split evaluation.
struct SeedEvalRunRecord: Codable {
    let caseID: String
    let category: String
    let subcategory: String
    let language: String
    let isNullEdit: Bool
    let severityIfWrong: String

    // Inputs
    let rawAsrText: String
    let finalExpectedText: String
    let protectedTerms: [String]
    let noTranslation: Bool

    // Outputs
    let finalText: String
    let actualCommand: String

    // Metrics
    let exactMatch: Bool
    let wer: Double
    let cer: Double
    let nullEditPreserved: Bool
    let protectedTermsPreserved: Bool
    let protectedTermsMissing: [String]
    let isHardNegative: Bool
    let hardNegativePass: Bool
    let translationViolation: Bool
    let reasoningTagContamination: Bool

    // Pipeline trace
    let rewriteStageRan: Bool
    let totalDurationMs: Double
}

// MARK: - Seed Split Evaluation Harness

@MainActor
final class EvalSeedSplitTests: XCTestCase {

    private struct RuntimeConfig: Decodable {
        let mode: String?
        let splitPath: String?
        let splitName: String?
        let outputFile: String?
        let modelPath: String?

        enum CodingKeys: String, CodingKey {
            case mode
            case splitPath = "split_path"
            case splitName = "split_name"
            case outputFile = "output_file"
            case modelPath = "model_path"
        }
    }

    private let pipeline = FormattingPipeline()

    // ── Path resolution ─────────────────────────────────────────────────────

    private var fileManager: FileManager { .default }

    private var evalsRoot: URL {
        let sentinelPath = "Evals/datasets/splits/test.jsonl"

        // Candidate base directories to search
        var candidates: [URL] = []

        // 1. Current working directory
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

        // 2. #filePath: ZphyrTests/EvalSeedSplitTests.swift
        //    Go up: ZphyrTests/ → Zphyr/ → repo root
        let filePath = URL(fileURLWithPath: #filePath)
        let zphyrTestsDir = filePath.deletingLastPathComponent()
        let zphyrDir = zphyrTestsDir.deletingLastPathComponent()
        candidates.append(zphyrDir)

        // 3. DerivedData build products (when running from xcodebuild)
        if let buildDir = ProcessInfo.processInfo.environment["BUILD_DIR"] {
            candidates.append(URL(fileURLWithPath: buildDir).deletingLastPathComponent())
        }

        // 4. Common project root locations
        if let projectRoot = zphyrDir.deletingLastPathComponent().path != zphyrDir.path
            ? zphyrDir.deletingLastPathComponent() : nil {
            candidates.append(projectRoot)
        }

        // Try each candidate
        for base in candidates {
            let evalsPath = base.appendingPathComponent("Evals")
            let testPath = evalsPath.appendingPathComponent("datasets/splits/test.jsonl")

            // Debug output for path resolution
            #if DEBUG
            print("[EvalSeedSplitTests] Checking: \(testPath.path)")
            #endif

            if fileManager.fileExists(atPath: testPath.path) {
                print("[EvalSeedSplitTests] Found Evals root at: \(evalsPath.path)")
                return evalsPath
            }
        }

        // Last resort: return a path and let the error be caught
        let fallback = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Evals", isDirectory: true)
        print("[EvalSeedSplitTests] WARNING: Could not find Evals root, using fallback: \(fallback.path)")
        return fallback
    }

    var testSplitURL: URL {
        if let configuredSplitPath = ProcessInfo.processInfo.environment["EVAL_SPLIT_PATH"],
           !configuredSplitPath.isEmpty {
            return resolveConfiguredSplitURL(configuredSplitPath)
        }
        if let configuredSplitPath = loadRuntimeConfig()?.splitPath,
           !configuredSplitPath.isEmpty {
            return resolveConfiguredSplitURL(configuredSplitPath)
        }
        return evalsRoot.appendingPathComponent("datasets/splits/test.jsonl")
    }

    var reportsURL: URL {
        let reports = evalsRoot.appendingPathComponent("reports")
        try? fileManager.createDirectory(at: reports, withIntermediateDirectories: true)
        return reports
    }

    private func loadRuntimeConfig() -> RuntimeConfig? {
        let explicitPath = ProcessInfo.processInfo.environment["EVAL_SPLIT_CONFIG_PATH"]
        let configURL: URL
        if let explicitPath, !explicitPath.isEmpty {
            configURL = URL(fileURLWithPath: explicitPath)
        } else {
            configURL = reportsURL.appendingPathComponent("current_seed_split_config.json")
        }

        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return nil
        }

        return try? JSONDecoder().decode(RuntimeConfig.self, from: data)
    }

    private func resolveConfiguredSplitURL(_ configuredSplitPath: String) -> URL {
        let absoluteCandidate = URL(fileURLWithPath: configuredSplitPath, isDirectory: false)
        if FileManager.default.fileExists(atPath: absoluteCandidate.path) {
            return absoluteCandidate
        }

        let relativeCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(configuredSplitPath)
        if FileManager.default.fileExists(atPath: relativeCandidate.path) {
            return relativeCandidate
        }

        return absoluteCandidate
    }

    // ── Setup ───────────────────────────────────────────────────────────────

    override func setUp() async throws {
        try await super.setUp()
        let runtimeConfig = loadRuntimeConfig()

        // Apply EVAL_MODE to AppState so pipeline runs under correct mode
        let modeStr = evalMode
        print("[EvalSeedSplitTests] EVAL_MODE: \(modeStr)")
        if let mode = FormattingMode(rawValue: modeStr) {
            AppState.shared.formattingMode = mode
            print("[EvalSeedSplitTests] FormattingMode set to: \(mode.rawValue)")
        } else {
            print("[EvalSeedSplitTests] WARNING: Unsupported EVAL_MODE '\(modeStr)', using 'advanced'")
            AppState.shared.formattingMode = .advanced
        }

        print("[EvalSeedSplitTests] splitPath: \(testSplitURL.path)")
        print("[EvalSeedSplitTests] splitName: \(splitName)")
        print("[EvalSeedSplitTests] runtimeConfig present: \(runtimeConfig != nil)")

        if let modelPath = runtimeConfig?.modelPath, !modelPath.isEmpty {
            let overrideURL = URL(fileURLWithPath: modelPath, isDirectory: true)
            AdvancedLLMFormatter.overrideInstallURL = overrideURL
            print("[EvalSeedSplitTests] modelPath override: \(modelPath)")

            let resolvedPath = AdvancedLLMFormatter.resolveInstallURL()?.path ?? "nil"
            print("[EvalSeedSplitTests] formatter resolved path: \(resolvedPath)")

            if resolvedPath == "nil" {
                XCTFail("Explicit formatter model path is invalid or incomplete: \(modelPath)")
                return
            }

            AppState.shared.advancedModeInstalled = true
            await AdvancedLLMFormatter.shared.loadIfInstalled()
            print("[EvalSeedSplitTests] formatter installed flag: \(AppState.shared.advancedModeInstalled)")
            print("[EvalSeedSplitTests] formatter loaded: \(AdvancedLLMFormatter.shared.isModelLoaded)")

            if !AdvancedLLMFormatter.shared.isModelLoaded {
                XCTFail("Formatter model did not load from explicit path: \(modelPath)")
            }
        } else {
            AdvancedLLMFormatter.overrideInstallURL = nil
            print("[EvalSeedSplitTests] formatter resolved path: \(AdvancedLLMFormatter.resolveInstallURL()?.path ?? "nil")")
            print("[EvalSeedSplitTests] formatter installed flag: \(AppState.shared.advancedModeInstalled)")
            print("[EvalSeedSplitTests] formatter loaded: \(AdvancedLLMFormatter.shared.isModelLoaded)")
        }
    }

    override func tearDown() async throws {
        AdvancedLLMFormatter.overrideInstallURL = nil
        try await super.tearDown()
    }

    var evalMode: String {
        ProcessInfo.processInfo.environment["EVAL_MODE"]
            ?? loadRuntimeConfig()?.mode
            ?? "advanced"
    }

    var splitName: String {
        let raw = ProcessInfo.processInfo.environment["EVAL_SPLIT_NAME"]
            ?? loadRuntimeConfig()?.splitName
            ?? testSplitURL.deletingPathExtension().lastPathComponent
        let sanitized = raw.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "_",
            options: .regularExpression
        )
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // ── Load test split ─────────────────────────────────────────────────────

    private func loadTestSplit() -> [SeedSplitCase] {
        guard let data = try? Data(contentsOf: testSplitURL) else {
            XCTFail("Cannot load test split from: \(testSplitURL.path)")
            return []
        }

        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
        var cases: [SeedSplitCase] = []

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let lineData = line.data(using: .utf8),
               let evalCase = try? JSONDecoder().decode(SeedSplitCase.self, from: lineData) {
                cases.append(evalCase)
            }
        }

        return cases
    }

    // ── WER/CER computation ─────────────────────────────────────────────────

    private func computeWER(reference: String, hypothesis: String) -> Double {
        let refWords = reference.split(separator: " ").map { $0.lowercased() }
        let hypWords = hypothesis.split(separator: " ").map { $0.lowercased() }

        guard !refWords.isEmpty else { return hypWords.isEmpty ? 0.0 : 1.0 }

        let m = refWords.count
        let n = hypWords.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = refWords[i-1] == hypWords[j-1] ? 0 : 1
                dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
            }
        }

        return Double(dp[m][n]) / Double(m)
    }

    private func computeCER(reference: String, hypothesis: String) -> Double {
        let refChars = Array(reference.lowercased())
        let hypChars = Array(hypothesis.lowercased())

        guard !refChars.isEmpty else { return hypChars.isEmpty ? 0.0 : 1.0 }

        let m = refChars.count
        let n = hypChars.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = refChars[i-1] == hypChars[j-1] ? 0 : 1
                dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
            }
        }

        return Double(dp[m][n]) / Double(m)
    }

    // ── Translation violation check (simplified) ────────────────────────────

    private func checkTranslationViolation(
        raw: String,
        output: String,
        noTranslation: Bool
    ) -> Bool {
        guard noTranslation else { return false }

        // Simplified check: detect major language shifts
        // (Full translation detection requires linguistic analysis)
        let frenchIndicators = ["le", "la", "les", "un", "une", "des", "ce", "cet", "cette", "mes", "tes", "ses"]
        let englishIndicators = ["the", "a", "an", "this", "that", "these", "those", "my", "your", "his", "her"]

        let rawWords = Set(raw.lowercased().split(separator: " ").map { String($0) })
        let outputWords = Set(output.lowercased().split(separator: " ").map { String($0) })

        // Count indicator words in raw vs output
        let rawFrench = rawWords.intersection(frenchIndicators).count
        let rawEnglish = rawWords.intersection(englishIndicators).count
        let outputFrench = outputWords.intersection(frenchIndicators).count
        let outputEnglish = outputWords.intersection(englishIndicators).count

        // Detect language shift (heuristic)
        if rawFrench > rawEnglish && outputEnglish > outputFrench && outputEnglish > 2 {
            return true  // FR → EN shift detected
        }
        if rawEnglish > rawFrench && outputFrench > outputEnglish && outputFrench > 2 {
            return true  // EN → FR shift detected
        }

        return false
    }

    // ── Hard negative check ────────────────────────────────────────────────

    private func isHardNegative(subcategory: String) -> Bool {
        return [
            "intentional_repetition",
            "no_list_ambiguous",
            "ambiguous_command_content"
        ].contains(subcategory)
    }

    // ── Format command from RecognizedCommand ─────────────────────────────

    private func formatCommand(_ cmd: RecognizedCommand) -> String {
        switch cmd {
        case .none:                    return "none"
        case .cancelLast:              return "cancelLast"
        case .copyOnly:                return "copyOnly"
        case .newParagraph:            return "newParagraph"
        case .forceList:               return "forceList"
        case .customAction(let name):  return "customAction(\(name))"
        }
    }

    // ── Main test: Evaluate seed split ───────────────────────────────────────

    func testSeedSplitEvaluation() async throws {
        print("\n=== SEED SPLIT EVALUATION START ===")
        print("testSplitURL: \(testSplitURL.path)")
        print("File exists: \(FileManager.default.fileExists(atPath: testSplitURL.path))")

        let cases = loadTestSplit()
        print("Loaded \(cases.count) cases")
        guard !cases.isEmpty else {
            XCTFail("No test cases loaded from seed split")
            return
        }

        print("\n=== SEED SPLIT EVALUATION ===")
        print("Mode: \(evalMode)")
        print("Split: \(splitName)")
        print("Test cases: \(cases.count)")
        print("Formatter resolved path: \(AdvancedLLMFormatter.resolveInstallURL()?.path ?? "nil")")
        print("Formatter installed flag: \(AppState.shared.advancedModeInstalled)")
        print("Formatter loaded: \(AdvancedLLMFormatter.shared.isModelLoaded)")
        print("============================\n")

        var records: [SeedEvalRunRecord] = []

        for evalCase in cases {
            let input = TranscriptionInput(
                rawText: evalCase.rawAsrText,
                languageCode: evalCase.language,
                targetBundleID: nil
            )

            let result = await pipeline.run(input)
            let finalText = result.finalText
            let actualCommand = formatCommand(result.extractedCommand)

            // Compute metrics
            let exactMatch = finalText == evalCase.finalExpectedText
            let wer = computeWER(reference: evalCase.finalExpectedText, hypothesis: finalText)
            let cer = computeCER(reference: evalCase.finalExpectedText, hypothesis: finalText)

            // Null edit check
            let nullEditPreserved = evalCase.isNullEdit && (finalText == evalCase.rawAsrText)

            // Protected terms check
            let missingTerms = evalCase.protectedTerms.filter { !finalText.contains($0) }
            let protectedTermsPreserved = missingTerms.isEmpty

            // Hard negative check
            let hardNegative = isHardNegative(subcategory: evalCase.subcategory)
            let hardNegativePass = hardNegative && exactMatch

            // Translation violation check
            let translationViolation = checkTranslationViolation(
                raw: evalCase.rawAsrText,
                output: finalText,
                noTranslation: evalCase.noTranslation
            )

            let reasoningTagContamination =
                finalText.localizedCaseInsensitiveContains("<think>")
                || finalText.localizedCaseInsensitiveContains("</think>")

            // Determine if rewrite stage ran
            let rewriteStageRan = result.trace.contains { trace in
                trace.stageName.contains("Rewrite") &&
                !trace.wasSkipped &&
                !trace.transformations.contains { $0.hasPrefix("rewrite_failed_closed") }
            }

            let record = SeedEvalRunRecord(
                caseID: evalCase.id,
                category: evalCase.category,
                subcategory: evalCase.subcategory,
                language: evalCase.language,
                isNullEdit: evalCase.isNullEdit,
                severityIfWrong: evalCase.severityIfWrong,

                rawAsrText: evalCase.rawAsrText,
                finalExpectedText: evalCase.finalExpectedText,
                protectedTerms: evalCase.protectedTerms,
                noTranslation: evalCase.noTranslation,

                finalText: finalText,
                actualCommand: actualCommand,

                exactMatch: exactMatch,
                wer: wer,
                cer: cer,
                nullEditPreserved: nullEditPreserved,
                protectedTermsPreserved: protectedTermsPreserved,
                protectedTermsMissing: missingTerms,
                isHardNegative: hardNegative,
                hardNegativePass: hardNegativePass,
                translationViolation: translationViolation,
                reasoningTagContamination: reasoningTagContamination,

                rewriteStageRan: rewriteStageRan,
                totalDurationMs: result.totalDurationMs
            )

            records.append(record)

            // Print progress
            if records.count % 10 == 0 {
                print("  Processed \(records.count)/\(cases.count)...")
            }
        }

        // Write results
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else {
            XCTFail("Failed to encode results")
            return
        }

        let outputFile = ProcessInfo.processInfo.environment["EVAL_OUTPUT_FILE"]
            ?? loadRuntimeConfig()?.outputFile
            ?? "seed_split_\(splitName)_\(evalMode)_L2.json"
        let outputURL = reportsURL.appendingPathComponent(outputFile)
        try data.write(to: outputURL)

        print("\n=== RESULTS SUMMARY ===")
        print("Output: \(outputURL.path)")

        // Aggregate metrics
        let total = records.count
        let exactMatches = records.filter { $0.exactMatch }.count
        let meanWER = records.map { $0.wer }.reduce(0, +) / Double(max(total, 1))
        let meanCER = records.map { $0.cer }.reduce(0, +) / Double(max(total, 1))

        // Null edit preservation
        let nullEditCases = records.filter { $0.isNullEdit }
        let nullEditPreserved = nullEditCases.filter { $0.nullEditPreserved }.count

        // Hard negative pass rate
        let hardNegatives = records.filter { $0.isHardNegative }
        let hardNegativePasses = hardNegatives.filter { $0.hardNegativePass }.count

        // Protected term accuracy
        let protectedCases = records.filter { !$0.protectedTerms.isEmpty }
        let totalProtectedTerms = protectedCases.reduce(0) { $0 + $1.protectedTerms.count }
        let preservedTerms = totalProtectedTerms - protectedCases.reduce(0) { $0 + $1.protectedTermsMissing.count }

        // Translation violations
        let translationViolations = records.filter { $0.translationViolation }.count
        let reasoningContaminations = records.filter { $0.reasoningTagContamination }.count

        print("\n─ OVERALL METRICS (n=\(total)) ─")
        print("  Exact match rate:  \(exactMatches)/\(total) (\(String(format: "%.1f", Double(exactMatches)/Double(total)*100))%)")
        print("  Mean WER:         \(String(format: "%.4f", meanWER))")
        print("  Mean CER:         \(String(format: "%.4f", meanCER))")

        print("\n─ NULL EDIT PRESERVATION (\(nullEditCases.count) examples) ─")
        print("  Preserved:        \(nullEditPreserved)/\(nullEditCases.count) (\(nullEditCases.count > 0 ? String(format: "%.1f", Double(nullEditPreserved)/Double(nullEditCases.count)*100) : "N/A")%)")

        print("\n─ HARD NEGATIVE PASS RATE (\(hardNegatives.count) examples) ─")
        print("  Passed:           \(hardNegativePasses)/\(hardNegatives.count) (\(hardNegatives.count > 0 ? String(format: "%.1f", Double(hardNegativePasses)/Double(hardNegatives.count)*100) : "N/A")%)")

        print("\n─ PROTECTED TERM ACCURACY ─")
        print("  Terms preserved:  \(preservedTerms)/\(totalProtectedTerms) (\(totalProtectedTerms > 0 ? String(format: "%.1f", Double(preservedTerms)/Double(totalProtectedTerms)*100) : "N/A")%)")
        print("  Examples with any missing: \(protectedCases.filter { !$0.protectedTermsPreserved }.count)/\(protectedCases.count)")

        print("\n─ TRANSLATION VIOLATIONS ─")
        print("  Violations:       \(translationViolations)")

        print("\n─ REASONING TAG CONTAMINATION ─")
        print("  Contaminated:     \(reasoningContaminations)")

        print("\n─ CATEGORY BREAKDOWN ─")
        let byCategory = Dictionary(grouping: records, by: { $0.category })
        for (category, catRecords) in byCategory.sorted(by: { $0.key < $1.key }) {
            let catWER = catRecords.map { $0.wer }.reduce(0, +) / Double(max(catRecords.count, 1))
            let catCER = catRecords.map { $0.cer }.reduce(0, +) / Double(max(catRecords.count, 1))
            print("  \(category.padding(toLength: 14, withPad: " ", startingAt: 0)) WER=\(String(format: "%.4f", catWER))  CER=\(String(format: "%.4f", catCER))  (n=\(catRecords.count))")
        }

        print("\n─ FAILURE MODES ─")
        let nullFailures = records.filter { $0.isNullEdit && !$0.nullEditPreserved }
        if !nullFailures.isEmpty {
            print("\n  Null edit failures (\(nullFailures.count)):")
            for r in nullFailures.prefix(5) {
                print("    - \(r.caseID): '\(r.rawAsrText)' → '\(r.finalText)'")
            }
        }

        let hardNegFailures = records.filter { $0.isHardNegative && !$0.hardNegativePass }
        if !hardNegFailures.isEmpty {
            print("\n  Hard negative failures (\(hardNegFailures.count)):")
            for r in hardNegFailures {
                print("    - \(r.caseID) (\(r.subcategory))")
                print("      Expected: '\(r.finalExpectedText)'")
                print("      Got:      '\(r.finalText)'")
            }
        }

        let protectedFailures = records.filter { !$0.protectedTerms.isEmpty && !$0.protectedTermsPreserved }
        if !protectedFailures.isEmpty {
            print("\n  Protected term failures (\(protectedFailures.count)):")
            for r in protectedFailures.prefix(5) {
                print("    - \(r.caseID): missing \(r.protectedTermsMissing)")
            }
        }

        if translationViolations > 0 {
            print("\n  Translation violation cases:")
            for r in records.filter({ $0.translationViolation }) {
                print("    - \(r.caseID)")
            }
        }

        if reasoningContaminations > 0 {
            print("\n  Reasoning tag contamination cases:")
            for r in records.filter({ $0.reasoningTagContamination }).prefix(10) {
                print("    - \(r.caseID): '\(r.finalText)'")
            }
        }

        print("\n========================\n")

        // Hard assertions
        if translationViolations > 0 {
            XCTFail("Translation violations detected: \(translationViolations). This is a hard constraint failure.")
        }
        if reasoningContaminations > 0 {
            XCTFail("Reasoning tag contamination detected: \(reasoningContaminations). Final output must never expose <think>.")
        }
    }
}
