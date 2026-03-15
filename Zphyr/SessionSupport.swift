import Foundation
import AppKit

enum SessionPresentation {
    static func pipelineDecisionMessage(
        _ decision: PipelineDecision?,
        languageCode: String
    ) -> String {
        guard let decision else {
            return L10n.ui(for: languageCode, fr: "Aucune décision", en: "No decision", es: "Sin decisión", zh: "无决策", ja: "決定なし", ru: "Нет решения")
        }
        switch decision {
        case .commandShortCircuit:
            return L10n.ui(for: languageCode, fr: "Commande détectée : pipeline écourtée", en: "Command detected: pipeline short-circuited", es: "Comando detectado: pipeline acortada", zh: "检测到命令：管线提前结束", ja: "コマンド検出：パイプラインを短絡", ru: "Команда обнаружена: пайплайн прерван")
        case .deterministicOnly:
            return L10n.ui(for: languageCode, fr: "Sortie déterministe", en: "Deterministic output", es: "Salida determinista", zh: "确定性输出", ja: "決定論的出力", ru: "Детерминированный вывод")
        case .acceptedBaselineRound2:
            return L10n.ui(for: languageCode, fr: "Réécriture acceptée", en: "Rewrite accepted", es: "Reescritura aceptada", zh: "重写已接受", ja: "リライトを採用", ru: "Переписывание принято")
        case .deterministicFallback:
            return L10n.ui(for: languageCode, fr: "Fallback déterministe", en: "Deterministic fallback", es: "Fallback determinista", zh: "确定性回退", ja: "決定論的フォールバック", ru: "Детерминированный откат")
        }
    }

    static func fallbackMessage(
        pipelineFallbackReason: FallbackReason?,
        insertionFallbackReason: FallbackReason?,
        outputProfile: OutputProfile,
        languageCode: String
    ) -> String? {
        let reason = insertionFallbackReason ?? pipelineFallbackReason
        switch reason {
        case .none:
            return nil
        case .some(.profileRewriteDisabledVerbatim):
            return L10n.ui(for: languageCode, fr: "Réécriture ignorée : profil verbatim", en: "Rewrite skipped: verbatim profile", es: "Reescritura ignorada: perfil verbatim", zh: "已跳过重写：verbatim 配置", ja: "リライトを無効化：verbatim プロファイル", ru: "Переписывание пропущено: профиль verbatim")
        case .some(.profileProtectedTermsRejected):
            return L10n.ui(for: languageCode, fr: "Fallback déterministe : terme protégé perdu", en: "Deterministic fallback: protected term lost", es: "Fallback determinista: término protegido perdido", zh: "确定性回退：保护术语丢失", ja: "決定論的フォールバック：保護用語が失われました", ru: "Детерминированный откат: потерян защищенный термин")
        case .some(.profileValidationRejected):
            switch outputProfile {
            case .technical:
                return L10n.ui(for: languageCode, fr: "Fallback déterministe : règle du profil technique", en: "Deterministic fallback: technical profile rule", es: "Fallback determinista: regla del perfil técnico", zh: "确定性回退：technical 配置规则", ja: "決定論的フォールバック：technical プロファイル規則", ru: "Детерминированный откат: правило technical-профиля")
            case .email:
                return L10n.ui(for: languageCode, fr: "Fallback déterministe : règle du profil email", en: "Deterministic fallback: email profile rule", es: "Fallback determinista: regla del perfil email", zh: "确定性回退：email 配置规则", ja: "決定論的フォールバック：email プロファイル規則", ru: "Детерминированный откат: правило email-профиля")
            default:
                return L10n.ui(for: languageCode, fr: "Fallback déterministe : règle du profil actif", en: "Deterministic fallback: active profile rule", es: "Fallback determinista: regla del perfil activo", zh: "确定性回退：当前配置规则", ja: "決定論的フォールバック：アクティブプロファイル規則", ru: "Детерминированный откат: правило активного профиля")
            }
        case .some(.rewriteSkippedMode):
            return L10n.ui(for: languageCode, fr: "Réécriture ignorée : mode trigger", en: "Rewrite skipped: trigger mode", es: "Reescritura ignorada: modo trigger", zh: "已跳过重写：trigger 模式", ja: "リライトを無効化：trigger モード", ru: "Переписывание пропущено: режим trigger")
        case .some(.rewriteModelUnavailable):
            return L10n.ui(for: languageCode, fr: "Réécriture ignorée : modèle indisponible", en: "Rewrite skipped: model unavailable", es: "Reescritura ignorada: modelo no disponible", zh: "已跳过重写：模型不可用", ja: "リライトを無効化：モデルが利用不可", ru: "Переписывание пропущено: модель недоступна")
        case .some(.selectedFormattingModelUnavailable):
            return L10n.ui(for: languageCode, fr: "Réécriture ignorée : modèle de formatage non prêt", en: "Rewrite skipped: formatting model not ready", es: "Reescritura ignorada: modelo de formateo no listo", zh: "已跳过重写：格式化模型尚未就绪", ja: "リライトを無効化：整形モデルの準備が未完了", ru: "Переписывание пропущено: модель форматирования не готова")
        case .some(.insertionAccessibilityUnavailable):
            return L10n.ui(for: languageCode, fr: "Insertion dégradée : clipboard only", en: "Degraded insertion: clipboard only", es: "Inserción degradada: solo portapapeles", zh: "降级插入：仅剪贴板", ja: "挿入を縮退：clipboard only", ru: "Упрощенная вставка: только буфер обмена")
        case .some(.insertionTargetNotFrontmost):
            return L10n.ui(for: languageCode, fr: "Insertion dégradée : app cible non focalisée", en: "Degraded insertion: target app lost focus", es: "Inserción degradada: la app objetivo perdió el foco", zh: "降级插入：目标应用未聚焦", ja: "挿入を縮退：対象アプリが非アクティブ", ru: "Упрощенная вставка: целевое приложение не в фокусе")
        default:
            return L10n.ui(for: languageCode, fr: "Fallback actif", en: "Fallback active", es: "Fallback activo", zh: "已启用回退", ja: "フォールバック有効", ru: "Фолбэк активен")
        }
    }

