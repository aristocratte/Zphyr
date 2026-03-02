//
//  HomeView.swift
//  Zphyr
//
//  Dashboard: real-time stats + transcription history from AppState.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transcription Entry model (used in HomeView + HistoryView)

struct TranscriptionEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let title: String
    let preview: String
    let date: String
    let duration: String
    let wordCount: Int
    let language: String
}

// MARK: - Shared session store (persisted to UserDefaults)

@Observable
@MainActor
final class TranscriptionStore {
    static let shared = TranscriptionStore()
    static let storageKey = "zphyr.transcriptions"

    private init() { load() }

    var entries: [TranscriptionEntry] = []

    func add(text: String, language: String) {
        guard !text.isEmpty else { return }
        let words = text.split(separator: " ").count
        let entry = TranscriptionEntry(
            title: text,
            preview: text,
            date: Self.formattedNow(),
            duration: "",
            wordCount: words,
            language: language.uppercased()
        )
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        entries = []
        SecureLocalDataStore.removeValue(forKey: Self.storageKey)
    }

    func reloadFromDisk() {
        load()
    }

    private static func formattedNow() -> String {
        let f = DateFormatter()
        f.locale = AppState.shared.uiLocale
        f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return f.string(from: Date())
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            _ = SecureLocalDataStore.save(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = SecureLocalDataStore.load(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data)
        else {
            entries = []
            return
        }
        entries = decoded
    }

    // Cumulative stats
    var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }
    var totalTranscriptions: Int { entries.count }
    // Rough time saved estimate: 3× faster than typing (avg 40 wpm typing vs ~120 wpm speech)
    var minutesSaved: Double { Double(totalWords) / 120.0 * 2 }
}

// MARK: - HomeView

