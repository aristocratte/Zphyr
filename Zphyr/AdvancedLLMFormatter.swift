//
//  AdvancedLLMFormatter.swift
//  Zphyr
//
//  On-device LLM text formatting using Apple's MLX Swift framework.
//  Model: mlx-community/Qwen3-1.7B-4bit (~1.1 GB, 4-bit quantized)
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
import MLXLLM
import MLXLMCommon

/// Singleton managing on-device Qwen inference for intelligent code formatting.
@Observable
@MainActor
final class AdvancedLLMFormatter {

    static let shared     = AdvancedLLMFormatter()
    static let modelId    = "mlx-community/Qwen3-1.7B-4bit"
    static let modelBytes: Double = 1_100 * 1_024 * 1_024  // ~1.1 GB

    /// Best-effort discovery of the local cache directory for the formatting model.
    static func resolveInstallURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // MLX Swift caches models at ~/Library/Caches/models/<org>/<model>/
        let mlxDirect = home
            .appendingPathComponent("Library/Caches/models/mlx-community/Qwen3-1.7B-4bit")
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
                let isMatch = name.contains("models--mlx-community--qwen3-1.7b-4bit")
                    || name.contains("qwen3-1.7b-4bit")
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

    // Speed tracking
    private var lastFraction: Double = 0
    private var lastSpeedUpdate: Date = .distantPast

    private init() {}

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
        lastFraction      = 0
        lastSpeedUpdate   = Date()

        let task = Task<Void, Never> {
            do {
                let config = ModelConfiguration(id: Self.modelId)
                let result = try await LLMModelFactory.shared.loadContainer(
                    configuration: config,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let p  = progress.fractionCompleted
                            let now = Date()
                            let dt  = now.timeIntervalSince(self.lastSpeedUpdate)
                            if dt >= 0.6 {
                                let dp       = p - self.lastFraction
                                let bps      = (dp * Self.modelBytes) / dt
                                let received = p * Self.modelBytes
                                self.downloadSpeed   = bps > 0 ? Self.formatSpeed(bps) : ""
                                self.downloadedMB    = String(format: "%.0f / 1100 MB",
                                                              received / 1_048_576)
                                self.lastFraction    = p
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
        guard AppState.shared.advancedModeInstalled, container == nil else { return }
        let config = ModelConfiguration(id: Self.modelId)
        container = try? await LLMModelFactory.shared.loadContainer(configuration: config)
        if container != nil {
            log.notice("[AdvancedLLM] loaded from disk cache")
        } else {
            AppState.shared.advancedModeInstalled = false
            log.warning("[AdvancedLLM] cache missing, resetting installed flag")
        }
    }

    /// Unloads the model from memory to free GPU/RAM when not needed.
    func unload() {
        container = nil
        log.notice("[AdvancedLLM] model unloaded")
    }

    /// Deletes all cached model files for Qwen3-1.7B-4bit from disk.
    static func removeModelFromDisk() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // MLX Swift cache: ~/Library/Caches/models/mlx-community/Qwen3-1.7B-4bit/
        let mlxDirect = home
            .appendingPathComponent("Library/Caches/models/mlx-community/Qwen3-1.7B-4bit")
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
                if name.contains("models--mlx-community--qwen3-1.7b-4bit")
                    || name.contains("qwen3-1.7b-4bit") {
                    try? fm.removeItem(at: entry)
                }
            }
        }
    }

    // MARK: - Formatting