    static func insertionStrategyMessage(
        _ strategy: InsertionStrategy?,
        fallbackReason: FallbackReason?,
        languageCode: String
    ) -> String {
        switch strategy {
        case .typingEvents:
            return L10n.ui(for: languageCode, fr: "Frappe simulée", en: "Simulated typing", es: "Escritura simulada", zh: "模拟输入", ja: "擬似タイピング", ru: "Имитация ввода")
        case .pasteWithClipboardRestore:
            return L10n.ui(for: languageCode, fr: "Collage avec restauration du presse-papiers", en: "Paste with clipboard restore", es: "Pegado con restauración del portapapeles", zh: "粘贴并恢复剪贴板", ja: "貼り付け後にクリップボード復元", ru: "Вставка с восстановлением буфера обмена")
        case .clipboardOnly:
            if fallbackReason != nil {
                return L10n.ui(for: languageCode, fr: "Clipboard only (dégradé)", en: "Clipboard only (degraded)", es: "Solo portapapeles (degradado)", zh: "仅剪贴板（降级）", ja: "clipboard only（縮退）", ru: "Только буфер обмена (упрощенно)")
            }
            return L10n.ui(for: languageCode, fr: "Clipboard only", en: "Clipboard only", es: "Solo portapapeles", zh: "仅剪贴板", ja: "clipboard only", ru: "Только буфер обмена")
        case .none:
            return L10n.ui(for: languageCode, fr: "Aucune insertion", en: "No insertion", es: "Sin inserción", zh: "无插入", ja: "挿入なし", ru: "Без вставки")
        }
    }
}

struct SessionDebugExport: Codable {
    struct StageLatency: Codable {
        let stageName: String
        let durationMs: Double
        let wasSkipped: Bool
        let isModelBased: Bool
        let transformations: [String]
    }

