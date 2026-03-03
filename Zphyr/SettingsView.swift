//
//  SettingsView.swift
//  Zphyr
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case system
    case shortcut
    case privacy

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:  return "slider.horizontal.3"
        case .system:   return "cpu"
        case .shortcut: return "keyboard"
        case .privacy:  return "lock.shield"
        }
    }

    func label(for languageCode: String) -> String {
        switch self {
        case .general:
            return L10n.ui(for: languageCode, fr: "Général", en: "General", es: "General", zh: "通用", ja: "一般", ru: "Общие")
        case .system:
            return L10n.ui(for: languageCode, fr: "Système", en: "System", es: "Sistema", zh: "系统", ja: "システム", ru: "Система")
        case .shortcut:
            return L10n.ui(for: languageCode, fr: "Raccourci", en: "Shortcut", es: "Atajo", zh: "快捷键", ja: "ショートカット", ru: "Горячая клавиша")
        case .privacy:
            return L10n.ui(for: languageCode, fr: "Confidentialité", en: "Privacy", es: "Privacidad", zh: "隐私", ja: "プライバシー", ru: "Конфиденциальность")
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            VStack(spacing: 0) {
                Text(t("Paramètres", "Settings", "Ajustes", "设置", "設定", "Настройки"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                VStack(spacing: 2) {
                    ForEach(SettingsSection.allCases) { section in
                        SettingsSidebarRow(section: section, isSelected: selectedSection == section) {
                            selectedSection = section
                        }
                    }
                }
                .padding(.horizontal, 8)
                Spacer()
            }
            .frame(width: 190)
            .background(Color(hex: "#F0F0EE"))

            Rectangle()
                .fill(Color(hex: "#E8E8E6"))
                .frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedSection {
                    case .general:  GeneralSettingsContent()
                    case .system:   SystemSettingsContent()
                    case .shortcut: ShortcutSettingsContent()
                    case .privacy:  PrivacySettingsContent()
                    }

                    if let notice = AppState.shared.advancedFeaturesNotice, selectedSection == .system {
                        Text(notice)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#888880"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#F0F0EE"))
                            .cornerRadius(10)
                    }
                }
                .id(selectedSection)
                .animation(.none, value: selectedSection)
                .padding(28)
            }
            .background(Color(hex: "#F7F7F5"))
        }
        .colorScheme(.light)
    }
}

// MARK: - Sidebar Row

struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#1A1A1A") : Color(hex: "#888880"))
                    .frame(width: 16)
                Text(section.label(for: lang))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#1A1A1A") : Color(hex: "#666660"))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(hex: "#1A1A1A").opacity(0.08)
                          : (isHovered ? Color(hex: "#1A1A1A").opacity(0.04) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reusable card/row components

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showDivider: Bool
    @ViewBuilder let trailing: Trailing

    init(icon: String, iconColor: Color = Color(hex: "#1A1A1A"), title: String,
         subtitle: String? = nil, showDivider: Bool = true,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon; self.iconColor = iconColor; self.title = title
        self.subtitle = subtitle; self.showDivider = showDivider
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#AAAAAA"))
                    }
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Rectangle()
                    .fill(Color(hex: "#F0F0EE"))
                    .frame(height: 1)
                    .padding(.leading, 58)
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsContent: View {
    @Bindable private var state = AppState.shared

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    private static let uiLanguages: [(SupportedUILanguage, String)] = [
        (.fr, "\u{1F1EB}\u{1F1F7} Français"),
        (.en, "\u{1F1FA}\u{1F1F8} English"),
        (.es, "\u{1F1EA}\u{1F1F8} Español"),
        (.zh, "\u{1F1E8}\u{1F1F3} 中文"),
        (.ja, "\u{1F1EF}\u{1F1F5} 日本語"),
        (.ru, "\u{1F1F7}\u{1F1FA} Русский"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Général", "General", "General", "通用", "一般", "Общие"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            // UI Language picker
            SettingsCard {
                SettingsRow(icon: "character.bubble", iconColor: Color(hex: "#007AFF"),
                            title: t("Langue de l'interface", "Interface language", "Idioma de interfaz", "界面语言", "インターフェース言語", "Язык интерфейса"),
                            subtitle: t("Langue d'affichage de Zphyr", "Zphyr display language", "Idioma de visualización de Zphyr", "Zphyr 显示语言", "Zphyr の表示言語", "Язык интерфейса Zphyr"),
                            showDivider: false) {
                    Picker("", selection: $state.uiDisplayLanguage) {
                        ForEach(Self.uiLanguages, id: \.0) { lang, label in
                            Text(label).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 165)
                }
            }

            SettingsCard {
                SettingsRow(icon: "power", iconColor: Color(hex: "#34C759"),
                            title: t("Lancer au démarrage", "Launch at startup", "Iniciar al arrancar", "开机启动", "起動時に開始", "Запускать при старте"),
                            subtitle: t("Ouvre Zphyr automatiquement au démarrage", "Open Zphyr automatically at startup", "Abre Zphyr automáticamente al iniciar", "开机时自动打开 Zphyr", "起動時に Zphyr を自動で開く", "Автоматически открывать Zphyr при запуске")) {
                    Toggle("", isOn: $state.launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(icon: "speaker.wave.2.fill", iconColor: Color(hex: "#007AFF"),
                            title: t("Effets sonores", "Sound effects", "Efectos de sonido", "声音效果", "サウンド効果", "Звуковые эффекты"),
                            subtitle: t("Son au début et à la fin de la dictée", "Sound at dictation start and end", "Sonido al inicio y fin del dictado", "听写开始与结束提示音", "音声入力の開始/終了音", "Звук в начале и конце диктовки"),
                            showDivider: false) {
                    Toggle("", isOn: $state.soundEffectsEnabled).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsCard {
                SettingsRow(icon: "text.cursor", iconColor: Color(hex: "#FF9500"),
                            title: t("Insertion automatique", "Auto insert", "Inserción automática", "自动插入", "自動挿入", "Автовставка"),
                            subtitle: t("Simule la frappe via Accessibilité. Désactivé = copie dans le presse-papiers uniquement.", "Simulates typing via Accessibility. Off = clipboard only.", "Simula escritura vía Accesibilidad. Desactivado = solo portapapeles.", "通过辅助功能模拟输入。关闭 = 仅复制到剪贴板。", "アクセシビリティで入力をシミュレート。オフ = クリップボードのみ。", "Симулирует ввод через Специальные возможности. Выкл = только буфер обмена."),
                            showDivider: false) {
                    Toggle("", isOn: $state.autoInsert).labelsHidden().toggleStyle(.switch)
                }
            }

        }
    }
}

// MARK: - System Settings

struct SystemSettingsContent: View {
    @Bindable private var state = AppState.shared

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Système", "System", "Sistema", "系统", "システム", "Система"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            // Code formatting mode
            SettingsCard {
                SettingsRow(
                    icon: "textformat.alt",
                    iconColor: Color(hex: "#AF52DE"),
                    title: t("Mode de formatage", "Formatting mode", "Modo de formateo", "格式化模式", "フォーマットモード", "Режим форматирования"),
                    subtitle: state.formattingMode.subtitle(for: lang),
                    showDivider: state.formattingMode == .advanced
                ) {
                    Picker("", selection: $state.formattingMode) {
                        ForEach(FormattingMode.allCases) { mode in
                            Text(mode.displayName(for: lang)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 175)
                }

                // Style picker only in advanced mode (trigger uses explicit keywords in speech)
                if state.formattingMode == .advanced {
                    SettingsRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        iconColor: Color(hex: "#007AFF"),
                        title: t("Style par défaut", "Default style", "Estilo predeterminado", "默认样式", "デフォルトスタイル", "Стиль по умолчанию"),
                        subtitle: t("Appliqué quand le langage n'est pas détecté", "Applied when language is not detected", "Aplicado cuando el idioma no se detecta", "当语言未被检测时应用", "言語が検出されない場合に適用", "Применяется когда язык не определён"),
                        showDivider: false
                    ) {
                        Picker("", selection: $state.defaultCodeStyle) {
                            ForEach(CodeStyle.allCases) { style in
                                Text(style.displayName(for: lang)).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
            }

            // Qwen model install card — only visible in advanced mode
            if state.formattingMode == .advanced {
                QwenModelCard()
            }

            // Model status card
            SettingsCard {
                SettingsRow(icon: "cpu", iconColor: Color(hex: "#007AFF"),
                            title: t("Modèle Whisper", "Whisper model", "Modelo Whisper", "Whisper 模型", "Whisper モデル", "Модель Whisper"),
                            subtitle: "openai/whisper-large-v3-turbo · 632 MB",
                            showDivider: false) {
                    modelStatusBadge
                }
            }

            // Progress bar when downloading/loading
            if !state.modelStatus.isReady {
                SettingsCard {
                    VStack(spacing: 8) {
                        HStack {
                            Text(state.modelStatusLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "#666660"))
                            Spacer()
                            if state.modelStatus.progress > 0 {
                                Text("\(Int(state.modelStatus.progress * 100))%")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "#888880"))
                            }
                        }
                        if state.modelStatus.progress > 0 {
                            ProgressView(value: state.modelStatus.progress)
                                .progressViewStyle(.linear)
                                .tint(Color(hex: "#007AFF"))
                                .animation(.easeInOut(duration: 0.3), value: state.modelStatus.progress)
                        }
                    }
                    .padding(14)
                }
            }

            // Dictation languages (multi-select)
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#34C759").opacity(0.1))
                                .frame(width: 30, height: 30)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#34C759"))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t("Langues de dictée", "Dictation languages", "Idiomas de dictado", "听写语言", "音声入力言語", "Языки диктовки"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            Text(t("Sélectionnez vos langues parlées — Whisper les reconnaîtra toutes.", "Select your spoken languages — Whisper will recognize all of them.", "Selecciona tus idiomas hablados — Whisper los reconocerá todos.", "选择你会说的语言，Whisper 将全部识别。", "話す言語をすべて選択 — Whisper がすべて認識します。", "Выберите языки — Whisper распознает все."))
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                        }
                        Spacer()
                        if state.selectedLanguages.count > 1 {
                            Text(t("\(state.selectedLanguages.count) langues", "\(state.selectedLanguages.count) languages", "\(state.selectedLanguages.count) idiomas", "\(state.selectedLanguages.count) 种语言", "\(state.selectedLanguages.count) 言語", "\(state.selectedLanguages.count) языка"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#22D3B8"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#22D3B8").opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ], spacing: 6) {
                        ForEach(WhisperLanguage.all, id: \.id) { language in
                            SLanguageCell(
                                language: language,
                                isSelected: state.selectedLanguages.contains(where: { $0.id == language.id })
                            ) {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    if state.selectedLanguages.contains(where: { $0.id == language.id }) {
                                        if state.selectedLanguages.count > 1 {
                                            state.selectedLanguages.removeAll { $0.id == language.id }
                                        }
                                    } else {
                                        state.selectedLanguages.append(language)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
            }

            // Model management (path + uninstall + reinstall)
            if state.modelStatus.isReady || state.modelInstallPath != nil {
                SettingsCard {
                    SettingsRow(icon: "folder.fill", iconColor: Color(hex: "#FF9500"),
                                title: t("Emplacement du modèle", "Model location", "Ubicación del modelo", "模型位置", "モデルの場所", "Расположение модели"),
                                subtitle: state.modelInstallPath.flatMap {
                                    URL(fileURLWithPath: $0).deletingLastPathComponent().path
                                } ?? "—") {
                        Button {
                            if let path = state.modelInstallPath {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        } label: {
                            Label(t("Ouvrir", "Open", "Abrir", "打开", "開く", "Открыть"),
                                  systemImage: "folder.badge.gearshape")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#FF9500"))
                        }
                        .buttonStyle(.plain)
                        .disabled(state.modelInstallPath == nil)
                    }
                    SettingsRow(icon: "trash", iconColor: Color(hex: "#FF3B30"),
                                title: t("Désinstaller le modèle", "Uninstall model", "Desinstalar modelo", "卸载模型", "モデルを削除", "Удалить модель"),
                                subtitle: t("Supprime les fichiers du modèle du disque", "Removes model files from disk", "Elimina los archivos del modelo del disco", "从磁盘删除模型文件", "モデルファイルをディスクから削除", "Удаляет файлы модели с диска")) {
                        Button(t("Désinstaller", "Uninstall", "Desinstalar", "卸载", "削除", "Удалить")) {
                            DictationEngine.shared.uninstallModel()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                    }
                    SettingsRow(icon: "arrow.counterclockwise", iconColor: Color(hex: "#007AFF"),
                                title: t("Réinstaller le modèle", "Reinstall model", "Reinstalar modelo", "重新安装模型", "モデルを再インストール", "Переустановить модель"),
                                subtitle: t("Supprime et retélécharge le modèle", "Deletes and redownloads the model", "Elimina y vuelve a descargar el modelo", "删除并重新下载模型", "モデルを削除して再ダウンロード", "Удаляет и повторно скачивает модель"),
                                showDivider: false) {
                        Button(t("Réinstaller", "Reinstall", "Reinstalar", "重装", "再インストール", "Переустановить")) {
                            Task { await DictationEngine.shared.reinstallModel() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#007AFF"))
                    }
                }
            }

            // Retry button when model failed
            if case .failed = state.modelStatus {
                Button {
                    Task { await DictationEngine.shared.loadModel() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text(t("Réessayer le téléchargement", "Retry download", "Reintentar descarga", "重试下载", "ダウンロードを再試行", "Повторить загрузку"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#007AFF"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#007AFF").opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // Local data size
            SettingsCard {
                SettingsRow(icon: "internaldrive.fill", iconColor: Color(hex: "#888880"),
                            title: t("Données locales", "Local data", "Datos locales", "本地数据", "ローカルデータ", "Локальные данные"),
                            subtitle: t("Historique de transcriptions et dictionnaire", "Transcription history and dictionary", "Historial de transcripciones y diccionario", "转写历史与词典", "文字起こし履歴と辞書", "История транскрипций и словарь"),
                            showDivider: false) {
                    Text(localDataSize)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: "#888880"))
                }
            }

            // Return to onboarding
            SettingsCard {
                SettingsRow(icon: "arrow.uturn.backward.circle.fill", iconColor: Color(hex: "#FF9500"),
                            title: t("Retourner dans l'onboarding", "Return to onboarding", "Volver al onboarding", "返回引导流程", "オンボーディングに戻る", "Вернуться к онбордингу"),
                            subtitle: t("Relance le guide de configuration initial", "Relaunches the initial setup guide", "Reinicia la guía de configuración inicial", "重新启动初始设置向导", "初期セットアップガイドを再起動します", "Перезапускает начальное руководство по настройке"),
                            showDivider: false) {
                    Button(t("Retourner", "Return", "Volver", "返回", "戻る", "Вернуться")) {
                        NotificationCenter.default.post(name: .returnToOnboarding, object: nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#FF9500"))
                }
            }
        }
    }

    private var localDataSize: String {
        let keys = [TranscriptionStore.storageKey, "zphyr.dictionary.entries"]
        let totalBytes = keys.compactMap { UserDefaults.standard.data(forKey: $0)?.count }.reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        switch state.modelStatus {
        case .ready:
            Label(t("Prêt", "Ready", "Listo", "就绪", "準備完了", "Готово"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#34C759"))
                .labelStyle(.titleAndIcon)
        case .notDownloaded:
            Button(t("Télécharger", "Download", "Descargar", "下载", "ダウンロード", "Скачать")) { Task { await DictationEngine.shared.loadModel() } }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#007AFF"))
        case .failed:
            Label(t("Erreur", "Error", "Error", "错误", "エラー", "Ошибка"), systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#FF3B30"))
                .labelStyle(.titleAndIcon)
        default:
            ProgressView().scaleEffect(0.7)
        }
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsContent: View {
    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Raccourci global", "Global shortcut", "Atajo global", "全局快捷键", "グローバルショートカット", "Глобальная горячая клавиша"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            Text(t("Maintenez la touche enfoncée pour dicter. Relâchez pour transcrire.",
                   "Hold the key to dictate. Release to transcribe.",
                   "Mantén la tecla pulsada para dictar. Suelta para transcribir.",
                   "按住按键开始听写，松开即可转写。",
                   "キーを押し続けて音声入力し、離すと文字起こしします。",
                   "Удерживайте клавишу для диктовки. Отпустите для транскрибации."))
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#888880"))
                .lineSpacing(3)

            // Preset trigger key picker
            SettingsCard {
                SettingsRow(icon: "keyboard.chevron.compact.down", iconColor: Color(hex: "#FF6B35"),
                            title: t("Touche prédéfinie", "Preset key", "Tecla predefinida", "预设键", "プリセットキー", "Предустановленная клавиша"),
                            subtitle: ShortcutManager.shared.recordedShortcut == nil
                                ? ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)
                                : t("Désactivé (raccourci personnalisé actif)", "Disabled (custom shortcut active)", "Desactivado (atajo personalizado activo)", "已禁用（自定义快捷键生效）", "無効（カスタムショートカット有効）", "Отключено (используется пользовательский)"),
                            showDivider: false) {
                    Picker("", selection: Binding(
                        get: { ShortcutManager.shared.selectedTriggerKey },
                        set: { ShortcutManager.shared.selectedTriggerKey = $0 }
                    )) {
                        ForEach(TriggerKey.allCases) { key in
                            Text(key.displayName(for: lang)).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 195)
                    .opacity(ShortcutManager.shared.recordedShortcut == nil ? 1 : 0.4)
                    .disabled(ShortcutManager.shared.recordedShortcut != nil)
                }
            }

            // Custom shortcut recorder
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#22D3B8").opacity(0.1))
                                .frame(width: 30, height: 30)
                            Image(systemName: "keyboard.badge.ellipsis")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#22D3B8"))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t("Raccourci personnalisé", "Custom shortcut", "Atajo personalizado", "自定义快捷键", "カスタムショートカット", "Пользовательский ярлык"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            Text(t("Enregistrez n'importe quelle combinaison. Remplace la touche prédéfinie.", "Record any key combination. Overrides the preset key.", "Graba cualquier combinación. Reemplaza la tecla predefinida.", "录制任意组合键，覆盖预设键。", "任意のキーを記録。プリセットキーを上書きします。", "Запишите любую комбинацию. Заменяет предустановленную клавишу."))
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                        }
                        Spacer()
                        SCustomShortcutRecorder()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }

            // Info banner
            HStack(spacing: 10) {
                Image(systemName: "hand.point.up.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#FF6B35"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Mode push-to-talk", "Push-to-talk", "Modo pulsar para hablar", "按住说话模式", "プッシュトゥトーク", "Режим push-to-talk"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(t("Maintenez \(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) → parlez → relâchez. Le texte est transcrit et injecté automatiquement.",
                           "Hold \(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) → speak → release. Text is transcribed and inserted automatically.",
                           "Mantén \(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) → habla → suelta. El texto se transcribe e inserta automáticamente.",
                           "按住 \(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) → 说话 → 松开。文本会自动转写并插入。",
                           "\(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) を押しながら話し、離すと自動で文字起こしと挿入を行います。",
                           "Удерживайте \(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)) → говорите → отпустите. Текст автоматически транскрибируется и вставляется."))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#666660"))
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(Color(hex: "#FF6B35").opacity(0.07))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FF6B35").opacity(0.15), lineWidth: 1))
        }
    }
}

// MARK: - Privacy Settings

struct PrivacySettingsContent: View {
    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }
    @State private var showDeleteConfirm = false
    @State private var encryptLocalData = SecureLocalDataStore.isEncryptionEnabled()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Confidentialité", "Privacy", "Privacidad", "隐私", "プライバシー", "Конфиденциальность"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            // Privacy banner
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "#34C759"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("100% Local & Privé", "100% local & private", "100% local y privado", "100% 本地与私密", "100% ローカル & プライベート", "100% локально и приватно"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(t("Toute la transcription (Whisper) s'exécute sur votre Mac. Aucune donnée audio ne quitte votre appareil.",
                           "All transcription (Whisper) runs on your Mac. No audio data leaves your device.",
                           "Toda la transcripción (Whisper) se ejecuta en tu Mac. Ningún audio sale de tu dispositivo.",
                           "所有转写（Whisper）都在你的 Mac 上运行，音频不会离开设备。",
                           "すべての文字起こし（Whisper）は Mac 上で実行され、音声データは外部に送信されません。",
                           "Вся транскрибация (Whisper) выполняется на вашем Mac. Аудиоданные не покидают устройство."))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#666660"))
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(Color(hex: "#34C759").opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#34C759").opacity(0.2), lineWidth: 1))

            // No telemetry info card
            SettingsCard {
                SettingsRow(icon: "checkmark.shield.fill", iconColor: Color(hex: "#34C759"),
                            title: t("Aucune télémétrie", "No telemetry", "Sin telemetría", "无遥测", "テレメトリなし", "Без телеметрии"),
                            subtitle: t("Zphyr ne collecte aucune donnée analytique, aucun rapport de crash ni aucune statistique d'usage.",
                                        "Zphyr collects no analytics, crash reports, or usage statistics.",
                                        "Zphyr no recopila datos analíticos, reportes de fallos ni estadísticas de uso.",
                                        "Zphyr 不收集任何分析数据、崩溃报告或使用统计。",
                                        "Zphyr は分析データ、クラッシュレポート、使用統計を一切収集しません。",
                                        "Zphyr не собирает аналитику, отчёты о сбоях и статистику использования."),
                            showDivider: false) {
                    EmptyView()
                }
            }

            SettingsCard {
                SettingsRow(
                    icon: "lock.square.stack.fill",
                    iconColor: Color(hex: "#007AFF"),
                    title: t("Chiffrement des données locales", "Encrypt local data", "Cifrar datos locales", "加密本地数据", "ローカルデータを暗号化", "Шифровать локальные данные"),
                    subtitle: t("Historique et dictionnaire stockés chiffrés sur ce Mac.",
                                "History and dictionary are stored encrypted on this Mac.",
                                "El historial y el diccionario se guardan cifrados en este Mac.",
                                "在此 Mac 上加密存储历史与词典。",
                                "履歴と辞書をこの Mac 上で暗号化保存します。",
                                "История и словарь хранятся в зашифрованном виде на этом Mac."),
                    showDivider: false
                ) {
                    Toggle("", isOn: encryptionBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                    Text(t("Supprimer toutes les données locales", "Delete all local data", "Eliminar todos los datos locales", "删除所有本地数据", "ローカルデータをすべて削除", "Удалить все локальные данные"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(Color(hex: "#FF3B30"))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "#FF3B30").opacity(0.08))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                t("Supprimer toutes les données ?", "Delete all local data?", "¿Eliminar todos los datos?", "删除所有数据？", "すべてのデータを削除しますか？", "Удалить все данные?"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(t("Supprimer", "Delete", "Eliminar", "删除", "削除", "Удалить"), role: .destructive) {
                    TranscriptionStore.shared.clearAll()
                    DictionaryStore.shared.clearAll()
                }
                Button(t("Annuler", "Cancel", "Cancelar", "取消", "キャンセル", "Отмена"), role: .cancel) {}
            } message: {
                Text(t("L'historique des dictées et le dictionnaire seront supprimés définitivement.",
                       "Dictation history and dictionary will be permanently deleted.",
                       "El historial de dictados y el diccionario se eliminarán permanentemente.",
                       "听写历史和词典将被永久删除。",
                       "音声入力履歴と辞書は完全に削除されます。",
                       "История диктовок и словарь будут удалены безвозвратно."))
            }
        }
        .onAppear {
            encryptLocalData = SecureLocalDataStore.isEncryptionEnabled()
        }
    }

    private var encryptionBinding: Binding<Bool> {
        Binding(
            get: { encryptLocalData },
            set: { newValue in
                encryptLocalData = newValue
                SecureLocalDataStore.setEncryptionEnabled(newValue)
                TranscriptionStore.shared.reloadFromDisk()
                DictionaryStore.shared.reloadFromDisk()
            }
        )
    }
}

// MARK: - Language Cell (multi-select)

struct SLanguageCell: View {
    let language: WhisperLanguage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(language.flag)
                    .font(.system(size: 15))
                Text(language.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#1A1A1A") : Color(hex: "#555550"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#22D3B8"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isSelected
                            ? Color(hex: "#22D3B8").opacity(0.10)
                            : (isHovered ? Color(hex: "#1A1A1A").opacity(0.04) : Color(hex: "#F8F8F6"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                isSelected ? Color(hex: "#22D3B8").opacity(0.45) : Color(hex: "#E5E5E0"),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Custom Shortcut Recorder

struct SCustomShortcutRecorder: View {
    @State private var isRecording: Bool = false
    @State private var pulse: Bool = false
    private var manager: ShortcutManager { ShortcutManager.shared }

    var body: some View {
        HStack(spacing: 8) {
            if let custom = manager.recordedShortcut {
                // Show current custom shortcut pill
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#22D3B8"))
                    Text(custom.displayText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "#22D3B8").opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#22D3B8").opacity(0.35), lineWidth: 1))

                Button {
                    manager.clearCustomShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }
                .buttonStyle(.plain)
                .help(t("Supprimer le raccourci personnalisé", "Remove custom shortcut", "Eliminar atajo personalizado", "删除自定义快捷键", "カスタムショートカットを削除", "Удалить пользовательский ярлык"))

            } else if isRecording {
                // Recording state
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#FF3B30"))
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.3 : 0.9)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                    Text(t("Appuyez sur une touche…", "Press a key…", "Pulsa una tecla…", "按下一个键…", "キーを押してください…", "Нажмите клавишу…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(hex: "#FF3B30").opacity(0.06))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#FF3B30").opacity(0.3), lineWidth: 1))

                Button(t("Annuler", "Cancel", "Cancelar", "取消", "キャンセル", "Отмена")) {
                    manager.stopRecording()
                    isRecording = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#888880"))

            } else {
                // Record button
                Button {
                    isRecording = true
                    manager.startRecording { recorded in
                        manager.recordedShortcut = recorded
                        isRecording = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(t("Enregistrer", "Record", "Grabar", "录制", "記録", "Записать"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#1A1A1A"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#F0F0EE"))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#E5E5E0"), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isRecording)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: manager.recordedShortcut)
    }
}

// MARK: - Qwen Model Card

private struct QwenModelCard: View {
    @State private var formatter = AdvancedLLMFormatter.shared
    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        SettingsCard {
            if formatter.isInstalling {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#22D3B8").opacity(0.1))
                                .frame(width: 30, height: 30)
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#22D3B8"))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Qwen2.5-1.5B-Instruct-4bit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            Text(L10n.ui(for: lang, fr: "Téléchargement en cours…", en: "Downloading…", es: "Descargando…", zh: "正在下载…", ja: "ダウンロード中…", ru: "Загрузка…"))
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                        }
                        Spacer()
                        Text("\(Int(formatter.downloadProgress * 100))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundColor(Color(hex: "#22D3B8"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    ProgressView(value: formatter.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Color(hex: "#22D3B8"))
                        .animation(.easeInOut(duration: 0.3), value: formatter.downloadProgress)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            } else if AppState.shared.advancedModeInstalled {
                SettingsRow(
                    icon: "brain.head.profile",
                    iconColor: Color(hex: "#22D3B8"),
                    title: "Qwen2.5-1.5B-Instruct-4bit",
                    subtitle: L10n.ui(for: lang, fr: "Installé · IA locale prête", en: "Installed · local AI ready", es: "Instalado · IA local lista", zh: "已安装 · 本地 AI 就绪", ja: "インストール済み · ローカル AI 準備完了", ru: "Установлен · локальный ИИ готов"),
                    showDivider: false
                ) {
                    Button(L10n.ui(for: lang, fr: "Supprimer", en: "Remove", es: "Eliminar", zh: "删除", ja: "削除", ru: "Удалить")) {
                        AdvancedLLMFormatter.shared.unload()
                        AppState.shared.advancedModeInstalled = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#FF3B30"))
                }
            } else {
                SettingsRow(
                    icon: "arrow.down.circle.fill",
                    iconColor: Color(hex: "#AF52DE"),
                    title: "Qwen2.5-1.5B-Instruct-4bit",
                    subtitle: L10n.ui(for: lang, fr: "~900 Mo · IA locale sur Apple Silicon", en: "~900 MB · Local AI on Apple Silicon", es: "~900 MB · IA local en Apple Silicon", zh: "~900 MB · Apple Silicon 本地 AI", ja: "~900 MB · Apple Silicon ローカル AI", ru: "~900 МБ · локальный ИИ на Apple Silicon"),
                    showDivider: false
                ) {
                    if let error = formatter.installError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#FF3B30"))
                            .lineLimit(2)
                            .frame(maxWidth: 160, alignment: .trailing)
                    } else {
                        Button(L10n.ui(for: lang, fr: "Installer", en: "Install", es: "Instalar", zh: "安装", ja: "インストール", ru: "Установить")) {
                            Task { await AdvancedLLMFormatter.shared.installModel() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#AF52DE"))
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 780, height: 580)
}
