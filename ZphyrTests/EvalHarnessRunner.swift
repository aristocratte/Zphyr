//
//  EvalHarnessRunner.swift
//  ZphyrTests
//
//  Three XCTestCase subclasses — one per evaluation layer.
//  L1a: raw ASR transcript quality (transcript-only, no audio in v1).
//  L2:  post-ASR formatting pipeline — THE CORE of v1.
//  L3:  end-to-end final text composite.
//
//  Runtime dimensions are first-class:
//    EVAL_MODE     env var: "trigger" | "advanced" (default: "trigger")
//    EVAL_CATEGORY env var: "all" | "prose" | "technical" | "commands" | etc.
//
//  Output: Evals/reports/current_run_{mode}[_{category}]_L2.json
//
//  Usage:
//    xcodebuild test -scheme Zphyr -only-testing:ZphyrTests/EvalL2Tests \
//      EVAL_MODE=trigger EVAL_CATEGORY=all

@testable import Zphyr
import XCTest
import Foundation

// MARK: - Shared Harness Infrastructure

@MainActor
class EvalHarnessBase: XCTestCase {

    private struct RuntimeConfig: Decodable {
        let mode: String?
        let category: String?
    }

    // ── Runtime configuration from env vars ───────────────────────────────
    static var evalMode: String {
        if let mode = ProcessInfo.processInfo.environment["EVAL_MODE"], !mode.isEmpty {
            return mode
        }
        if let mode = loadRuntimeConfig()?.mode, !mode.isEmpty {
            return mode
        }
        return "trigger"
    }
    static var evalCategory: String {
        if let category = ProcessInfo.processInfo.environment["EVAL_CATEGORY"], !category.isEmpty {
            return canonicalCategoryKey(category)
        }
        if let category = loadRuntimeConfig()?.category, !category.isEmpty {
            return canonicalCategoryKey(category)
        }
        return "all"
    }
    static var categorySuffix: String { evalCategory == "all" ? "" : "_\(evalCategory)" }
    static var runStem: String { "current_run_\(evalMode)\(categorySuffix)" }

    private static let fileManager = FileManager.default
    private static let evalsSentinelPath = "Evals/datasets/schema.json"

    static func canonicalCategoryKey(_ raw: String) -> String {
        switch raw.lowercased() {
        case "command", "commands":
            return "commands"
        case "list", "lists":
            return "lists"
        case "correction", "corrections":
            return "corrections"
        case "technical", "prose", "short", "multilingual", "all":
            return raw.lowercased()
        default:
            return raw.lowercased()
        }
    }

    static func contextType(forCategoryKey key: String) -> String {
        switch canonicalCategoryKey(key) {
        case "commands":
            return "command"
        case "lists":
            return "list"
        case "corrections":
            return "correction"
        default:
            return canonicalCategoryKey(key)
        }
    }

