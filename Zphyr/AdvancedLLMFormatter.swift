//
//  AdvancedLLMFormatter.swift
//  Zphyr
//
//  On-device LLM text formatting using Apple's MLX Swift framework.
//  Model: arhesstide/zphyr_qwen_v1-MLX-4bit (fine-tuned Qwen3-1.7B, 4-bit quantized)
//  Runs on Apple Silicon via Metal — zero network latency after initial download.
//
//  ─── ONE-TIME SETUP IN XCODE ────────────────────────────────────────────────
//  File → Add Package Dependencies
//  URL    : https://github.com/ml-explore/mlx-swift-lm
//  Branch : main
//  Products to add to the Zphyr target: MLXLLM   MLXLMCommon
//  (mlx-swift-examples ne contient PAS MLXLLM — utiliser mlx-swift-lm)
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import os

struct LLMFormattingConstraints: Sendable {
    let maxTokens: Int
    let temperature: Float
    let forbiddenConversationalInsertions: [String]

    static let strict = LLMFormattingConstraints(
        maxTokens: 512,
        temperature: 0,
        forbiddenConversationalInsertions: [
            "ok", "okay", "yes", "yeah", "sure", "please", "thanks", "thank", "bonjour",
            "salut", "merci", "hello", "hi", "hola", "ciao", "voila", "voilà"
        ]
    )
}

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon

/// Singleton managing on-device Qwen inference for intelligent code formatting.
@Observable
@MainActor
final class AdvancedLLMFormatter {

    private enum PromptPreparationPath: String {
        case rawAlpaca = "alpaca-raw"
        case chatTemplate = "chat-template"
    }

    struct SanitizedGenerationOutput: Sendable {
        let rawText: String
        let cleanedText: String?
        let fallbackReason: String?
        let strippedReasoningTags: Bool
    }

    static let shared     = AdvancedLLMFormatter()
    static let modelId    = "arhesstide/zphyr_qwen_v1-MLX-4bit"
    static let modelBytes: Double = 1_100 * 1_024 * 1_024  // ~1.1 GB
    static var overrideInstallURL: URL?
    private static let extraStopTokens: Set<String> = ["<think>", "</think>"]

