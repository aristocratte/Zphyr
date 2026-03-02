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

            // Dictation language
            SettingsCard {
                SettingsRow(icon: "mic.fill", iconColor: Color(hex: "#34C759"),
                            title: t("Langue de dictée", "Dictation language", "Idioma de dictado", "听写语言", "音声入力言語", "Язык диктовки"),
                            subtitle: t("Langue principale reconnue par Whisper", "Primary language recognized by Whisper", "Idioma principal reconocido por Whisper", "Whisper 识别的主语言", "Whisper が認識する主要言語", "Основной язык, распознаваемый Whisper"),
                            showDivider: false) {
                    Picker("", selection: $state.selectedLanguage) {
                        ForEach(WhisperLanguage.all) { lang in
                            Text("\(lang.flag)  \(lang.name)").tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 165)
                }
            }
        }
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

            // Trigger key picker
            SettingsCard {
                SettingsRow(icon: "keyboard.chevron.compact.down", iconColor: Color(hex: "#FF6B35"),
                            title: t("Touche de déclenchement", "Trigger key", "Tecla de activación", "触发键", "起動キー", "Клавиша запуска"),
                            subtitle: ShortcutManager.shared.selectedTriggerKey.displayName(for: lang),
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

#Preview {
    SettingsView()
        .frame(width: 780, height: 580)
}
