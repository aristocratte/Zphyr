//
//  DictionaryView.swift
//  Zphyr
//
//  Custom word mappings stored in UserDefaults.
//  Words / phrases are injected into the Whisper initial_prompt at transcription time,
//  helping Whisper recognise uncommon names, acronyms, and technical terms.
//

import SwiftUI
import os
import UniformTypeIdentifiers

// MARK: - Dictionary Entry model

struct DictionaryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// The word or phrase as it should appear in the transcription output.
    var word: String
    /// Optional spoken alias (e.g. "kaypi" → "KAPI"). Leave empty if the written form is the spoken form.
    var spokenAs: String

    var displaySpoken: String {
        spokenAs.isEmpty ? word : spokenAs
    }
}

// MARK: - Dictionary Store

@Observable
@MainActor
final class DictionaryStore {
    struct PronunciationReplacementRule {
        let regex: NSRegularExpression
        let replacementTemplate: String
    }

    static let shared = DictionaryStore()
    private nonisolated static let logger = Logger(subsystem: "com.zphyr.app", category: "DictionaryStore")

    static let storageKey = "zphyr.dictionary.entries"
    var entries: [DictionaryEntry] = []
    private var cachedPronunciationRules: [PronunciationReplacementRule]?

    private init() {
        load()
    }

    func add(_ entry: DictionaryEntry) {
        entries.append(entry)
        invalidateCaches()
        save()
    }

    func addOrMerge(word: String, spokenAs: String) {
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSpoken = spokenAs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedWord.isEmpty else { return }

        if let idx = entries.firstIndex(where: { $0.word.caseInsensitiveCompare(cleanedWord) == .orderedSame }) {
            var existing = entries[idx]
            if existing.spokenAs.isEmpty && !cleanedSpoken.isEmpty {
                existing.spokenAs = cleanedSpoken
                entries[idx] = existing
                invalidateCaches()
                save()
                Self.logger.notice("[DictionaryStore] merged spokenAs for word=\(cleanedWord, privacy: .private(mask: .hash)), spokenAs=\(cleanedSpoken, privacy: .private(mask: .hash))")
            }
            return
        }

        let entry = DictionaryEntry(word: cleanedWord, spokenAs: cleanedSpoken)
        entries.append(entry)
        invalidateCaches()
        save()
        Self.logger.notice("[DictionaryStore] added word=\(cleanedWord, privacy: .private(mask: .hash)), spokenAs=\(cleanedSpoken, privacy: .private(mask: .hash))")
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        invalidateCaches()
        save()
    }