    private static func preferredExplicitInstallURL() -> URL? {
        if let overrideInstallURL {
            return overrideInstallURL
        }
        if let overridePath = ProcessInfo.processInfo.environment["ZPHYR_FORMATTER_MODEL_PATH"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        return nil
    }

    /// Best-effort discovery of the local cache directory for the formatting model.
    static func resolveInstallURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        if let explicitURL = preferredExplicitInstallURL() {
            return directoryContainsModelFiles(explicitURL) ? explicitURL : nil
        }

        // MLX Swift caches models at ~/Library/Caches/models/<org>/<model>/
        let mlxDirect = home
            .appendingPathComponent("Library/Caches/models/arhesstide/zphyr_qwen_v1-MLX-4bit")
        if fm.fileExists(atPath: mlxDirect.path),
           directoryContainsModelFiles(mlxDirect) {
            return mlxDirect
        }

        // Fallback: HuggingFace Python-style cache roots
        let roots = [
            home.appendingPathComponent(".cache/huggingface/hub"),
            home.appendingPathComponent("Library/Caches/huggingface/hub"),
            home.appendingPathComponent("Library/Application Support/huggingface/hub")
        ]

        var candidates: [URL] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                let isMatch = name.contains("models--arhesstide--zphyr_qwen_v1-mlx-4bit")
                    || name.contains("zphyr_qwen_v1-mlx-4bit")
                guard isMatch else { continue }

                let snapshots = entry.appendingPathComponent("snapshots")
                if fm.fileExists(atPath: snapshots.path),
                   let snapshotEntries = try? fm.contentsOfDirectory(
                    at: snapshots,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                   ),
                   !snapshotEntries.isEmpty {
                    if let latestSnapshot = snapshotEntries.max(by: {
                        let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return lhs < rhs
                    }), Self.directoryContainsModelFiles(latestSnapshot) {
                        candidates.append(latestSnapshot)
                        continue
                    }
                }

                if Self.directoryContainsModelFiles(entry) {
                    candidates.append(entry)
                }
            }
        }

        return candidates.max(by: {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        })
    }

    /// Returns `true` only when the directory contains actual model weight files.
    private static func directoryContainsModelFiles(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        let hasConfig = contents.contains { $0.lastPathComponent == "config.json" }
        let hasWeights = contents.contains { $0.pathExtension == "safetensors" }
        return hasConfig && hasWeights
    }

    // MARK: - Observable state (drives onboarding + settings UI)
    var downloadProgress: Double  = 0
    var isInstalling: Bool        = false
    var installError: String?     = nil
    var downloadSpeed: String     = ""   // e.g. "3.2 MB/s"
    var downloadedMB: String      = ""   // e.g. "312 / 625 MB"

    private var container: ModelContainer?
    private var installTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.zphyr.app", category: "AdvancedLLM")
    var isModelLoaded: Bool { container != nil }

        // Speed tracking
    private var lastBytes: Int64 = 0
    private var lastSpeedUpdate: Date = .distantPast

    private init() {
        // Reconcile UserDefaults flag with actual disk state on startup.
        let installedOnDisk = Self.resolveInstallURL() != nil
        if AppState.shared.advancedModeInstalled != installedOnDisk {
            AppState.shared.advancedModeInstalled = installedOnDisk
        }
    }

    // MARK: - Installation

    /// Downloads the model from HuggingFace and loads it into memory.
    /// Sets `AppState.shared.advancedModeInstalled = true` on success.
    func installModel() async {
        guard !isInstalling else { return }
        isInstalling      = true
        installError      = nil
        downloadProgress  = 0
        downloadSpeed     = ""
        downloadedMB      = ""
        lastBytes         = 0
        lastSpeedUpdate   = Date()

        let task = Task<Void, Never> {
            do {
                let config = ModelConfiguration(id: Self.modelId)
                let result = try await LLMModelFactory.shared.loadContainer(
                    configuration: config,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let p   = progress.fractionCompleted
                            let now = Date()
                            let dt  = now.timeIntervalSince(self.lastSpeedUpdate)
                            if dt >= 0.6 {
                                // Use real bytes from Progress if available, else estimate
                                let totalBytes = progress.totalUnitCount > 0
                                    ? progress.totalUnitCount
                                    : Int64(Self.modelBytes)
                                let completedBytes = progress.completedUnitCount > 0
                                    ? progress.completedUnitCount
                                    : Int64(p * Self.modelBytes)
                                let deltaBytes = completedBytes - self.lastBytes
                                let bps        = deltaBytes > 0 ? Double(deltaBytes) / dt : 0
                                self.downloadSpeed   = bps > 0 ? Self.formatSpeed(bps) : ""
                                self.downloadedMB    = String(
                                    format: "%.0f / %.0f MB",
                                    Double(completedBytes) / 1_048_576,
                                    Double(totalBytes) / 1_048_576
                                )
                                self.lastBytes       = completedBytes
                                self.lastSpeedUpdate = now
                            }
                            self.downloadProgress = p
                        }
                    }
                )
                if !Task.isCancelled {
                    self.container        = result
                    self.downloadProgress = 1.0
                    self.downloadSpeed    = ""
                    self.downloadedMB     = ""
                    AppState.shared.advancedModeInstalled = true
                    self.log.notice("[AdvancedLLM] installation complete")
                }
            } catch is CancellationError {
                self.log.notice("[AdvancedLLM] install cancelled")
            } catch {
                if !Task.isCancelled {
                    self.installError = error.localizedDescription
                    self.log.error("[AdvancedLLM] install error: \(error.localizedDescription)")
                }
            }
            self.isInstalling  = false
            self.installTask   = nil
        }
        installTask = task
        await task.value
    }

    /// Cancels an in-progress installation.
    func cancelInstall() {
        installTask?.cancel()
        installTask      = nil
        isInstalling     = false
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""
        log.notice("[AdvancedLLM] install cancelled by user")
    }

    /// Silently loads an already-downloaded model from the local cache (no network).
    func loadIfInstalled() async {
        guard container == nil else { return }
        guard let installURL = Self.resolveInstallURL() else {
            if AppState.shared.advancedModeInstalled {
                AppState.shared.advancedModeInstalled = false
            }
            if let explicitURL = Self.preferredExplicitInstallURL() {
                log.error("[AdvancedLLM] load skipped: explicit model path invalid or incomplete: \(explicitURL.path, privacy: .public)")
            } else {
                log.notice("[AdvancedLLM] load skipped: model not present on disk")
            }
            return
        }
        if !AppState.shared.advancedModeInstalled {
            AppState.shared.advancedModeInstalled = true
        }
        let configuration: ModelConfiguration
        if Self.preferredExplicitInstallURL() != nil {
            configuration = ModelConfiguration(
                directory: installURL,
                extraEOSTokens: Self.extraStopTokens
            )
            log.notice("[AdvancedLLM] loading explicit local model from \(installURL.path, privacy: .public)")
        } else {
            configuration = ModelConfiguration(
                id: Self.modelId,
                extraEOSTokens: Self.extraStopTokens
            )
            log.notice("[AdvancedLLM] loading cached model using id=\(Self.modelId, privacy: .public) resolvedPath=\(installURL.path, privacy: .public)")
        }

        do {
            container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        } catch {
            container = nil
            AppState.shared.advancedModeInstalled = false
            log.error("[AdvancedLLM] load failed from \(installURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        if container != nil {
            log.notice("[AdvancedLLM] loaded model successfully from \(installURL.path, privacy: .public)")
        } else {
            AppState.shared.advancedModeInstalled = false
            log.warning("[AdvancedLLM] load returned nil container for path \(installURL.path, privacy: .public)")
        }
    }

    /// Unloads the model from memory to free GPU/RAM when not needed.
    func unload() {
        container = nil
        log.notice("[AdvancedLLM] model unloaded")
    }

    /// Deletes all cached model files for zphyr_qwen_v1-MLX-4bit from disk.
    static func removeModelFromDisk() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // MLX Swift cache: ~/Library/Caches/models/arhesstide/zphyr_qwen_v1-MLX-4bit/
        let mlxDirect = home
            .appendingPathComponent("Library/Caches/models/arhesstide/zphyr_qwen_v1-MLX-4bit")
        if fm.fileExists(atPath: mlxDirect.path) {
            try? fm.removeItem(at: mlxDirect)
        }

        // HuggingFace Python-style caches
        let roots = [
            home.appendingPathComponent(".cache/huggingface/hub"),
            home.appendingPathComponent("Library/Caches/huggingface/hub"),
            home.appendingPathComponent("Library/Application Support/huggingface/hub")
        ]
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.contains("models--arhesstide--zphyr_qwen_v1-mlx-4bit")
                    || name.contains("zphyr_qwen_v1-mlx-4bit") {
                    try? fm.removeItem(at: entry)
                }
            }
        }
    }

    // MARK: - Formatting

    /// Formats code identifiers in `text` using the local LLM.
    /// Returns `nil` on any failure — callers must fall back to `CodeFormatter`.
    func format(_ text: String, style: CodeStyle, constraints: LLMFormattingConstraints) async -> String? {
        if container == nil, AppState.shared.advancedModeInstalled {
            log.notice("[AdvancedLLM] container missing while advancedModeInstalled=true; trying lazy load from disk cache")
            await loadIfInstalled()
        }

        guard let container else {
            log.notice(
                "[AdvancedLLM] skipped: model not loaded (container=nil advancedModeInstalled=\(AppState.shared.advancedModeInstalled, privacy: .public))"
            )
            return nil
        }

        let inputWords = text.split(whereSeparator: \.isWhitespace).count
        log.notice(
            "[AdvancedLLM] generating… input=\(inputWords, privacy: .public) words style=\(String(describing: style), privacy: .public) preview=\"\(Self.debugPreview(text), privacy: .public)\""
        )
        let startTime = CFAbsoluteTimeGetCurrent()
        var promptMode = "unprepared"

        // Default style hint appended at end so the LLM has a fallback when
        // context doesn't specify a language/convention.
        let defaultStyleHint: String
        switch style {
        case .camel:     defaultStyleHint = "camelCase"
        case .snake:     defaultStyleHint = "snake_case"
        case .pascal:    defaultStyleHint = "PascalCase"
        case .screaming: defaultStyleHint = "SCREAMING_SNAKE_CASE"
        case .kebab:     defaultStyleHint = "kebab-case"
        }

        let systemPrompt = """
            Return only the final formatted text.
            No reasoning. No explanation. No `<think>` tags. No XML or HTML-like tags.
            No markdown unless the final text itself requires a list or code block.
            Preserve meaning, language, URLs, paths, code, package names, versions, and technical tokens exactly.
            Apply minimal formatting only: punctuation, capitalization, spacing, explicit spoken punctuation, and obvious ASR cleanup.
            For dictated identifiers, use \(defaultStyleHint) only when the input clearly asks for an identifier form.
            If uncertain, make the smallest safe change and never add extra words.
            """

        do {
            let prepared = try await prepareInput(
                for: text,
                systemPrompt: systemPrompt,
                container: container
            )
            promptMode = prepared.path.rawValue
            let lmInput = prepared.input
#if DEBUG
            let tokenShape = lmInput.text.tokens.shape
            let tokenCount = tokenShape.last ?? 0
            log.notice(
                "[AdvancedLLM] prepared input mode=\(prepared.path.rawValue, privacy: .public) tokenShape=\(String(describing: tokenShape), privacy: .public) tokenCount=\(tokenCount, privacy: .public) hasMask=\(lmInput.text.mask != nil, privacy: .public)"
            )
#endif
            log.notice(
                "[AdvancedLLM] submit generation mode=\(promptMode, privacy: .public) maxTokens=\(constraints.maxTokens, privacy: .public) temperature=\(constraints.temperature, privacy: .public)"
            )
            let stream  = try await container.generate(
                input: lmInput,
                parameters: GenerateParameters(
                    maxTokens: constraints.maxTokens,
                    temperature: constraints.temperature
                )
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let chunk) = generation { output += chunk }
            }
            let rawResult = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            log.notice(
                "[AdvancedLLM] raw output mode=\(promptMode, privacy: .public) in \(String(format: "%.2f", elapsed), privacy: .public)s preview=\"\(Self.debugPreview(rawResult), privacy: .public)\""
            )
            let sanitized = Self.sanitizeGeneratedOutput(rawResult)
            if sanitized.strippedReasoningTags {
                log.notice(
                    "[AdvancedLLM] cleaned reasoning tags mode=\(promptMode, privacy: .public) cleanedPreview=\"\(Self.debugPreview(sanitized.cleanedText ?? ""), privacy: .public)\""
                )
            } else {
                log.notice(
                    "[AdvancedLLM] cleaned output mode=\(promptMode, privacy: .public) preview=\"\(Self.debugPreview(sanitized.cleanedText ?? ""), privacy: .public)\""
                )
            }
            guard let result = sanitized.cleanedText else {
                log.warning(
                    "[AdvancedLLM] rejecting output mode=\(promptMode, privacy: .public) reason=\(sanitized.fallbackReason ?? "unknown", privacy: .public) rawPreview=\"\(Self.debugPreview(sanitized.rawText), privacy: .public)\""
                )
                return nil
            }

            let outputWords = result.split(whereSeparator: \.isWhitespace).count
            guard !result.isEmpty else {
                log.notice("[AdvancedLLM] empty result after trimming mode=\(promptMode, privacy: .public)")
                return nil
            }

            // ── Hallucination guard ──────────────────────────────────────────
            // If the model added significantly more words than the input, it's
            // likely making things up. Reject and let the regex fallback run.
            let tolerance   = max(4, inputWords / 5)   // allow up to +20 % or +4 words
            if outputWords > inputWords + tolerance {
                log.warning("[AdvancedLLM] hallucination guard mode=\(promptMode, privacy: .public): word count (in=\(inputWords) out=\(outputWords))")
                return nil
            }

            // ── Foreign script guard ─────────────────────────────────────────
            // Detect characters from scripts absent in the input (e.g. Thai,
            // CJK, Cyrillic injected when input is Latin).
            if Self.containsForeignScripts(input: text, output: result) {
                log.warning("[AdvancedLLM] hallucination guard mode=\(promptMode, privacy: .public): foreign scripts detected")
                return nil
            }

            // ── Repetition guard ─────────────────────────────────────────────
            // Detect degenerate repeated token sequences (e.g. "à¹ĭà¹ĭà¹ĭà¹ĭ")
            if Self.containsExcessiveRepetition(result) {
                log.warning("[AdvancedLLM] hallucination guard mode=\(promptMode, privacy: .public): excessive repetition")
                return nil
            }

            let sourceTokens = tokenSet(text)
            let candidateTokens = tokenSet(result)
            let forbiddenInsertions = constraints.forbiddenConversationalInsertions
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }
                .filter { candidateTokens.contains($0) && !sourceTokens.contains($0) }
            if !forbiddenInsertions.isEmpty {
                log.warning("[AdvancedLLM] forbidden insertion guard mode=\(promptMode, privacy: .public) triggered: \(forbiddenInsertions.joined(separator: ","), privacy: .public)")
                return nil
            }

            return result
        } catch {
            log.error("[AdvancedLLM] generate failed mode=\(promptMode, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func formatSpeed(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        return String(format: "%.0f KB/s", bps / 1_024)
    }

    private func prepareInput(
        for text: String,
        systemPrompt: String,
        container: ModelContainer
    ) async throws -> (input: LMInput, path: PromptPreparationPath) {
        if await shouldUseRawAlpacaPrompt(container: container) {
            let prompt = Self.alpacaPrompt(for: text)
#if DEBUG
            log.notice(
                "[AdvancedLLM] prepare input mode=\(PromptPreparationPath.rawAlpaca.rawValue, privacy: .public) promptChars=\(prompt.count, privacy: .public) userChars=\(text.count, privacy: .public) promptPreview=\"\(Self.debugPreview(prompt), privacy: .public)\""
            )
#endif
            let tokens = await container.encode(prompt)
            return (LMInput(tokens: MLXArray(tokens)), .rawAlpaca)
        }

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(text)
        ])
