//
//  AdvancedLLMFormatter.swift
//  Zphyr
//
//  On-device LLM code formatting using Apple's MLX Swift framework.
//  Model: mlx-community/Qwen2.5-1.5B-Instruct-4bit (~900 MB, 4-bit quantized)
//  Runs on Apple Silicon via Metal — zero network latency after initial download.
//
//  ─── ONE-TIME SETUP IN XCODE ────────────────────────────────────────────────
//  File → Add Package Dependencies
//  URL    : https://github.com/ml-explore/mlx-swift-examples
//  Branch : main   (or the latest tagged release)
//  Products to add to the Zphyr target: MLXLLM   MLXLMCommon
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

    static let shared  = AdvancedLLMFormatter()
    static let modelId = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    // MARK: - Observable state (drives onboarding + settings UI)
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = nil

    private var container: ModelContainer?
    private let log = Logger(subsystem: "com.zphyr.app", category: "AdvancedLLM")

    private init() {}

    // MARK: - Installation

    /// Downloads the model from HuggingFace and loads it into memory.
    /// Sets `AppState.shared.advancedModeInstalled = true` on success.
    func installModel() async {
        guard !isInstalling else { return }
        isInstalling     = true
        installError     = nil
        downloadProgress = 0

        do {
            let config = ModelConfiguration(id: Self.modelId)
            container = try await LLMModelFactory.shared.loadContainer(
                configuration: config,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }
            )
            downloadProgress = 1.0
            AppState.shared.advancedModeInstalled = true
            log.notice("[AdvancedLLM] installation complete")
        } catch {
            installError = error.localizedDescription
            log.error("[AdvancedLLM] install error: \(error.localizedDescription)")
        }
        isInstalling = false
    }

    /// Silently loads an already-downloaded model from the local cache (no network).
    func loadIfInstalled() async {
        guard AppState.shared.advancedModeInstalled, container == nil else { return }
        let config = ModelConfiguration(id: Self.modelId)
        container = try? await LLMModelFactory.shared.loadContainer(configuration: config)
        if container != nil {
            log.notice("[AdvancedLLM] loaded from disk cache")
        } else {
            // Cache missing — reset flag so user can reinstall
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

        let styleName: String
        switch style {
        case .camel:     styleName = "camelCase"
        case .snake:     styleName = "snake_case"
        case .pascal:    styleName = "PascalCase"
        case .screaming: styleName = "SCREAMING_SNAKE_CASE"
        case .kebab:     styleName = "kebab-case"
        }

        // Ultra-short system prompt to keep token overhead minimal
        let system = "Reformat code identifiers to \(styleName). Keep all other words exactly. Return only the rewritten text."
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": text]
        ]

        do {
            let result = try await container.perform { context in
                let input = try await context.processor.prepare(
                    input: .init(messages: messages)
                )
                return try MLXLMCommon.generate(
                    input: input,
                    parameters: .init(temperature: 0, maxTokens: 150),
                    context: context
                ) { _ in .more }
            }
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            log.error("[AdvancedLLM] generate failed: \(error.localizedDescription)")
            return nil
        }
    }
}

#else
// ─── Compile-time stub ───────────────────────────────────────────────────────
// This stub is active when the mlx-swift-examples package has not yet been
// added to the Xcode project. All formatter calls return nil → CodeFormatter fallback.
// Remove this #else block after you add the package in Xcode.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class AdvancedLLMFormatter {
    static let shared          = AdvancedLLMFormatter()
    static let modelId         = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = "⚠️ Ajoutez le package mlx-swift-examples dans Xcode."
    private init() {}
    func installModel()    async { installError = "Package MLX non ajouté dans Xcode." }
    func loadIfInstalled() async {}
    func unload()                {}
    func format(_ text: String, style: CodeStyle) async -> String? { nil }
}

#endif
