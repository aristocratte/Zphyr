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

    private static let nowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter
    }()

    private static func formattedNow() -> String {
        nowFormatter.locale = AppState.shared.uiLocale
        return nowFormatter.string(from: Date())
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
            VStack(alignment: .leading, spacing: 24) {

                // ── Header ────────────────────────────────────────────
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(hex: "#111111"))

                        // Status pill
                        HStack(spacing: 5) {
                            Circle()
                                .fill(appState.modelStatus.isReady ? Color(hex: "#34C759") : Color(hex: "#CCCCC8"))
                                .frame(width: 6, height: 6)
                            Text(appState.modelStatus.isReady
                                 ? t("Whisper actif · Maintenez \(triggerDisplayName)",
                                     "Whisper ready · Hold \(triggerDisplayName)",
                                     "Whisper listo · Mantén \(triggerDisplayName)",
                                     "Whisper 已就绪 · 按住 \(triggerDisplayName)",
                                     "Whisper 準備完了 · \(triggerDisplayName) を長押し",
                                     "Whisper готов · Удержите \(triggerDisplayName)")
                                 : t("Whisper non chargé",
                                     "Whisper not loaded",
                                     "Whisper no cargado",
                                     "Whisper 未加载",
                                     "Whisper 未読み込み",
                                     "Whisper не загружен"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "#888880"))
                        }
                    }
                    Spacer()
                }

                // ── Stats row ─────────────────────────────────────────
                HStack(spacing: 12) {
                    StatCard(
                        value: "\(store.totalWords)",
                        label: t("Mots dictés", "Words dictated", "Palabras dictadas", "已听写词数", "音声入力した単語数", "Продиктовано слов"),
                        icon: "character.cursor.ibeam"
                    )
                    StatCard(
                        value: formatMinutes(store.minutesSaved),
                        label: t("Temps gagné", "Time saved", "Tiempo ahorrado", "节省时间", "節約時間", "Сэкономлено времени"),
                        icon: "clock"
                    )
                    StatCard(
                        value: "\(store.totalTranscriptions)",
                        label: t("Transcriptions", "Transcriptions", "Transcripciones", "转写次数", "文字起こし回数", "Транскрипции"),
                        icon: "doc.text"
                    )
                    ModelStatCard()
                }

                // ── Live dictation banner ─────────────────────────────
                if appState.dictationState == .listening || appState.dictationState == .processing || appState.dictationState == .formatting {
                    LiveDictationBanner()
                }

                // ── Recent transcriptions ─────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        Text(t("Récent", "Recent", "Recientes", "最近", "最近", "Недавние"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#111111"))
                        if !store.entries.isEmpty {
                            Text("· \(store.entries.count)")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color(hex: "#BBBBBB"))
                        }
                        Spacer()
                        if !store.entries.isEmpty {
                            Button {
                                exportHistory()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 11, weight: .medium))
                                    Text(t("Exporter", "Export", "Exportar", "导出", "エクスポート", "Экспорт"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color(hex: "#AAAAAA"))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if store.entries.isEmpty {
                        EmptyStateView()
                    } else {
                        VStack(spacing: 6) {
                            ForEach(store.entries.prefix(8)) { entry in
                                TranscriptionCard(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(24)
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
        if m < 1 { return "0m" }
        if m < 60 { return "\(Int(m))m" }
        let hours = Int(m / 60)
        let minutes = Int(m.truncatingRemainder(dividingBy: 60))
        return "\(hours)h\(minutes)m"
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
                 : appState.dictationState == .formatting
                 ? t("Formatage IA…", "AI formatting…", "Formateando IA…", "AI 格式化…", "AI フォーマット中…", "ИИ форматирует…")
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
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(hex: "#22D3B8").opacity(0.5))

            Text(t("Vos dictées apparaîtront ici",
                   "Your dictations will appear here",
                   "Tus dictados aparecerán aquí",
                   "你的听写记录会显示在这里",
                   "音声入力の履歴がここに表示されます",
                   "Ваши диктовки появятся здесь"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#CCCCCA"))

            Text(t("Maintenez \(triggerDisplayName) pour commencer",
                   "Hold \(triggerDisplayName) to start",
                   "Mantén \(triggerDisplayName) para comenzar",
                   "按住 \(triggerDisplayName) 开始",
                   "\(triggerDisplayName) を長押しして開始",
                   "Удержите \(triggerDisplayName) для начала"))
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#DDDDDA"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.025), radius: 4, x: 0, y: 1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#22D3B8"))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundColor(Color(hex: "#111111"))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
    }
}

// MARK: - Model Stat Card

private struct ModelStatCard: View {
    @Bindable private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#22D3B8"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.modelStatus.isReady ? Color(hex: "#34C759") : Color(hex: "#DDDDDA"))
                        .frame(width: 8, height: 8)
                    Text(appState.modelStatus.isReady
                         ? t("Actif", "Active", "Activo", "活跃", "アクティブ", "Активен")
                         : t("Inactif", "Inactive", "Inactivo", "未活跃", "非アクティブ", "Неактивен"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(appState.modelStatus.isReady ? Color(hex: "#111111") : Color(hex: "#CCCCCC"))
                }
                Text(t("Modèle Whisper", "Whisper model", "Modelo Whisper", "Whisper 模型", "Whisper モデル", "Модель Whisper"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#AAAAAA"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
    }
}

// MARK: - Transcription Card

struct TranscriptionCard: View {
    let entry: TranscriptionEntry
    @State private var isHovered = false
    @State private var copied = false
    @State private var flashCopy = false

    private var langColor: Color {
        switch entry.language.uppercased() {
        case "FR":      return Color(hex: "#007AFF")
        case "EN":      return Color(hex: "#34C759")
        case "ES":      return Color(hex: "#FF9500")
        case "ZH":      return Color(hex: "#FF3B30")
        case "JA":      return Color(hex: "#AF52DE")
        case "RU":      return Color(hex: "#5856D6")
        case "SWIFT":   return Color(hex: "#FF6B35")
        case "JS", "TS":return Color(hex: "#F0DB4F")
        case "PY":      return Color(hex: "#3776AB")
        default:        return Color(hex: "#AAAAAA")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(langColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#111111"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(entry.date)
                    Text("·")
                    Text(t("\(entry.wordCount) mots",
                           "\(entry.wordCount) words",
                           "\(entry.wordCount) palabras",
                           "\(entry.wordCount) 词",
                           "\(entry.wordCount) 語",
                           "\(entry.wordCount) слов"))
                    Text("·")
                    Text(entry.language.uppercased())
                        .foregroundColor(langColor)
                }
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(Color(hex: "#BBBBBB"))
            }

            Spacer()

            // Action icons
            HStack(spacing: 6) {
                Button { copy() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(copied ? Color(hex: "#34C759") : (isHovered ? Color(hex: "#888880") : Color(hex: "#DDDDDA")))
                        .frame(width: 26, height: 26)
                        .background(isHovered ? Color(hex: "#F0F0EE") : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if isHovered {
                    Button {
                        TranscriptionStore.shared.remove(id: entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#FF3B30"))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "#FF3B30").opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        }
        .padding(.vertical, 11)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: .black.opacity(isHovered ? 0.055 : 0.028),
                        radius: isHovered ? 8 : 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#34C759").opacity(flashCopy ? 0.10 : 0))
                .animation(.easeOut(duration: 0.5), value: flashCopy)
        )
        .scaleEffect(isHovered ? 1.002 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { copy() }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.preview, forType: .string)
        copied = true
        flashCopy = true
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            flashCopy = false
            try? await Task.sleep(for: .seconds(1.1))
            copied = false
        }
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