#if DEBUG
        log.notice(
            "[AdvancedLLM] prepare input mode=\(PromptPreparationPath.chatTemplate.rawValue, privacy: .public) messages=2 systemChars=\(systemPrompt.count, privacy: .public) userChars=\(text.count, privacy: .public) systemPreview=\"\(Self.debugPreview(systemPrompt), privacy: .public)\" userPreview=\"\(Self.debugPreview(text), privacy: .public)\""
        )
#endif
        let input = try await container.prepare(input: userInput)
        return (input, .chatTemplate)
    }

    private func shouldUseRawAlpacaPrompt(container: ModelContainer) async -> Bool {
        if Self.preferredExplicitInstallURL() != nil {
            return true
        }
        let configuration = await container.configuration
        let normalizedName = configuration.name.lowercased()
        return normalizedName == Self.modelId.lowercased()
            || normalizedName.contains("zphyr_qwen_v1-mlx-4bit")
    }

    nonisolated static func alpacaPrompt(for text: String) -> String {
        [
            "Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.",
            "Instruction:",
            "Return only the final formatted text. No reasoning. No explanation. No <think> tags. No XML or HTML-like tags. Preserve meaning and technical tokens exactly. Apply only the minimal formatting needed.",
            "",
            "Input:",
            text,
            "",
            "Response:"
        ].joined(separator: "\n")
    }

    private func tokenSet(_ text: String) -> Set<String> {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        return Set(
            normalized
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        )
    }

    nonisolated static func sanitizeGeneratedOutput(
        _ rawOutput: String,
        requiredTerms: [String] = []
    ) -> SanitizedGenerationOutput {
        let trimmedRaw = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return SanitizedGenerationOutput(
                rawText: trimmedRaw,
                cleanedText: nil,
                fallbackReason: "empty_raw_output",
                strippedReasoningTags: false
            )
        }

        var strippedReasoningTags = false
        var cleaned = trimmedRaw

        if cleaned.range(of: #"(?is)<think>.*?</think>"#, options: .regularExpression) != nil {
            strippedReasoningTags = true
            cleaned = cleaned.replacingOccurrences(
                of: #"(?is)<think>.*?</think>"#,
                with: " ",
                options: .regularExpression
            )
        }

        if cleaned.range(of: #"(?i)</?think>"#, options: .regularExpression) != nil {
            strippedReasoningTags = true
            cleaned = cleaned.replacingOccurrences(
                of: #"(?i)</?think>"#,
                with: " ",
                options: .regularExpression
            )
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return SanitizedGenerationOutput(
                rawText: trimmedRaw,
                cleanedText: nil,
                fallbackReason: "empty_after_reasoning_cleanup",
                strippedReasoningTags: strippedReasoningTags
            )
        }

        if cleaned.range(of: #"<[A-Za-z/][^>]*>"#, options: .regularExpression) != nil {
            return SanitizedGenerationOutput(
                rawText: trimmedRaw,
                cleanedText: nil,
                fallbackReason: "xml_like_tag_contamination",
                strippedReasoningTags: strippedReasoningTags
            )
        }

        if !cleaned.contains(where: { $0.isLetter || $0.isNumber }) {
            return SanitizedGenerationOutput(
                rawText: trimmedRaw,
                cleanedText: nil,
                fallbackReason: "non_substantive_output",
                strippedReasoningTags: strippedReasoningTags
            )
        }

        let missingTerms = requiredTerms.filter { !$0.isEmpty && !cleaned.contains($0) }
        if !missingTerms.isEmpty {
            return SanitizedGenerationOutput(
                rawText: trimmedRaw,
                cleanedText: nil,
                fallbackReason: "missing_required_terms",
                strippedReasoningTags: strippedReasoningTags
            )
        }

        return SanitizedGenerationOutput(
            rawText: trimmedRaw,
            cleanedText: cleaned,
            fallbackReason: nil,
            strippedReasoningTags: strippedReasoningTags
        )
    }

    // MARK: - Hallucination detection helpers

    /// Returns the set of broad script categories present in a string.
    private static func scriptSet(_ text: String) -> Set<String> {
        var scripts = Set<String>()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v < 0x0080 { scripts.insert("Latin"); continue }
            // Latin Extended
            if (0x0080...0x024F).contains(v) || (0x1E00...0x1EFF).contains(v) { scripts.insert("Latin"); continue }
            // Cyrillic
            if (0x0400...0x04FF).contains(v) || (0x0500...0x052F).contains(v) { scripts.insert("Cyrillic"); continue }
            // Arabic
            if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) { scripts.insert("Arabic"); continue }
            // Thai
            if (0x0E00...0x0E7F).contains(v) { scripts.insert("Thai"); continue }
            // CJK
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
                || (0x3000...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v)
                || (0xFF00...0xFFEF).contains(v) { scripts.insert("CJK"); continue }
            // Hangul
            if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) { scripts.insert("Hangul"); continue }
            // Devanagari
            if (0x0900...0x097F).contains(v) { scripts.insert("Devanagari"); continue }
        }
        return scripts
    }

    /// Detects foreign scripts in output that were not present in input.
    private static func containsForeignScripts(input: String, output: String) -> Bool {
        let inputScripts = scriptSet(input)
        let outputScripts = scriptSet(output)
        let foreignScripts = outputScripts.subtracting(inputScripts)
        return !foreignScripts.isEmpty
    }

    /// Detects degenerate repetition (same 2–6 char sequence repeated 4+ times).
    private static func containsExcessiveRepetition(_ text: String) -> Bool {
        let pattern = #"(.{2,6})\1{3,}"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func debugPreview(_ text: String, limit: Int = 320) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else { return normalized }
        let remaining = normalized.count - limit
        return "\(normalized.prefix(limit))…(+\(remaining) chars)"
    }
}