    func update(_ entry: DictionaryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            invalidateCaches()
            save()
        }
    }

    func clearAll() {
        entries = []
        invalidateCaches()
        SecureLocalDataStore.removeValue(forKey: Self.storageKey)
    }

    func reloadFromDisk() {
        load()
    }

    /// Returns all words/phrases for injection into the Whisper prompt.
    var wordsForPrompt: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let value = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }

    /// Returns pronunciation hints like "spoken form -> written form" for prompting.
    var spokenHintsForPrompt: [String] {
        entries.compactMap { entry in
            let spoken = entry.spokenAs.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty, !written.isEmpty else { return nil }
            return "\"\(spoken)\" -> \"\(written)\""
        }
    }

    var pronunciationReplacementRules: [PronunciationReplacementRule] {
        if let cachedPronunciationRules {
            return cachedPronunciationRules
        }

        let compiled = entries
            .compactMap { entry -> PronunciationReplacementRule? in
                let spoken = entry.spokenAs.trimmingCharacters(in: .whitespacesAndNewlines)
                let written = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty, !written.isEmpty else { return nil }
                let escaped = NSRegularExpression.escapedPattern(for: spoken)
                let pattern = "\\b\(escaped)\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    return nil
                }
                return PronunciationReplacementRule(
                    regex: regex,
                    replacementTemplate: Self.escapedReplacementTemplate(written)
                )
            }
            .sorted { lhs, rhs in
                lhs.regex.pattern.count > rhs.regex.pattern.count
            }

        cachedPronunciationRules = compiled
        return compiled
    }

    /// Returns true when the dictionary already knows this spoken -> written mapping.
    func containsMapping(mistakenWord: String, correctedWord: String) -> Bool {
        let mistaken = mistakenWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correctedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mistaken.isEmpty, !corrected.isEmpty else { return false }

        for entry in entries {
            guard entry.word.caseInsensitiveCompare(corrected) == .orderedSame else { continue }
            guard !entry.spokenAs.isEmpty else { continue }
            if entry.spokenAs.caseInsensitiveCompare(mistaken) == .orderedSame {
                return true
            }
        }
        return false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            _ = SecureLocalDataStore.save(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = SecureLocalDataStore.load(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            entries = []
            invalidateCaches()
            return
        }
        entries = decoded
        invalidateCaches()
    }

    private func invalidateCaches() {
        cachedPronunciationRules = nil
    }

    private static func escapedReplacementTemplate(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}

// MARK: - DictionaryView

struct DictionaryView: View {
    @Bindable private var appState = AppState.shared
    private var store: DictionaryStore { DictionaryStore.shared }

    @State private var showAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var searchText = ""

    private var filteredEntries: [DictionaryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.word.localizedCaseInsensitiveContains(q) ||
            $0.spokenAs.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        let _ = appState.selectedLanguage.id
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Dictionnaire", "Dictionary", "Diccionario", "词典", "辞書", "Словарь"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(
                        t("Les mots ajoutés ici sont injectés dans Whisper pour une meilleure reconnaissance.",
                          "Words added here are injected into Whisper for better recognition.",
                          "Las palabras añadidas aquí se inyectan en Whisper para mejorar el reconocimiento.",
                          "这里添加的词会注入 Whisper 以提升识别效果。",
                          "ここで追加した単語は認識精度向上のため Whisper に注入されます。",
                          "Слова, добавленные здесь, передаются в Whisper для лучшего распознавания.")
                    )
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#888880"))
                        .lineSpacing(2)
                }
                Spacer()
                HStack(spacing: 8) {
                    if !store.entries.isEmpty {
                        Button {
                            exportDictionary()
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

                    Button {
                        showAddSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(t("Ajouter", "Add", "Añadir", "添加", "追加", "Добавить"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#1A1A1A"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 12)

            // Search bar (only when there are entries)
            if !store.entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                    TextField(
                        t("Rechercher…", "Search…", "Buscar…", "搜索…", "検索…", "Поиск…"),
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#CCCCCC"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#E5E5E0"), lineWidth: 1))
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }

            if store.entries.isEmpty {
                emptyState
            } else if filteredEntries.isEmpty {
                // No results state
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                    Text(t("Aucun résultat pour « \(searchText) »",
                           "No results for \"\(searchText)\"",
                           "Sin resultados para \"\(searchText)\"",
                           "没有找到\"\(searchText)\"",
                           "「\(searchText)」の結果なし",
                           "Нет результатов для «\(searchText)»"))
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            DictionaryEntryRow(entry: entry) {
                                editingEntry = entry
                            } onDelete: {
                                if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                                    store.remove(at: IndexSet(integer: idx))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(Color(hex: "#F7F7F5"))
        .sheet(isPresented: $showAddSheet) {
            DictionaryEntrySheet(entry: nil) { newEntry in
                store.add(newEntry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntrySheet(entry: entry) { updated in
                store.update(updated)
            }
        }
    }

    private func exportDictionary() {
        let lines = store.entries.map { entry in
            entry.spokenAs.isEmpty ? entry.word : "\(entry.word)\t\(entry.spokenAs)"
        }
        let header = "# Zphyr Dictionary Export\n# Format: word[TAB]spoken_as\n\n"
        let content = header + lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.title = t("Exporter le dictionnaire", "Export dictionary", "Exportar diccionario", "导出词典", "辞書をエクスポート", "Экспорт словаря")
        panel.nameFieldStringValue = "zphyr-dictionary.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#1A1A1A").opacity(0.05))
                    .frame(width: 72, height: 72)
                Image(systemName: "text.book.closed")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "#BBBBBB"))
            }
            VStack(spacing: 6) {
                Text(t("Dictionnaire vide", "Empty dictionary", "Diccionario vacío", "词典为空", "辞書は空です", "Пустой словарь"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(
                    t("Ajoutez des noms propres, acronymes ou termes techniques\npour améliorer la précision de la dictée.",
                      "Add proper names, acronyms, or technical terms\nto improve dictation accuracy.",
                      "Añade nombres propios, acrónimos o términos técnicos\npara mejorar la precisión del dictado.",
                      "添加专有名词、缩写或技术术语，\n以提升听写准确率。",
                      "固有名詞・略語・技術用語を追加して\n音声入力の精度を高めましょう。",
                      "Добавляйте имена, аббревиатуры и технические термины,\nчтобы повысить точность диктовки.")
                )
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(t("Ajouter un mot", "Add a word", "Añadir una palabra", "添加词语", "単語を追加", "Добавить слово"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color(hex: "#1A1A1A"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dictionary Entry Row

private struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#007AFF").opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: "textformat.abc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#007AFF"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.word)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                if !entry.spokenAs.isEmpty {
                    Text(
                        t("Prononcé : \"\(entry.spokenAs)\"",
                          "Pronounced as: \"\(entry.spokenAs)\"",
                          "Pronunciado como: \"\(entry.spokenAs)\"",
                          "发音：\"\(entry.spokenAs)\"",
                          "発音: \"\(entry.spokenAs)\"",
                          "Произносится как: \"\(entry.spokenAs)\"")
                    )
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#888880"))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "#E5E5E0"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
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
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(isHovered ? 0.06 : 0.03),
                        radius: isHovered ? 8 : 5, x: 0, y: 2)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Add / Edit Sheet

struct DictionaryEntrySheet: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var word: String = ""
    @State private var spokenAs: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(entry == nil
                     ? t("Nouveau mot", "New word", "Nueva palabra", "新词", "新しい単語", "Новое слово")
                     : t("Modifier", "Edit", "Editar", "编辑", "編集", "Изменить"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            VStack(spacing: 20) {
                // Word field
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Mot ou expression", "Word or phrase", "Palabra o expresión", "词或短语", "単語またはフレーズ", "Слово или фраза"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#888880"))
                    TextField(t("ex: WhisperKit, API_KEY, Jean-Philippe…",
                                "e.g. WhisperKit, API_KEY, John Doe…",
                                "ej: WhisperKit, API_KEY, Juan Pérez…",
                                "例如：WhisperKit、API_KEY、张三…",
                                "例: WhisperKit, API_KEY, 山田太郎…",
                                "напр.: WhisperKit, API_KEY, Иван Иванов…"), text: $word)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                        .padding(10)
                        .background(Color(hex: "#F5F5F3"))
                        .cornerRadius(8)
                }

                // Spoken alias field
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Prononciation (optionnel)", "Pronunciation (optional)", "Pronunciación (opcional)", "发音（可选）", "発音（任意）", "Произношение (необязательно)"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#888880"))
                    TextField(t("ex: \"whisper kit\", \"kaypi\"…",
                                "e.g. \"whisper kit\", \"kaypi\"…",
                                "ej: \"whisper kit\", \"kaypi\"…",
                                "例如：“whisper kit”、“kaypi”…",
                                "例: \"whisper kit\", \"kaypi\"…",
                                "напр.: \"whisper kit\", \"kaypi\"…"), text: $spokenAs)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                        .padding(10)
                        .background(Color(hex: "#F5F5F3"))
                        .cornerRadius(8)
                    Text(t("Si vide, Whisper cherchera directement le mot tel quel.",
                           "If empty, Whisper will try to recognize the word as-is.",
                           "Si está vacío, Whisper buscará la palabra tal cual.",
                           "若留空，Whisper 将按原词尝试识别。",
                           "空の場合、Whisper は単語をそのまま認識しようとします。",
                           "Если пусто, Whisper попытается распознать слово как есть."))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                }
            }
            .padding(20)

            Spacer()

            Divider()

            HStack {
                Button(t("Annuler", "Cancel", "Cancelar", "取消", "キャンセル", "Отмена")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#888880"))
                Spacer()
                Button {
                    guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    var newEntry = entry ?? DictionaryEntry(word: "", spokenAs: "")
                    newEntry.word = word.trimmingCharacters(in: .whitespaces)
                    newEntry.spokenAs = spokenAs.trimmingCharacters(in: .whitespaces)
                    onSave(newEntry)
                    dismiss()
                } label: {
                    Text(entry == nil
                         ? t("Ajouter", "Add", "Añadir", "添加", "追加", "Добавить")
                         : t("Enregistrer", "Save", "Guardar", "保存", "保存", "Сохранить"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(word.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color(hex: "#BBBBBB")
                                    : Color(hex: "#1A1A1A"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 400, height: 340)
        .background(Color.white)
        .colorScheme(.light)
        .onAppear {
            if let entry {
                word = entry.word
                spokenAs = entry.spokenAs
            }
        }
    }
}

#Preview {
    DictionaryView()
        .frame(width: 720, height: 560)
}