    let sessionID: String
    let startedAt: String
    let updatedAt: String
    let endedAt: String?
    let finalPhase: String
    let rawASRTranscript: String?
    let finalFormattedText: String?
    let pipelineDecision: String?
    let fallbackReason: String?
    let outputProfile: String
    let insertionStrategy: String?
    let insertionFallbackReason: String?
    let targetBundleID: String?
    let transcriptionMode: String
    let latencies: [String: Double]
    let timeline: [String: String]
    let pipelineStageLatencies: [StageLatency]
    let transitions: [DictationSessionTransition]
}

enum SessionDebugExportError: LocalizedError {
    case noSession
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No session available for export."
        case .exportCancelled:
            return "Debug export cancelled."
        }
    }
}

@MainActor
final class SessionDebugExporter {
    static let shared = SessionDebugExporter()

    private let isoFormatter = ISO8601DateFormatter()

    private init() {}

    func exportLatestSessionInteractively() throws -> URL {
        guard let session = AppState.shared.latestDictationSession else {
            throw SessionDebugExportError.noSession
        }

        let panel = NSSavePanel()
        panel.title = "Export Zphyr Debug Bundle"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "zphyr-debug-\(session.id.uuidString.prefix(8))"

        guard panel.runModal() == .OK, let destination = panel.url else {
            throw SessionDebugExportError.exportCancelled
        }

        return try exportLatestSession(to: destination)
    }