#else
// ─── Compile-time stub ───────────────────────────────────────────────────────
// This stub is active when the mlx-swift-lm package has not yet been
// added to the Xcode project. All formatter calls return nil → CodeFormatter fallback.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class AdvancedLLMFormatter {
    static let shared          = AdvancedLLMFormatter()
    static let modelId         = "arhesstide/zphyr_qwen_v1-MLX-4bit"
    static var overrideInstallURL: URL?
    struct SanitizedGenerationOutput: Sendable {
        let rawText: String
        let cleanedText: String?
        let fallbackReason: String?
        let strippedReasoningTags: Bool
    }
    static func resolveInstallURL() -> URL? { nil }
    nonisolated static func sanitizeGeneratedOutput(
        _ rawOutput: String,
        requiredTerms: [String] = []
    ) -> SanitizedGenerationOutput {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return SanitizedGenerationOutput(
            rawText: trimmed,
            cleanedText: trimmed.isEmpty ? nil : trimmed,
            fallbackReason: trimmed.isEmpty ? "empty_raw_output" : nil,
            strippedReasoningTags: false
        )
    }
    nonisolated static func alpacaPrompt(for text: String) -> String {
        [
            "Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.",
            "Instruction:",
            "Return only the final formatted text. No reasoning. No explanation. No <think> tags. No XML or HTML-like tags. Preserve meaning and technical tokens exactly. Apply only the minimal formatting needed.",
            "",
            "Input:",
            text,
            "",
            "Response:"
        ].joined(separator: "\n")
    }
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = "⚠️ Ajoutez mlx-swift-lm dans Xcode (Branch: main, produits: MLXLLM + MLXLMCommon)."
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    var isModelLoaded: Bool      = false
    private let log = Logger(subsystem: "com.zphyr.app", category: "AdvancedLLMStub")
    private init() {}
    func installModel()    async {}
    func cancelInstall()         {}
    func loadIfInstalled() async {}
    func unload()                {}
    static func removeModelFromDisk() {}
    func format(_ text: String, style: CodeStyle, constraints: LLMFormattingConstraints) async -> String? {
        log.error("[AdvancedLLMStub] format called but MLXLLM is unavailable; returning nil")
        return nil
    }
}

#endif
