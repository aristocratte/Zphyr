//
//  AdvancedLLMFormatter.swift
//  Zphyr
//
//  On-device LLM code formatting using Apple's MLX Swift framework.
//  Model: mlx-community/Qwen3.5-0.8B-4bit (~625 MB, 4-bit quantized)
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

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// Singleton managing on-device Qwen inference for intelligent code formatting.
@Observable
@MainActor
final class AdvancedLLMFormatter {

    static let shared     = AdvancedLLMFormatter()
    static let modelId    = "mlx-community/Qwen3.5-0.8B-4bit"
    static let modelBytes: Double = 625 * 1_024 * 1_024   // ~625 MB

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
                                self.downloadedMB    = String(format: "%.0f / 625 MB",
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

    // MARK: - Formatting

    /// Formats code identifiers in `text` using the local LLM.
    /// Returns `nil` on any failure — callers must fall back to `CodeFormatter`.
    func format(_ text: String, style: CodeStyle) async -> String? {
        guard let container else { return nil }

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
                parameters: GenerateParameters(maxTokens: 512, temperature: 0)
            )
            var output = ""
            for await generation in stream {
                if case .chunk(let chunk) = generation { output += chunk }
            }
            let result = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !result.isEmpty else { return nil }

            // ── Hallucination guard ──────────────────────────────────────────
            // If the model added significantly more words than the input, it's
            // likely making things up. Reject and let the regex fallback run.
            let inputWords  = text.split(whereSeparator: \.isWhitespace).count
            let outputWords = result.split(whereSeparator: \.isWhitespace).count
            let tolerance   = max(4, inputWords / 5)   // allow up to +20 % or +4 words
            if outputWords > inputWords + tolerance {
                log.warning("[AdvancedLLM] hallucination guard triggered (in=\(inputWords) out=\(outputWords)), using regex fallback")
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
    static let modelId         = "mlx-community/Qwen3.5-0.8B-4bit"
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
    func format(_ text: String, style: CodeStyle) async -> String? { nil }
}

#endif