struct HomeView: View {
    private var store: TranscriptionStore { TranscriptionStore.shared }
    @Bindable private var appState = AppState.shared
    @AppStorage("zphyr.shortcut.triggerKey") private var triggerKeyRaw = TriggerKey.rightOption.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(greeting)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text(appState.modelStatus.isReady
                             ? t("Le modèle Whisper est actif. Maintenez \(triggerDisplayName) pour dicter.",
                                 "Whisper is ready. Hold \(triggerDisplayName) to dictate.",
                                 "Whisper está listo. Mantén \(triggerDisplayName) para dictar.",
                                 "Whisper 已就绪。按住 \(triggerDisplayName) 开始听写。",
                                 "Whisper の準備ができました。\(triggerDisplayName) を押し続けて音声入力します。",
                                 "Whisper готов. Удерживайте \(triggerDisplayName), чтобы диктовать.")
                             : t("Le modèle Whisper n'est pas encore chargé.",
                                 "Whisper is not loaded yet.",
                                 "Whisper aún no está cargado.",
                                 "Whisper 尚未加载。",
                                 "Whisper はまだ読み込まれていません。",
                                 "Whisper еще не загружен."))
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#888880"))
                    }
                    Spacer()
                }

                // Stats row
                HStack(spacing: 14) {
                    StatCard(
                        value: "\(store.totalWords)",
                        label: t("Mots dictés", "Words dictated", "Palabras dictadas", "已听写词数", "音声入力した単語数", "Продиктовано слов"),
                        icon: "character.cursor.ibeam",
                        trend: store.totalWords > 0 ? nil : nil
                    )
                    StatCard(
                        value: formatMinutes(store.minutesSaved),
                        label: t("Temps gagné", "Time saved", "Tiempo ahorrado", "节省时间", "節約時間", "Сэкономлено времени"),
                        icon: "clock.badge.checkmark",
                        trend: nil
                    )
                    StatCard(
                        value: "\(store.totalTranscriptions)",
                        label: t("Transcriptions", "Transcriptions", "Transcripciones", "转写次数", "文字起こし回数", "Транскрипции"),
                        icon: "doc.text.fill",
                        trend: nil
                    )
                    StatCard(
                        value: appState.modelStatus.isReady ? "✓" : "–",
                        label: t("Modèle", "Model", "Modelo", "模型", "モデル", "Модель"),
                        icon: "cpu",
                        trend: nil,
                        valueColor: appState.modelStatus.isReady ? Color(hex: "#34C759") : Color(hex: "#BBBBBB")
                    )
                }

                // Live dictation state banner
                if appState.dictationState == .listening || appState.dictationState == .processing {
                    LiveDictationBanner()
                }

                // Recent transcriptions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(t("Récent", "Recent", "Recientes", "最近", "最近", "Недавние"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Spacer()
                        if store.entries.isEmpty {
                            Text(t("Aucune dictée pour l'instant",
                                   "No dictation yet",
                                   "Aún no hay dictados",
                                   "还没有听写记录",
                                   "まだ音声入力はありません",
                                   "Пока нет диктовок"))
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#CCCCCC"))
                        } else {
                            Button {
                                exportHistory()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .medium))
                                    Text(t("Exporter", "Export", "Exportar", "导出", "エクスポート", "Экспорт"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color(hex: "#888880"))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if store.entries.isEmpty {
                        EmptyStateView()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(store.entries.prefix(8)) { entry in
                                TranscriptionCard(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(hex: "#F7F7F5"))
        .onChange(of: appState.lastTranscription) { _, newText in
            guard !newText.isEmpty else { return }
            TranscriptionStore.shared.add(
                text: newText,
                language: appState.selectedLanguage.id.uppercased()
            )
        }
    }

    // MARK: - Export

    private func exportHistory() {
        let lines = store.entries.map { entry in
            "[\(entry.date)] [\(entry.language)] \(entry.wordCount) mots\n\(entry.preview)"
        }
        let content = lines.joined(separator: "\n\n---\n\n")
        let panel = NSSavePanel()
        panel.title = t("Exporter l'historique", "Export history", "Exportar historial", "导出历史", "履歴をエクスポート", "Экспорт истории")
        panel.nameFieldStringValue = "zphyr-history.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return t("Bonjour", "Good morning", "Buenos días", "早上好", "おはようございます", "Доброе утро")
        case 12..<18:
            return t("Bon après-midi", "Good afternoon", "Buenas tardes", "下午好", "こんにちは", "Добрый день")
        default:
            return t("Bonsoir", "Good evening", "Buenas noches", "晚上好", "こんばんは", "Добрый вечер")
        }
    }

    private func formatMinutes(_ m: Double) -> String {
        if m < 1 {
            return t("< 1m", "< 1m", "< 1m", "< 1分", "< 1分", "< 1м")
        }
        if m < 60 { return "\(Int(m))m" }
        let hours = Int(m / 60)
        let minutes = Int(m.truncatingRemainder(dividingBy: 60))
        return "\(hours)h \(minutes)m"
    }

    private var triggerDisplayName: String {
        let key = TriggerKey(rawValue: triggerKeyRaw) ?? .rightOption
        return key.displayName(for: appState.uiDisplayLanguage.rawValue)
    }
}

// MARK: - Live dictation banner