    @discardableResult
    func exportLatestSession(to destination: URL) throws -> URL {
        guard let session = AppState.shared.latestDictationSession else {
            throw SessionDebugExportError.noSession
        }
        let metrics = LocalMetricsRecorder.shared.sessionHistory.last(where: { $0.sessionID == session.id })
            ?? LocalMetricsRecorder.shared.lastSession

        let bundleURL = destination.pathExtension.isEmpty
            ? destination.appendingPathExtension("zphyrdebug")
            : destination
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let export = makeExport(session: session, metrics: metrics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = bundleURL.appendingPathComponent("session.json")
        try encoder.encode(export).write(to: jsonURL)

        let summaryURL = bundleURL.appendingPathComponent("summary.md")
        try summaryMarkdown(session: session, metrics: metrics).write(to: summaryURL, atomically: true, encoding: .utf8)

        return bundleURL
    }

    private func makeExport(
        session: DictationSession,
        metrics: DictationSessionMetrics?
    ) -> SessionDebugExport {
        let stageLatencies = session.pipelineTrace.map { trace in
            SessionDebugExport.StageLatency(
                stageName: trace.stageName,
                durationMs: trace.durationMs,
                wasSkipped: trace.wasSkipped,
                isModelBased: trace.isModelBased,
                transformations: trace.transformations
            )
        }
        let latencies: [String: Double] = [
            "speechEndToAsrStartMs": Double(metrics?.speechEndToASRStartMs ?? 0),
            "asrToRawTranscriptMs": Double(metrics?.asrToRawTranscriptMs ?? 0),
            "rawTranscriptToFormattingFinalMs": Double(metrics?.rawTranscriptToFormattingFinalMs ?? 0),
            "formattingFinalToInsertionMs": Double(metrics?.formattingFinalToInsertionMs ?? 0),
            "endToEndMs": Double(metrics?.endToEndDurationMs ?? 0),
            "asrMs": Double(metrics?.asrDurationMs ?? 0),
            "stabilizeMs": Double(metrics?.stabilizeDurationMs ?? 0),
            "formatterMs": Double(metrics?.formatterDurationMs ?? 0),
            "insertionMs": Double(metrics?.insertionDurationMs ?? 0),
            "totalMs": Double(metrics?.totalDurationMs ?? 0),
        ]
        let timeline: [String: String] = [
            "speechEndedAt": metrics?.speechEndedAt.map { isoFormatter.string(from: $0) } ?? "",
            "asrStartedAt": metrics?.asrStartedAt.map { isoFormatter.string(from: $0) } ?? "",
            "rawTranscriptReadyAt": metrics?.rawTranscriptReadyAt.map { isoFormatter.string(from: $0) } ?? "",
            "formattingCompletedAt": metrics?.formattingCompletedAt.map { isoFormatter.string(from: $0) } ?? "",
            "insertionCompletedAt": metrics?.insertionCompletedAt.map { isoFormatter.string(from: $0) } ?? "",
            "sessionCompletedAt": metrics?.sessionCompletedAt.map { isoFormatter.string(from: $0) } ?? "",
        ]

        return SessionDebugExport(
            sessionID: session.id.uuidString,
            startedAt: isoFormatter.string(from: session.startedAt),
            updatedAt: isoFormatter.string(from: session.updatedAt),
            endedAt: session.endedAt.map { isoFormatter.string(from: $0) },
            finalPhase: session.phase.rawValue,
            rawASRTranscript: session.liveTranscription.finalText,
            finalFormattedText: session.finalFormattedText,
            pipelineDecision: session.pipelineDecision?.rawValue,
            fallbackReason: session.latestFallbackReason?.rawValue,
            outputProfile: session.outputProfile.rawValue,
            insertionStrategy: session.insertionStrategy?.rawValue,
            insertionFallbackReason: session.insertionFallbackReason?.rawValue,
            targetBundleID: session.targetBundleID,
            transcriptionMode: session.liveTranscription.mode.rawValue,
            latencies: latencies,
            timeline: timeline,
            pipelineStageLatencies: stageLatencies,
            transitions: session.transitions
        )
    }

    private func summaryMarkdown(
        session: DictationSession,
        metrics: DictationSessionMetrics?
    ) -> String {
        let languageCode = AppState.shared.uiDisplayLanguage.rawValue
        let pipelineDecision = SessionPresentation.pipelineDecisionMessage(session.pipelineDecision, languageCode: languageCode)
        let fallback = SessionPresentation.fallbackMessage(
            pipelineFallbackReason: session.pipelineFallbackReason,
            insertionFallbackReason: session.insertionFallbackReason,
            outputProfile: session.outputProfile,
            languageCode: languageCode
        ) ?? "none"
        let insertion = SessionPresentation.insertionStrategyMessage(
            session.insertionStrategy,
            fallbackReason: session.insertionFallbackReason,
            languageCode: languageCode
        )

        return """
        # Zphyr Debug Export

        - Session ID: `\(session.id.uuidString)`
        - Started: `\(isoFormatter.string(from: session.startedAt))`
        - Updated: `\(isoFormatter.string(from: session.updatedAt))`
        - Ended: `\(session.endedAt.map { isoFormatter.string(from: $0) } ?? "n/a")`
        - Final phase: `\(session.phase.rawValue)`
        - Output profile: `\(session.outputProfile.rawValue)`
        - Pipeline decision: \(pipelineDecision)
        - Fallback: \(fallback)
        - Insertion: \(insertion)
        - Target bundle: `\(session.targetBundleID ?? "n/a")`
        - ASR mode: `\(session.liveTranscription.mode.rawValue)`
        - Latency total end-to-end: `\(metrics?.endToEndDurationMs ?? 0) ms`
        - Fin parole -> début ASR: `\(metrics?.speechEndToASRStartMs ?? 0) ms`
        - Début ASR -> transcription brute: `\(metrics?.asrToRawTranscriptMs ?? 0) ms`
        - Transcription brute -> formatting final: `\(metrics?.rawTranscriptToFormattingFinalMs ?? 0) ms`
        - Formatting final -> insertion: `\(metrics?.formattingFinalToInsertionMs ?? 0) ms`
        - Pipeline total interne: `\(metrics?.totalDurationMs ?? 0) ms`

        ## Raw ASR

        ```
        \(session.liveTranscription.finalText ?? "")
        ```

        ## Final formatted text

        ```
        \(session.finalFormattedText ?? "")
        ```
        """
    }
}