    private static func containsEvalsRoot(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(evalsSentinelPath).path)
    }

    private static func findRepoRoot(startingAt startURL: URL) -> URL? {
        var current = startURL.standardizedFileURL.resolvingSymlinksInPath()
        if !current.hasDirectoryPath {
            current = current.deletingLastPathComponent()
        }

        while true {
            if containsEvalsRoot(at: current) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func resolveEvalsRoot() -> URL? {
        if let override = ProcessInfo.processInfo.environment["EVALS_ROOT"], !override.isEmpty {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: true)
            if fileManager.fileExists(atPath: overrideURL.appendingPathComponent("datasets/schema.json").path) {
                return overrideURL
            }
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            sourceRoot,
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: Bundle(for: EvalHarnessBase.self).bundlePath, isDirectory: true)
        ]

        for candidate in candidates {
            if containsEvalsRoot(at: candidate) {
                return candidate.appendingPathComponent("Evals", isDirectory: true)
            }
            if let repoRoot = findRepoRoot(startingAt: candidate) {
                return repoRoot.appendingPathComponent("Evals", isDirectory: true)
            }
        }

        return nil
    }

    private static func loadRuntimeConfig() -> RuntimeConfig? {
        let configURL: URL?
        if let explicitPath = ProcessInfo.processInfo.environment["EVAL_CONFIG_PATH"], !explicitPath.isEmpty {
            configURL = URL(fileURLWithPath: explicitPath)
        } else {
            configURL = resolveEvalsRoot()?.appendingPathComponent("reports/current_eval_config.json")
        }

        guard let configURL,
              fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return nil
        }

        return try? JSONDecoder().decode(RuntimeConfig.self, from: data)
    }

    // ── Test setup: apply EVAL_MODE to AppState so the pipeline runs under the correct mode ──
    override func setUp() async throws {
        try await super.setUp()
        if let mode = FormattingMode(rawValue: Self.evalMode) {
            AppState.shared.formattingMode = mode
        } else {
            XCTFail("Unsupported EVAL_MODE: \(Self.evalMode)")
        }
    }

    // ── Paths ──────────────────────────────────────────────────────────────
    var evalsRoot: URL {
        guard let resolved = Self.resolveEvalsRoot() else {
            XCTFail("Could not locate Evals root. Set EVALS_ROOT or run from the repository checkout.")
            return URL(fileURLWithPath: Self.fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Evals", isDirectory: true)
        }
        return resolved
    }

    var datasetsURL: URL { evalsRoot.appendingPathComponent("datasets") }
    var reportsURL: URL  { evalsRoot.appendingPathComponent("reports") }

    // ── Category → JSONL file mapping ─────────────────────────────────────
    let categoryFiles: [String: String] = [
        "prose":        "prose.jsonl",
        "short":        "short.jsonl",
        "technical":    "technical.jsonl",
        "commands":     "commands.jsonl",
        "lists":        "lists.jsonl",
        "multilingual": "multilingual.jsonl",
        "corrections":  "corrections.jsonl",
    ]

    // ── Load cases from JSONL ──────────────────────────────────────────────
    func loadCases(category: String? = nil) -> [EvalCase] {
        let targetCategory = Self.canonicalCategoryKey(category ?? Self.evalCategory)
        let filesToLoad: [String]
        if targetCategory == "all" {
            filesToLoad = categoryFiles.keys.sorted().compactMap { categoryFiles[$0] }
        } else {
            guard let file = categoryFiles[targetCategory] else { return [] }
            filesToLoad = [file]
        }

        var cases: [EvalCase] = []
        let decoder = JSONDecoder()
        for file in filesToLoad {
            let url = datasetsURL.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url) else {
                XCTFail("Cannot load dataset: \(file)")
                continue
            }
            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
            for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let lineData = line.data(using: .utf8),
                   let evalCase = try? decoder.decode(EvalCase.self, from: lineData) {
                    cases.append(evalCase)
                }
            }
        }
        return cases
    }

    func loadL2Cases(category: String? = nil) -> [EvalCase] {
        let requestedCategory = Self.canonicalCategoryKey(category ?? Self.evalCategory)
        let matchingContextType = Self.contextType(forCategoryKey: requestedCategory)

        return loadCases(category: requestedCategory).filter { evalCase in
            guard evalCase.formattingMode == Self.evalMode else { return false }
            guard requestedCategory != "all" else { return true }
            return evalCase.contextType == matchingContextType
        }
    }

    // ── Hard check: protected terms ────────────────────────────────────────
    func checkProtectedTerms(finalText: String, terms: [String]) -> [HardFailureReason] {
        var failures: [HardFailureReason] = []
        for term in terms {
            guard !term.isEmpty else { continue }
            if !finalText.contains(term) {
                // Distinguish case corruption from missing term
                if finalText.lowercased().contains(term.lowercased()) {
                    failures.append(.protectedTermCaseCorruption)
                } else {
                    failures.append(.protectedTermMissing)
                }
            }
        }
        return failures
    }

    // ── Hard check: URL validity ───────────────────────────────────────────
    func checkURLIntegrity(finalText: String, terms: [String]) -> [HardFailureReason] {
        var failures: [HardFailureReason] = []
        let urlPattern = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#, options: [.caseInsensitive])
        for term in terms where term.lowercased().hasPrefix("http") {
            guard finalText.contains(term) else {
                failures.append(.malformedURL); continue
            }
            // Structural validity: must match URL regex
            let nsText = finalText as NSString
            let results = urlPattern?.matches(in: finalText,
                range: NSRange(location: 0, length: nsText.length)) ?? []
            let foundURLs = results.map { nsText.substring(with: $0.range) }
            if !foundURLs.contains(where: { $0.hasPrefix(term) || $0 == term }) {
                failures.append(.malformedURL)
            }
        }
        return failures
    }

    // ── Hard check: email validity ─────────────────────────────────────────
    func checkEmailIntegrity(finalText: String, terms: [String]) -> [HardFailureReason] {
        var failures: [HardFailureReason] = []
        let emailPattern = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
        for term in terms where term.contains("@") && !term.hasPrefix("@") {
            guard finalText.contains(term) else {
                failures.append(.malformedEmail); continue
            }
            let nsText = finalText as NSString
            let results = emailPattern?.matches(in: finalText,
                range: NSRange(location: 0, length: nsText.length)) ?? []
            let foundEmails = results.map { nsText.substring(with: $0.range) }
            if !foundEmails.contains(term) {
                failures.append(.malformedEmail)
            }
        }
        return failures
    }

    // ── Hard check: numeric/version integrity ──────────────────────────────
    func checkNumericIntegrity(
        rawText: String,
        finalText: String,
        contextType: String
    ) -> [HardFailureReason] {
        // Only promote to hard check for technical, corrections, commands
        let sensibleContexts: Set<String> = ["technical", "correction", "command"]
        guard sensibleContexts.contains(contextType) else { return [] }

        // Extract digit sequences and version-like patterns
        let digitPattern = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)*\b"#)
        func extract(_ text: String) -> Set<String> {
            let ns = text as NSString
            let results = digitPattern?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
            return Set(results.map { ns.substring(with: $0.range) })
        }
        let rawNumbers = extract(rawText)
        let finalNumbers = extract(finalText)

        // Numbers present in raw but missing or changed in final → corruption
        for num in rawNumbers {
            if !finalNumbers.contains(num) {
                // Allow if the number was reformatted acceptably (e.g. 30000 → 30,000)
                // Simple check: if the string version without commas matches
                let stripped = finalText.replacingOccurrences(of: ",", with: "")
                if !stripped.contains(num) {
                    return [.numericCorruption]
                }
            }
        }
        return []
    }

    // ── Hard check: command accuracy ──────────────────────────────────────
    func checkCommandAccuracy(
        expected: String?,
        actual: String
    ) -> [HardFailureReason] {
        let normalizedActual = actual == "none" ? nil : actual
        if expected == nil && normalizedActual != nil {
            return [.spuriousCommand]
        }
        if let expected = expected, normalizedActual != expected {
            return [.commandMismatch]
        }
        return []
    }

    // ── Hard check: rewrite gate ───────────────────────────────────────────
    /// Returns forbiddenRewrite if rewrite_allowed_level == "none" and
    /// content-changing transformation occurred beyond deterministic formatting.
    func checkRewriteGate(
        rawText: String,
        finalText: String,
        level: String
    ) -> [HardFailureReason] {
        guard level == "none" else { return [] }

        // Normalise both sides: lowercase, collapse whitespace, strip punctuation
        // Deterministic transforms allowed: punctuation add/remove, capitalisation,
        // filler removal, whitespace normalisation. Semantic word changes are not.
        let normalize: (String) -> String = { text in
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let rawNorm   = normalize(rawText)
        let finalNorm = normalize(finalText)

        // Remove known English/French filler words from raw for comparison
        let fillers = ["uh", "um", "er", "euh", "like", "so", "basically", "voilà"]
        let rawTokens   = rawNorm.components(separatedBy: " ").filter { !fillers.contains($0) }
        let finalTokens = finalNorm.components(separatedBy: " ")

        // If final contains tokens not in raw → content was added → forbidden rewrite
        let rawSet   = Set(rawTokens)
        let finalSet = Set(finalTokens)
        let inserted = finalSet.subtracting(rawSet)
        // Allow very minor insertions (articles, punctuation words already filtered)
        let forbiddenInsertions = inserted.filter { $0.count > 2 }
        if !forbiddenInsertions.isEmpty {
            return [.forbiddenRewrite]
        }
        return []
    }

    // ── Run all hard checks for a case ────────────────────────────────────
    func runHardChecks(evalCase: EvalCase, finalText: String, actualCommand: String) -> [HardFailureReason] {
        var failures: [HardFailureReason] = []

        failures += checkProtectedTerms(finalText: finalText, terms: evalCase.protectedTerms)
        failures += checkURLIntegrity(finalText: finalText, terms: evalCase.protectedTerms)
        failures += checkEmailIntegrity(finalText: finalText, terms: evalCase.protectedTerms)
        failures += checkNumericIntegrity(
            rawText: evalCase.rawAsrText,
            finalText: finalText,
            contextType: evalCase.contextType
        )
        failures += checkCommandAccuracy(
            expected: evalCase.extractedCommandExpected,
            actual: actualCommand
        )
        failures += checkRewriteGate(
            rawText: evalCase.rawAsrText,
            finalText: finalText,
            level: evalCase.rewriteAllowedLevel
        )
        return failures
    }

    // ── Format command from RecognizedCommand ─────────────────────────────
    func formatCommand(_ cmd: RecognizedCommand) -> String {
        switch cmd {
        case .none:                    return "none"
        case .cancelLast:              return "cancelLast"
        case .copyOnly:                return "copyOnly"
        case .newParagraph:            return "newParagraph"
        case .forceList:               return "forceList"
        case .customAction(let name):  return "customAction(\(name))"
        }
    }

    // ── Write run records to JSON ─────────────────────────────────────────
    func writeRunRecords(_ records: [EvalRunRecord], suffix: String = "") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }

        let filename = "\(Self.runStem)\(suffix).json"
        let url = reportsURL.appendingPathComponent(filename)
        try? FileManager.default.createDirectory(at: reportsURL,
            withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

// MARK: - L1a: Raw ASR Transcript Quality

/// L1a evaluates raw_asr_text vs literal_reference.
/// No pipeline is run — this measures transcription quality alone.
/// In v1, this is transcript-only (no audio). L1b (audio-backed) is deferred.
@MainActor
final class EvalL1aTests: EvalHarnessBase {

    func testL1a_TranscriptQuality() async {
        let cases = loadCases()
        guard !cases.isEmpty else { XCTFail("No cases loaded"); return }

        var records: [EvalRunRecord] = []
        var totalWERNumerator = 0
        var totalWERDenominator = 0

        for evalCase in cases {
            // L1a: pipeline is bypassed — compare raw ASR text vs literal reference
            let rawTokens = evalCase.rawAsrText.lowercased().components(separatedBy: .whitespaces)
            let refTokens = evalCase.literalReference.lowercased().components(separatedBy: .whitespaces)

            // Simple token-level WER approximation (full jiwer WER computed in Python)
            let editDist = levenshtein(rawTokens, refTokens)
            totalWERNumerator   += editDist
            totalWERDenominator += max(refTokens.count, 1)

            let record = EvalRunRecord(
                caseID:              evalCase.id,
                contextType:         evalCase.contextType,
                language:            evalCase.language,
                notes:               evalCase.notes,
                formattingMode:      "n/a (L1a)",
                rawAsrText:          evalCase.rawAsrText,
                literalReference:    evalCase.literalReference,
                finalExpectedText:   evalCase.finalExpectedText,
                acceptableVariants:  evalCase.acceptableVariants,
                protectedTerms:      evalCase.protectedTerms,
                expectedCommand:     evalCase.extractedCommandExpected,
                rewriteAllowedLevel: evalCase.rewriteAllowedLevel,
                finalText:           evalCase.rawAsrText,   // L1a: no transformation
                actualCommand:       "none",
                rewriteStageRan:     false,
                stageTraces:         [],
                totalDurationMs:     0.0,
                hardFailureReasons:  []
            )
            records.append(record)
        }

        let approxWER = Double(totalWERNumerator) / Double(max(totalWERDenominator, 1))
        print("[EvalL1a] Approximate word-level edit rate: \(String(format: "%.3f", approxWER)) over \(cases.count) cases")
        print("[EvalL1a] Note: precise WER/CER computed by Python metrics engine")

        writeRunRecords(records, suffix: "_L1a")
    }

    // Simple Levenshtein distance on token arrays
    private func levenshtein(_ a: [String], _ b: [String]) -> Int {
        var dp = Array(0...b.count)
        for i in 1...max(a.count, 1) {
            var prev = dp[0]; dp[0] = i
            let aToken = i <= a.count ? a[i-1] : ""
            for j in 1...max(b.count, 1) {
                let temp = dp[j]
                dp[j] = aToken == b[j-1] ? prev : min(prev, min(dp[j], dp[j-1])) + 1
                prev = temp
            }
        }
        return dp[b.count]
    }
}

// MARK: - L2: Post-ASR Formatting Quality (PRIMARY LAYER)

/// L2 is the core evaluation layer for v1.
/// Runs raw_asr_text through FormattingPipeline and compares to final_expected_text.
/// Hard checks run inline; results written to JSON for Python metrics engine.
@MainActor
final class EvalL2Tests: EvalHarnessBase {

    private let pipeline = FormattingPipeline()

    // ─── Full L2 run ───────────────────────────────────────────────────────

    func testL2_AllCategories() async throws {
        let requestedCategory = Self.evalCategory == "all" ? nil : Self.evalCategory
        let cases = loadL2Cases(category: requestedCategory)
        guard !cases.isEmpty else {
            XCTFail("No eval cases loaded for category: \(Self.evalCategory) in mode: \(Self.evalMode)")
            return
        }

        var records: [EvalRunRecord] = []
        var hardFailureCount = 0

        for evalCase in cases {
            let record = await runL2Case(evalCase)
            records.append(record)
            if !record.hardFailureReasons.isEmpty { hardFailureCount += 1 }
        }

        writeRunRecords(records, suffix: "_L2")
        printL2Summary(records: records, hardFailures: hardFailureCount)

        // Fail the test if any hard failures exist — they must not silently pass
        if hardFailureCount > 0 {
            let failedIDs = records
                .filter { !$0.hardFailureReasons.isEmpty }
                .map { "\($0.caseID): \($0.hardFailureReasons.map(\.rawValue).joined(separator: ", "))" }
                .joined(separator: "\n  ")
            XCTFail("[\(hardFailureCount)] hard failure(s) in L2 eval:\n  \(failedIDs)")
        }
    }

    // ─── Category-specific convenience tests ──────────────────────────────

    func testL2_Technical() async throws {
        let records = await runCategory("technical")
        assertNoHardFailures(in: records, category: "technical")
    }

    func testL2_Commands() async throws {
        let records = await runCategory("commands")
        assertNoHardFailures(in: records, category: "commands")
    }

    func testL2_Prose() async throws {
        let records = await runCategory("prose")
        assertNoHardFailures(in: records, category: "prose")
    }

    func testL2_Short() async throws {
        let records = await runCategory("short")
        assertNoHardFailures(in: records, category: "short")
    }

    func testL2_Lists() async throws {
        let records = await runCategory("lists")
        assertNoHardFailures(in: records, category: "lists")
    }

    func testL2_Multilingual() async throws {
        let records = await runCategory("multilingual")
        assertNoHardFailures(in: records, category: "multilingual")
    }

    func testL2_Corrections() async throws {
        let records = await runCategory("corrections")
        assertNoHardFailures(in: records, category: "corrections")
    }

    // ─── Core runner ──────────────────────────────────────────────────────

    private func runCategory(_ category: String) async -> [EvalRunRecord] {
        let cases = loadL2Cases(category: category)
        if cases.isEmpty {
            XCTFail("No eval cases loaded for category: \(category) in mode: \(Self.evalMode)")
            return []
        }
        var records: [EvalRunRecord] = []
        for evalCase in cases {
            records.append(await runL2Case(evalCase))
        }
        return records
    }

    private func runL2Case(_ evalCase: EvalCase) async -> EvalRunRecord {
        // FormattingPipeline.run() builds PipelineMetadata internally from AppState
        let input = TranscriptionInput(
            rawText:       evalCase.rawAsrText,
            languageCode:  evalCase.language,
            targetBundleID: nil
        )

        let result = await pipeline.run(input)

        let finalText     = result.finalText
        let actualCommand = formatCommand(result.extractedCommand)

        // Determine whether the rewrite stage actually ran
        let rewriteStageRan = result.trace.contains {
            $0.stageName.contains("Rewrite") && !$0.wasSkipped
        }

        // Annotate stage traces with execution status
        let evalTraces: [EvalStageTrace] = result.trace.map { trace in
            let status: StageExecutionStatus
            if trace.wasSkipped {
                status = .skipped
            } else {
                status = .ranNormally
            }
            return EvalStageTrace(from: trace, executionStatus: status)
        }

        // Run all hard checks
        var failures = runHardChecks(
            evalCase: evalCase,
            finalText: finalText,
            actualCommand: actualCommand
        )

        // Formatting acceptability check
        let accepted =
            finalText == evalCase.finalExpectedText ||
            evalCase.acceptableVariants.contains(finalText)
        if !accepted && evalCase.rewriteAllowedLevel == "none" {
            // If output is neither expected nor acceptable, check structurally
            // (full structure scoring done in Python; here we flag obvious mismatches)
            if finalText.isEmpty && !evalCase.finalExpectedText.isEmpty {
                failures.append(.formattingPolicyViolation)
            }
        }

        return EvalRunRecord(
            caseID:              evalCase.id,
            contextType:         evalCase.contextType,
            language:            evalCase.language,
            notes:               evalCase.notes,
            formattingMode:      Self.evalMode,
            rawAsrText:          evalCase.rawAsrText,
            literalReference:    evalCase.literalReference,
            finalExpectedText:   evalCase.finalExpectedText,
            acceptableVariants:  evalCase.acceptableVariants,
            protectedTerms:      evalCase.protectedTerms,
            expectedCommand:     evalCase.extractedCommandExpected,
            rewriteAllowedLevel: evalCase.rewriteAllowedLevel,
            finalText:           finalText,
            actualCommand:       actualCommand,
            rewriteStageRan:     rewriteStageRan,
            stageTraces:         evalTraces,
            totalDurationMs:     result.totalDurationMs,
            hardFailureReasons:  failures
        )
    }

    // ─── Assertions ───────────────────────────────────────────────────────

    private func assertNoHardFailures(in records: [EvalRunRecord], category: String) {
        let failures = records.filter { !$0.hardFailureReasons.isEmpty }
        if !failures.isEmpty {
            let detail = failures.map {
                "  \($0.caseID): \($0.hardFailureReasons.map(\.rawValue).joined(separator: ", "))"
            }.joined(separator: "\n")
            XCTFail("[L2/\(category)] \(failures.count) hard failure(s):\n\(detail)")
        }
    }

    // ─── Summary printing ─────────────────────────────────────────────────

    private func printL2Summary(records: [EvalRunRecord], hardFailures: Int) {
        let totalMs = records.map(\.totalDurationMs).reduce(0, +)
        let meanMs = records.isEmpty ? 0.0 : totalMs / Double(records.count)
        print("""
        ── L2 Eval Summary ─────────────────────────────────────────
          Mode:           \(Self.evalMode)
          Category:       \(Self.evalCategory)
          Cases:          \(records.count)
          Hard failures:  \(hardFailures) (\(String(format: "%.1f", Double(hardFailures)/Double(max(records.count,1))*100))%)
          Mean latency:   \(String(format: "%.1f", meanMs))ms
          Output:         Evals/reports/\(Self.runStem)_L2.json
        ────────────────────────────────────────────────────────────
        """)

        // Per-category breakdown
        let byCat = Dictionary(grouping: records, by: \.contextType)
        for (cat, catRecords) in byCat.sorted(by: { $0.key < $1.key }) {
            let fails = catRecords.filter { !$0.hardFailureReasons.isEmpty }.count
            print("  \(cat.padding(toLength: 14, withPad: " ", startingAt: 0)) \(catRecords.count) cases  \(fails) failures")
        }
    }
}

// MARK: - L3: End-to-End Final Text

/// L3 computes a lightweight aggregate over all L2 records.
/// It does not re-run the pipeline — it reads the L2 JSON output.
/// Full composite scoring (with Python metrics) is done by the Python engine.
@MainActor
final class EvalL3Tests: EvalHarnessBase {

    func testL3_CompositeFromL2Output() throws {
        let filename = "\(Self.runStem)_L2.json"
        let url = reportsURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("L2 output not found — run EvalL2Tests first to generate \(filename)")
        }
        let records = try JSONDecoder().decode([EvalRunRecord].self, from: data)
        let hardFailures = records.filter { !$0.hardFailureReasons.isEmpty }.count
        let total = records.count

        // Aggregate exact/acceptable match rate
        let matchCount = records.filter { record in
            record.finalText == record.finalExpectedText ||
            record.acceptableVariants.contains(record.finalText)
        }.count
        let matchRate = total > 0 ? Double(matchCount) / Double(total) : 0.0

        // Informational composite — clearly labelled as non-gate
        let commandCorrect = records.filter { rec in
            let expected = rec.expectedCommand
            let actual = rec.actualCommand == "none" ? nil : rec.actualCommand
            return expected == actual
        }.count
        let commandAccuracy = total > 0 ? Double(commandCorrect) / Double(total) : 0.0

        print("""
        ── L3 End-to-End Summary ────────────────────────────────────
          Cases evaluated: \(total)
          Hard failures:   \(hardFailures)   ← these cannot be gate-passed by any score
          Exact/acceptable match: \(String(format: "%.1f", matchRate * 100))%
          Command accuracy:       \(String(format: "%.1f", commandAccuracy * 100))%
          
          INFORMATIONAL SCORE (not a release gate):
          ~\(String(format: "%.0f", matchRate * 70 + commandAccuracy * 30))/100
          
          Full composite score and per-metric breakdown computed by:
            python Evals/metrics/zphyr_eval.py run --run Evals/reports/\(Self.runStem)_L2.json
        ────────────────────────────────────────────────────────────
        """)

        // L3 gate: hard failures from L2 must be zero
        XCTAssertEqual(hardFailures, 0,
            "L3: \(hardFailures) hard failure(s) propagated from L2. Fix before reviewing composite score.")
    }
}