    /// Formats code identifiers in `text` using the local LLM.
    /// Returns `nil` on any failure — callers must fall back to `CodeFormatter`.
    func format(_ text: String, style: CodeStyle, constraints: LLMFormattingConstraints) async -> String? {
        guard let container else {
            log.notice("[AdvancedLLM] skipped: model not loaded (container is nil)")
            return nil
        }

        let inputWords = text.split(whereSeparator: \.isWhitespace).count
        log.notice("[AdvancedLLM] generating… input=\(inputWords, privacy: .public) words style=\(String(describing: style), privacy: .public)")
        let startTime = CFAbsoluteTimeGetCurrent()

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

        let forbiddenList = constraints.forbiddenConversationalInsertions.joined(separator: ", ")
        let systemPrompt = """
            Tu es un assistant de FORMATAGE UNIQUEMENT.
            Tu ne dois JAMAIS réécrire, changer, remplacer, ajouter ou supprimer un seul mot du texte original.

            RÈGLES ABSOLUES (respecte-les à la lettre) :

            1. Tu peux UNIQUEMENT faire les modifications suivantes :
               - Ajouter ou corriger la ponctuation (., !, ?, ,, ;, :)
               - Mettre une majuscule au début des phrases
               - Créer des paragraphes (sauts de ligne doubles) quand il y a un changement de sujet clair
               - Transformer les listes parlées en vraies listes avec "- " ou "1. "
               - Formater les noms techniques (variables, fonctions, classes) selon le contexte
               - Corriger uniquement la casse des mots existants (ex: background color red → backgroundColorRed ou background_color_red)

            2. INTERDIT ABSOLU :
               - Ne change AUCUN mot existant (ni orthographe, ni synonyme, ni reformulation)
               - N'ajoute AUCUN mot nouveau
               - Ne supprime AUCUN mot existant (sauf les tics isolés comme "euh", "hum")
               - Ne fais pas de résumé, de commentaire, d'explication
               - Pas de blocs de code, pas de guillemets, pas de markdown autour du résultat

            3. Tu dois sortir EXACTEMENT le texte d'origine, mais avec uniquement les améliorations de formatage ci-dessus.
            4. Tu n'as pas le droit d'ajouter des mots conversationnels comme : \(forbiddenList).

            Exemples :

            Entrée : "je crée la variable background color red euh ensuite je fais une fonction fetch user data voilà voilà en python"
            Sortie : "Je crée la variable background_color_red. Ensuite je fais une fonction fetchUserData en Python."

            Entrée : "premier point je fais le login ensuite je fais le logout enfin je teste"
            Sortie : "- Je fais le login\\n- Je fais le logout\\n- Je teste"

            Style de casse par défaut si le contexte ne l'indique pas : \(defaultStyleHint).

            Réponds UNIQUEMENT avec le texte formaté. Rien d'autre.
            """

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(text)
        ])

        do {
            let lmInput = try await container.prepare(input: userInput)
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
            let result = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let outputWords = result.split(whereSeparator: \.isWhitespace).count
            log.notice("[AdvancedLLM] generated in \(String(format: "%.2f", elapsed), privacy: .public)s output=\(outputWords, privacy: .public) words")
            guard !result.isEmpty else {
                log.notice("[AdvancedLLM] empty result after trimming")
                return nil
            }

            // ── Hallucination guard ──────────────────────────────────────────
            // If the model added significantly more words than the input, it's
            // likely making things up. Reject and let the regex fallback run.
            let tolerance   = max(4, inputWords / 5)   // allow up to +20 % or +4 words
            if outputWords > inputWords + tolerance {
                log.warning("[AdvancedLLM] hallucination guard: word count (in=\(inputWords) out=\(outputWords))")
                return nil
            }

            // ── Foreign script guard ─────────────────────────────────────────
            // Detect characters from scripts absent in the input (e.g. Thai,
            // CJK, Cyrillic injected when input is Latin).
            if Self.containsForeignScripts(input: text, output: result) {
                log.warning("[AdvancedLLM] hallucination guard: foreign scripts detected")
                return nil
            }

            // ── Repetition guard ─────────────────────────────────────────────
            // Detect degenerate repeated token sequences (e.g. "à¹ĭà¹ĭà¹ĭà¹ĭ")
            if Self.containsExcessiveRepetition(result) {
                log.warning("[AdvancedLLM] hallucination guard: excessive repetition")
                return nil
            }

            let sourceTokens = tokenSet(text)
            let candidateTokens = tokenSet(result)
            let forbiddenInsertions = constraints.forbiddenConversationalInsertions
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }
                .filter { candidateTokens.contains($0) && !sourceTokens.contains($0) }
            if !forbiddenInsertions.isEmpty {
                log.warning("[AdvancedLLM] forbidden insertion guard triggered: \(forbiddenInsertions.joined(separator: ","), privacy: .public)")
                return nil
            }

            return result
        } catch {
            log.error("[AdvancedLLM] generate failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func formatSpeed(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        return String(format: "%.0f KB/s", bps / 1_024)
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
    static let modelId         = "mlx-community/Qwen3-1.7B-4bit"
    static func resolveInstallURL() -> URL? { nil }
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = "⚠️ Ajoutez mlx-swift-lm dans Xcode (Branch: main, produits: MLXLLM + MLXLMCommon)."
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    private init() {}
    func installModel()    async {}
    func cancelInstall()         {}
    func loadIfInstalled() async {}
    func unload()                {}
    static func removeModelFromDisk() {}
    func format(_ text: String, style: CodeStyle, constraints: LLMFormattingConstraints) async -> String? { nil }
}

#endif