private struct LiveDictationBanner: View {
    private var appState: AppState { AppState.shared }
    @State private var blink = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF3B30").opacity(0.15))
                    .frame(width: 28, height: 28)
                    .scaleEffect(blink ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blink)
                Circle()
                    .fill(Color(hex: "#FF3B30"))
                    .frame(width: 10, height: 10)
            }
            .onAppear { blink = true }

            Text(appState.dictationState == .listening
                 ? t("Écoute en cours…", "Listening…", "Escuchando…", "正在监听…", "聞き取り中…", "Слушаю…")
                 : t("Transcription…", "Transcribing…", "Transcribiendo…", "转写中…", "文字起こし中…", "Транскрибация…"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#FF3B30"))

            Spacer()

            // Spectrum mini
            HStack(spacing: 2) {
                ForEach(Array(appState.audioLevels.prefix(14).enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#FF3B30").opacity(0.7))
                        .frame(width: 3, height: max(3, level * 20))
                        .animation(.easeInOut(duration: 0.1), value: level)
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "#FF3B30").opacity(0.07))
        .cornerRadius(12)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @AppStorage("zphyr.shortcut.triggerKey") private var triggerKeyRaw = TriggerKey.rightOption.rawValue

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color(hex: "#22D3B8").opacity(0.45))
            Text(t("Vos dictées apparaîtront ici",
                   "Your dictations will appear here",
                   "Tus dictados aparecerán aquí",
                   "你的听写记录会显示在这里",
                   "音声入力の履歴がここに表示されます",
                   "Ваши диктовки появятся здесь"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#CCCCCC"))
            Text(t("Maintenez la touche \(triggerDisplayName) pour commencer à dicter.",
                   "Hold \(triggerDisplayName) to start dictating.",
                   "Mantén \(triggerDisplayName) para empezar a dictar.",
                   "按住 \(triggerDisplayName) 开始听写。",
                   "\(triggerDisplayName) を押し続けると音声入力を開始します。",
                   "Удерживайте \(triggerDisplayName), чтобы начать диктовку."))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#DDDDDA"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 1)
    }

    private var triggerDisplayName: String {
        let key = TriggerKey(rawValue: triggerKeyRaw) ?? .rightOption
        return key.displayName(for: AppState.shared.uiDisplayLanguage.rawValue)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let trend: String?
    var valueColor: Color = Color(hex: "#1A1A1A")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#22D3B8"))
                Spacer()
                if let trend {
                    Text(trend)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#34C759"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#34C759").opacity(0.1))
                        .cornerRadius(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundColor(valueColor)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#AAAAAA"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Transcription Card

struct TranscriptionCard: View {
    let entry: TranscriptionEntry
    @State private var isHovered = false
    @State private var copied = false

    var languageColor: Color {
        switch entry.language.uppercased() {
        case "SWIFT":   return Color(hex: "#FF6B35")
        case "JS", "TS":return Color(hex: "#F0DB4F")
        case "MD":      return Color(hex: "#4A90D9")
        case "PY":      return Color(hex: "#3776AB")
        case "FR":      return Color(hex: "#007AFF")
        case "EN":      return Color(hex: "#34C759")
        default:        return Color(hex: "#888880")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(languageColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text(String(entry.language.prefix(2)))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(languageColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label(entry.date, systemImage: "calendar")
                    if !entry.duration.isEmpty {
                        Label(entry.duration, systemImage: "timer")
                    }
                    Label(
                        t("\(entry.wordCount) mots",
                          "\(entry.wordCount) words",
                          "\(entry.wordCount) palabras",
                          "\(entry.wordCount) 个词",
                          "\(entry.wordCount) 語",
                          "\(entry.wordCount) слов"),
                        systemImage: "textformat"
                    )
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .labelStyle(.titleAndIcon)
            }

            Spacer()

            // Action buttons (visible on hover)
            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.preview, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(copied ? Color(hex: "#34C759") : Color(hex: "#888880"))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "#E5E5E0"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        TranscriptionStore.shared.remove(id: entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#FF3B30"))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "#FF3B30").opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                // Always show copy icon when not hovered (subtle)
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(copied ? Color(hex: "#34C759") : Color(hex: "#DDDDDA"))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(isHovered ? 0.06 : 0.03),
                        radius: isHovered ? 10 : 6, x: 0, y: 2)
        )
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// Keep mock data for HistoryView
let mockTranscriptions: [TranscriptionEntry] = [
    TranscriptionEntry(
        title: "Revue de code – AuthService",
        preview: "func authenticate(user: String, password: String) async throws -> AuthToken",
        date: "Aujourd'hui, 14h32", duration: "1m 12s", wordCount: 87, language: "Swift"
    ),
    TranscriptionEntry(
        title: "Notes de réunion – Sprint 12",
        preview: "On a décidé de migrer le backend vers une architecture microservices.",
        date: "Aujourd'hui, 11h05", duration: "3m 45s", wordCount: 243, language: "FR"
    ),
    TranscriptionEntry(
        title: "Refactor UserViewModel",
        preview: "@Observable class UserViewModel { var users: [User] = [] var isLoading = false",
        date: "Hier, 17h20", duration: "0m 58s", wordCount: 64, language: "Swift"
    ),
    TranscriptionEntry(
        title: "API endpoint – /auth/refresh",
        preview: "router.post('/auth/refresh', async (req, res) => { const { refreshToken } = req.body",
        date: "Hier, 09h44", duration: "2m 01s", wordCount: 132, language: "JS"
    ),
    TranscriptionEntry(
        title: "Documentation README",
        preview: "## Installation — Clonez le dépôt et installez les dépendances avec npm install.",
        date: "28 fév, 16h11", duration: "4m 22s", wordCount: 318, language: "MD"
    ),
]

#Preview {
    HomeView()
        .frame(width: 720, height: 600)
}
