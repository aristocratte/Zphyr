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
    private var defaultOutputProfileBinding: Binding<OutputProfile> {
        Binding(
            get: { state.defaultOutputProfile },
            set: { state.defaultOutputProfile = $0 }
        )
    }

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

            SettingsCard {
                SettingsRow(icon: "text.quote", iconColor: Color(hex: "#22D3B8"),
                            title: t("Profil de sortie par défaut", "Default output profile", "Perfil de salida por defecto", "默认输出配置", "デフォルト出力プロファイル", "Профиль вывода по умолчанию"),
                            subtitle: state.defaultOutputProfile.subtitle(for: lang),
                            showDivider: false) {
                    Picker("", selection: defaultOutputProfileBinding) {
                        ForEach(OutputProfile.allCases) { profile in
                            Text(profile.displayName(for: lang)).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }

            SettingsCard {
                SettingsRow(icon: "ladybug", iconColor: Color(hex: "#5856D6"),
                            title: t("Export debug local", "Local debug export", "Export debug local", "本地调试导出", "ローカルデバッグ書き出し", "Локальный экспорт отладки"),
                            subtitle: t("Génère session.json et summary.md pour la dernière session.", "Generates session.json and summary.md for the latest session.", "Genera session.json y summary.md para la última sesión.", "为最近一次会话生成 session.json 和 summary.md。", "直近セッションの session.json と summary.md を生成します。", "Генерирует session.json и summary.md для последней сессии."),
                            showDivider: false) {
                    Button(t("Exporter", "Export", "Exportar", "导出", "書き出し", "Экспорт")) {
                        do {
                            let exportURL = try SessionDebugExporter.shared.exportLatestSessionInteractively()
                            NSWorkspace.shared.activateFileViewerSelecting([exportURL])
                        } catch {
                            AppState.shared.error = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ProtectedTermsSettingsCard()

        }
        .onAppear {
            state.refreshPerformanceProfile()
        }
    }
}

private struct ProtectedTermsSettingsCard: View {
    @Bindable private var store = DictionaryStore.shared
    @State private var newProtectedTerm = ""
    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Glossary / protected terms", "Glossary / protected terms", "Glosario / términos protegidos", "词汇表 / 保护术语", "用語集 / 保護用語", "Глоссарий / защищенные термины"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField(
                            t("Ajouter un terme protégé", "Add a protected term", "Añadir un término protegido", "添加保护术语", "保護用語を追加", "Добавить защищенный термин"),
                            text: $newProtectedTerm
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(t("Ajouter", "Add", "Añadir", "添加", "追加", "Добавить")) {
                            let trimmed = newProtectedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            store.addProtectedTerm(trimmed)
                            newProtectedTerm = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text(
                        t("Conservation stricte dans les profils Verbatim et Technique.",
                          "Strictly preserved in Verbatim and Technical profiles.",
                          "Conservación estricta en los perfiles Verbatim y Técnico.",
                          "在 Verbatim 和 Technical 配置中严格保留。",
                          "Verbatim と Technical プロファイルで厳密に保持します。",
                          "Строго сохраняется в профилях Verbatim и Technical.")
                    )
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#888880"))

                    if store.sortedProtectedTerms.isEmpty {
                        Text(t("Aucun terme protégé défini.", "No protected terms defined.", "No hay términos protegidos.", "未定义保护术语。", "保護用語は未設定です。", "Защищенные термины не заданы."))
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#AAAAAA"))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.sortedProtectedTerms, id: \.self) { term in
                                HStack {
                                    Text(term)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(hex: "#222220"))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        if let index = store.protectedTerms.firstIndex(where: { $0 == term }) {
                                            store.removeProtectedTerms(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(hex: "#AAAAAA"))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - System Settings

struct SystemSettingsContent: View {
    @Bindable private var state = AppState.shared
    @State private var asrModelDiskSizeCache: String = "~"

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }
    private var asrDescriptor: ASRBackendDescriptor { DictationEngine.shared.currentASRDescriptor }
    private var asrRequiresInstall: Bool { asrDescriptor.requiresModelInstall }
    private var performanceProfile: PerformanceProfile { state.performanceProfile }
    private var asrModelDiskSizeRefreshToken: String {
        "\(asrDescriptor.kind.rawValue)|\(asrInstallURL?.path ?? "none")|\(state.modelStatus.isReady)"
    }

    private var asrBackendBinding: Binding<ASRBackendKind> {
        Binding(
            get: { state.preferredASRBackend },
            set: { newValue in
                state.preferredASRBackend = PerformanceRouter.shared.effectiveASRBackend(
                    preferred: newValue,
                    profile: state.performanceProfile
                )
                DictationEngine.shared.refreshASRBackendSelection()
                Task { await DictationEngine.shared.loadModel() }
            }
        )
    }

    private var formattingModeBinding: Binding<FormattingMode> {
        Binding(
            get: { state.formattingMode },
            set: { newValue in
                state.formattingMode = PerformanceRouter.shared.effectiveFormattingMode(
                    preferred: newValue,
                    profile: state.performanceProfile
                )
            }
        )
    }

    private var formattingModelBinding: Binding<FormattingModelID> {
        Binding(
            get: { state.activeFormattingModel },
            set: { newValue in
                guard newValue != state.activeFormattingModel else { return }
                state.activeFormattingModel = newValue
                Task { @MainActor in
                    AdvancedLLMFormatter.shared.unload()
                }
            }
        )
    }

    private var asrInstallURL: URL? {
        guard asrRequiresInstall else { return nil }
        let fm = FileManager.default
        if let explicitPath = state.modelInstallPath, fm.fileExists(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }
        return WhisperKitBackend.resolveInstallURL()
    }

    private var formatterInstallURL: URL? {
        AdvancedLLMFormatter.resolveInstallURL(for: state.activeFormattingModel)
    }

    private var formatterDescriptor: FormattingModelDescriptor {
        FormattingModelCatalog.descriptor(for: state.activeFormattingModel)
    }

    private var formatterInstallStatus: FormattingModelInstallStatus {
        guard state.isProModeUnlocked else {
            return .unavailable(
                t(
                    "Indisponible sur ce profil matériel.",
                    "Unavailable on this hardware profile.",
                    "No disponible en este perfil de hardware.",
                    "此硬件配置不可用。",
                    "このハードウェアプロファイルでは利用できません。",
                    "Недоступно на этом профиле железа."
                )
            )
        }
        return AdvancedLLMFormatter.shared.installStatus(for: state.activeFormattingModel)
    }

    private var formatterInstallStatusText: String {
        switch formatterInstallStatus {
        case .installed:
            return t("Installé", "Installed", "Instalado", "已安装", "インストール済み", "Установлен")
        case .notInstalled:
            return t("Non installé", "Not installed", "No instalado", "未安装", "未インストール", "Не установлен")
        case .downloading(let progress):
            return t("Téléchargement \(Int(progress * 100))%", "Downloading \(Int(progress * 100))%", "Descargando \(Int(progress * 100))%", "下载中 \(Int(progress * 100))%", "ダウンロード中 \(Int(progress * 100))%", "Загрузка \(Int(progress * 100))%")
        case .preparing:
            return t("Préparation…", "Preparing…", "Preparando…", "准备中…", "準備中…", "Подготовка…")
        case .unavailable(let reason), .error(let reason):
            return reason
        }
    }

    private var formatterApproxSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: formatterDescriptor.approximateBytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Système", "System", "Sistema", "系统", "システム", "Система"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            SettingsCard {
                SettingsRow(
                    icon: "memorychip",
                    iconColor: Color(hex: "#FF9500"),
                    title: t("Profil matériel", "Hardware profile", "Perfil de hardware", "硬件配置", "ハードウェアプロファイル", "Профиль железа"),
                    subtitle: "\(performanceProfile.displayLabel(for: lang)) · \(performanceProfile.physicalMemoryGB) GB RAM",
                    showDivider: false
                ) {
                    Text(performanceProfile.tier.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(performanceProfile.tier == .pro ? Color(hex: "#22D3B8") : Color(hex: "#888880"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (performanceProfile.tier == .pro ? Color(hex: "#22D3B8") : Color(hex: "#888880"))
                                .opacity(0.12)
                        )
                        .cornerRadius(7)
                }
            }

            // Code formatting mode
            SettingsCard {
                SettingsRow(
                    icon: "textformat.alt",
                    iconColor: Color(hex: "#AF52DE"),
                    title: t("Mode de formatage", "Formatting mode", "Modo de formateo", "格式化模式", "フォーマットモード", "Режим форматирования"),
                    subtitle: state.isProModeUnlocked
                        ? state.formattingMode.subtitle(for: lang)
                        : t("Mode Éco forcé par le profil matériel (Regex déterministe).", "Eco mode enforced by hardware profile (deterministic regex).", "Modo Eco forzado por el perfil de hardware (regex determinista).", "由硬件配置强制使用节能模式（确定性正则）。", "ハードウェア構成によりエコモード固定（決定的 Regex）。", "Эко-режим принудительно включён профилем железа (детерминированные regex)."),
                    showDivider: state.formattingMode == .advanced
                ) {
                    Picker("", selection: formattingModeBinding) {
                        ForEach(FormattingMode.allCases) { mode in
                            Text(mode.displayName(for: lang))
                                .tag(mode)
                                .disabled(mode == .advanced && !state.isProModeUnlocked)
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

            SettingsCard {
                SettingsRow(
                    icon: "brain.head.profile",
                    iconColor: Color(hex: "#22D3B8"),
                    title: t("Modèle de formatage", "Formatting model", "Modelo de formateo", "格式化模型", "フォーマットモデル", "Модель форматирования"),
                    subtitle: state.activeFormattingModel.shortDescription(for: lang),
                    showDivider: true
                ) {
                    Picker("", selection: formattingModelBinding) {
                        ForEach(FormattingModelID.allCases) { modelID in
                            Text(modelID.displayName(for: lang)).tag(modelID)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                SettingsRow(
                    icon: "sparkles",
                    iconColor: Color(hex: "#AF52DE"),
                    title: t("Usage recommandé", "Recommended use", "Uso recomendado", "推荐用途", "推奨用途", "Рекомендуемое применение"),
                    subtitle: state.activeFormattingModel.recommendedUsage(for: lang),
                    showDivider: true
                ) {
                    Text(formatterApproxSizeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#666660"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#F0F0EE"))
                        .cornerRadius(7)
                }

                SettingsRow(
                    icon: "checkmark.seal",
                    iconColor: Color(hex: "#007AFF"),
                    title: t("État du modèle", "Model status", "Estado del modelo", "模型状态", "モデル状態", "Состояние модели"),
                    subtitle: formatterInstallStatusText,
                    showDivider: false
                ) {
                    Text(formatterInstallStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#007AFF"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#007AFF").opacity(0.08))
                        .cornerRadius(7)
                }
            }

            FormattingModelCard(modelID: state.activeFormattingModel)

            // Model status card
            SettingsCard {
                SettingsRow(
                    icon: "cpu",
                    iconColor: Color(hex: "#007AFF"),
                    title: t("Backend ASR", "ASR backend", "Backend ASR", "ASR 后端", "ASR バックエンド", "ASR-бэкенд"),
                    subtitle: t("Choisissez le moteur de transcription local.", "Choose your local transcription engine.", "Elige tu motor de transcripción local.", "选择本地转写引擎。", "ローカル文字起こしエンジンを選択。", "Выберите локальный движок транскрибации."),
                    showDivider: true
                ) {
                    Picker("", selection: asrBackendBinding) {
                        Text("Whisper Large v3 Turbo")
                            .tag(ASRBackendKind.whisperKit)
                            .disabled(!state.isWhisperASRUnlocked)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                SettingsRow(
                    icon: "waveform",
                    iconColor: Color(hex: "#22D3B8"),
                    title: t("Backend actif", "Active backend", "Backend activo", "当前后端", "アクティブバックエンド", "Активный бэкенд"),
                    subtitle: asrRequiresInstall
                        ? "\(asrDescriptor.displayName) · \(asrModelDiskSizeCache)"
                        : "\(asrDescriptor.displayName) · \(t("Intégré au système", "Built into the system", "Integrado en el sistema", "系统内置", "システム内蔵", "Встроен в систему"))",
                    showDivider: false
                ) {
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
                            Text(t("Sélectionnez vos langues parlées pour la dictée locale.", "Select your spoken languages for local dictation.", "Selecciona tus idiomas hablados para el dictado local.", "选择本地听写的语音语言。", "ローカル音声入力で使う言語を選択してください。", "Выберите языки для локальной диктовки."))
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

            // Install paths for both local models
            SettingsCard {
                SettingsRow(
                    icon: "folder.fill",
                    iconColor: Color(hex: "#FF9500"),
                    title: t("Chemin backend ASR", "ASR backend path", "Ruta backend ASR", "ASR 后端路径", "ASR バックエンドのパス", "Путь ASR-бэкенда"),
                    subtitle: asrRequiresInstall
                        ? (asrInstallURL?.path ?? t("Non installé", "Not installed", "No instalado", "未安装", "未インストール", "Не установлен"))
                        : t("Backend système intégré (aucun dossier modèle).", "System backend (no model folder).", "Backend del sistema (sin carpeta de modelo).", "系统后端（无模型目录）。", "システムバックエンド（モデルフォルダなし）。", "Системный бэкенд (без папки модели).")
                ) {
                    Button {
                        if let asrInstallURL {
                            NSWorkspace.shared.activateFileViewerSelecting([asrInstallURL])
                        }
                    } label: {
                        Label(t("Ouvrir", "Open", "Abrir", "打开", "開く", "Открыть"),
                              systemImage: "folder.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF9500"))
                    }
                    .buttonStyle(.plain)
                    .disabled(asrInstallURL == nil || !asrRequiresInstall)
                }

                SettingsRow(
                    icon: "folder.fill",
                    iconColor: Color(hex: "#22D3B8"),
                    title: t("Chemin modèle de formatage", "Formatting model path", "Ruta del modelo de formateo", "格式化模型路径", "フォーマットモデルのパス", "Путь модели форматирования"),
                    subtitle: formatterInstallURL?.path ?? t("Non installé", "Not installed", "No instalado", "未安装", "未インストール", "Не установлен"),
                    showDivider: false
                ) {
                    Button {
                        if let formatterInstallURL {
                            NSWorkspace.shared.activateFileViewerSelecting([formatterInstallURL])
                        }
                    } label: {
                        Label(t("Ouvrir", "Open", "Abrir", "打开", "開く", "Открыть"),
                              systemImage: "folder.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#22D3B8"))
                    }
                    .buttonStyle(.plain)
                    .disabled(formatterInstallURL == nil)
                }
            }

            // ASR model management (uninstall + reinstall)
            if asrRequiresInstall && (state.modelStatus.isReady || asrInstallURL != nil) {
                SettingsCard {
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
        .onAppear {
            state.refreshPerformanceProfile()
        }
        .task(id: asrModelDiskSizeRefreshToken) {
            await refreshASRModelDiskSizeCache()
        }
    }

    private var localDataSize: String {
        let baseKeys = [TranscriptionStore.storageKey, "zphyr.dictionary.entries"]
        let keys = baseKeys + baseKeys.map { "\($0).enc" }
        let totalBytes = keys.compactMap { UserDefaults.standard.data(forKey: $0)?.count }.reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    private func refreshASRModelDiskSizeCache() async {
        guard asrRequiresInstall else {
            asrModelDiskSizeCache = t("N/A", "N/A", "N/A", "不适用", "N/A", "Н/Д")
            return
        }
        let installURL = asrInstallURL
        let fallback = asrDescriptor.modelSizeLabel ?? "~"
        let resolved = await Task.detached(priority: .utility) {
            Self.computeASRModelDiskSize(installURL: installURL, fallbackLabel: fallback)
        }.value
        asrModelDiskSizeCache = resolved
    }

    nonisolated private static func computeASRModelDiskSize(installURL: URL?, fallbackLabel: String) -> String {
        guard let url = installURL else { return fallbackLabel }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                              options: [.skipsHiddenFiles], errorHandler: nil) else { return "~2.46 GB" }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: keys), vals.isRegularFile == true else { continue }
            total += Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? vals.fileSize ?? 0)
        }
        guard total > 0 else { return "~2.46 GB" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        if !asrRequiresInstall {
            Label(t("Système", "System", "Sistema", "系统", "システム", "Система"), systemImage: "apple.logo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#007AFF"))
                .labelStyle(.titleAndIcon)
        } else {
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

// MARK: - Formatting Model Card

private struct FormattingModelCard: View {
    let modelID: FormattingModelID
    @State private var formatter = AdvancedLLMFormatter.shared
    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }
    private var descriptor: FormattingModelDescriptor { FormattingModelCatalog.descriptor(for: modelID) }

    private var isModelOnDisk: Bool {
        AdvancedLLMFormatter.resolveInstallURL(for: modelID) != nil
    }

    private var modelStatus: FormattingModelInstallStatus {
        guard AppState.shared.isProModeUnlocked else {
            return .unavailable(L10n.ui(for: lang, fr: "Indisponible sur ce profil matériel.", en: "Unavailable on this hardware profile.", es: "No disponible en este perfil de hardware.", zh: "此硬件配置不可用。", ja: "このハードウェアプロファイルでは利用できません。", ru: "Недоступно на этом профиле железа."))
        }
        return formatter.installStatus(for: modelID)
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: descriptor.approximateBytes, countStyle: .file)
    }

    var body: some View {
        SettingsCard {
            if formatter.isInstalling && formatter.installingModelID == modelID {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modelID.displayName(for: lang))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            HStack(spacing: 5) {
                                if !formatter.downloadedMB.isEmpty {
                                    Text(formatter.downloadedMB)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color(hex: "#666660"))
                                }
                                if !formatter.downloadSpeed.isEmpty {
                                    Text("·")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "#AAAAAA"))
                                    Text(formatter.downloadSpeed)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color(hex: "#22D3B8"))
                                } else {
                                    Text(L10n.ui(for: lang, fr: "Téléchargement…", en: "Downloading…", es: "Descargando…", zh: "正在下载…", ja: "ダウンロード中…", ru: "Загрузка…"))
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "#AAAAAA"))
                                }
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Text("\(Int(formatter.downloadProgress * 100))%")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundColor(Color(hex: "#22D3B8"))
                            Button(L10n.ui(for: lang, fr: "Annuler", en: "Cancel", es: "Cancelar", zh: "取消", ja: "キャンセル", ru: "Отмена")) {
                                formatter.cancelInstall()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#FF3B30"))
                        }
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
            } else if isModelOnDisk {
                SettingsRow(
                    icon: "brain.head.profile",
                    iconColor: Color(hex: "#22D3B8"),
                    title: modelID.displayName(for: lang),
                    subtitle: "\(L10n.ui(for: lang, fr: "Installé · IA locale prête", en: "Installed · local AI ready", es: "Instalado · IA local lista", zh: "已安装 · 本地 AI 就绪", ja: "インストール済み · ローカル AI 準備完了", ru: "Установлен · локальный ИИ готов")) · \(sizeLabel)",
                    showDivider: false
                ) {
                    HStack(spacing: 12) {
                        Button(L10n.ui(for: lang, fr: "Recharger", en: "Reload", es: "Recargar", zh: "重新加载", ja: "再読み込み", ru: "Перезагрузить")) {
                            formatter.unload()
                            Task {
                                await formatter.loadIfInstalled(modelID: modelID)
                                await formatter.warmup()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#007AFF"))

                        Button(L10n.ui(for: lang, fr: "Supprimer", en: "Remove", es: "Eliminar", zh: "删除", ja: "削除", ru: "Удалить")) {
                            formatter.unload()
                            AdvancedLLMFormatter.removeModelFromDisk(modelID: modelID)
                            AppState.shared.syncActiveFormattingModelInstallState()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                    }
                }

                // RAM resident warning — shown only when model is actually loaded in memory
                if formatter.loadedModelID == modelID {
                    Divider()
                        .padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#FF9500"))
                        Text(L10n.ui(for: lang,
                            fr: "Modèle chargé en RAM (\(sizeLabel)) — peut réduire la mémoire disponible pour d'autres applications gourmandes.",
                            en: "Model loaded in RAM (\(sizeLabel)) — may reduce available memory for other resource-intensive apps.",
                            es: "Modelo cargado en RAM (\(sizeLabel)) — puede reducir la memoria disponible para otras apps exigentes.",
                            zh: "模型已载入内存（\(sizeLabel)）— 可能影响其他高内存占用应用的可用空间。",
                            ja: "モデルがRAMに読み込まれています（\(sizeLabel)）— 他のメモリ集約型アプリに影響する場合があります。",
                            ru: "Модель загружена в ОЗУ (\(sizeLabel)) — может сократить доступную память для ресурсоёмких приложений."
                        ))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#7A4A00"))
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#FF9500").opacity(0.08))
                }
            } else {
                let subtitle: String = {
                    switch modelStatus {
                    case .unavailable(let reason), .error(let reason):
                        return reason
                    default:
                        return "\(sizeLabel) · \(modelID.shortDescription(for: lang))"
                    }
                }()

                SettingsRow(
                    icon: {
                        switch modelStatus {
                        case .unavailable, .error:
                            return "exclamationmark.triangle.fill"
                        default:
                            return "arrow.down.circle.fill"
                        }
                    }(),
                    iconColor: {
                        switch modelStatus {
                        case .unavailable, .error:
                            return Color(hex: "#FF9500")
                        default:
                            return Color(hex: "#AF52DE")
                        }
                    }(),
                    title: modelID.displayName(for: lang),
                    subtitle: subtitle,
                    showDivider: false
                ) {
                    switch modelStatus {
                    case .unavailable:
                        Text(L10n.ui(for: lang, fr: "Indisponible", en: "Unavailable", es: "No disponible", zh: "不可用", ja: "利用不可", ru: "Недоступно"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF9500"))
                    case .error:
                        Button(L10n.ui(for: lang, fr: "Réessayer", en: "Retry", es: "Reintentar", zh: "重试", ja: "再試行", ru: "Повторить")) {
                            Task { await formatter.installModel(modelID: modelID) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9500"))
                    default:
                        Button(L10n.ui(for: lang, fr: "Installer", en: "Install", es: "Instalar", zh: "安装", ja: "インストール", ru: "Установить")) {
                            Task { await formatter.installModel(modelID: modelID) }
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
