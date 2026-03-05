//
//  MainView.swift
//  Zphyr
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum MainAlert: Identifiable {
    case error(String)

    var id: String {
        switch self {
        case .error(let message):
            return "error:\(message)"
        }
    }
}

struct MainView: View {
    @State private var selectedItem: SidebarItem = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    private var engine: DictationEngine { DictationEngine.shared }
    @Bindable private var appState = AppState.shared
    private var activeAlertBinding: Binding<MainAlert?> {
        Binding(
            get: {
                if let message = appState.error {
                    return .error(message)
                }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                appState.error = nil
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedItem, onSettingsTapped: { showSettings = true })
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedItem {
                case .home:
                    HomeView()
                case .dictionary:
                    DictionaryView()
                case .audioTranscription:
                    AudioTranscriptionView()
                case .snippets:
                    SnippetsView()
                case .style:
                    StyleView()
                case .settings:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            appState.refreshPerformanceProfile()
            engine.refreshASRBackendSelection()
            // Pre-load ASR model in background on launch
            await engine.loadModel()
            if AppState.shared.modelStatus.isReady {
                ShortcutManager.shared.startListening()
            }
        }
        // Settings modal overlay (tap backdrop to dismiss)
        .overlay {
            if showSettings {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { showSettings = false }

                    SettingsView()
                        .frame(width: 720, height: 520)
                        .colorScheme(.light)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.22), radius: 40, x: 0, y: 12)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: showSettings)
        .alert(item: activeAlertBinding) { alert in
            switch alert {
            case .error(let message):
                return Alert(
                    title: Text(t("Erreur", "Error", "Error", "错误", "エラー", "Ошибка")),
                    message: Text(message),
                    dismissButton: .default(Text(t("OK", "OK", "OK", "确定", "OK", "ОК"))) {
                        appState.error = nil
                    }
                )
            }
        }
    }
}

// MARK: - Placeholder View
struct PlaceholderView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#1A1A1A").opacity(0.05))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "#BBBBBB"))
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .lineSpacing(3)
            }

            Text(t("Bientôt disponible", "Coming soon", "Próximamente", "即将推出", "近日公開", "Скоро будет"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#888880"))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(hex: "#888880").opacity(0.1))
                .cornerRadius(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#F7F7F5"))
    }
}

// MARK: - Snippets View

private enum SnippetPreviewContext: String, CaseIterable, Identifiable {
    case general = "general"
    case email = "email"
    case social = "social"

    var id: String { rawValue }

    func label(for languageCode: String) -> String {
        switch self {
        case .general:
            return L10n.ui(for: languageCode, fr: "Général", en: "General", es: "General", zh: "通用", ja: "一般", ru: "Общий")
        case .email:
            return L10n.ui(for: languageCode, fr: "Email", en: "Email", es: "Correo", zh: "邮件", ja: "メール", ru: "Почта")
        case .social:
            return L10n.ui(for: languageCode, fr: "Social", en: "Social", es: "Social", zh: "社交", ja: "SNS", ru: "Соцсети")
        }
    }
}

private enum SnippetKind: CaseIterable, Identifiable {
    case linkedIn
    case social
    case gmail

    var id: String {
        switch self {
        case .linkedIn: return "linkedin"
        case .social: return "social"
        case .gmail: return "gmail"
        }
    }

    func title(for languageCode: String) -> String {
        switch self {
        case .linkedIn:
            return L10n.ui(for: languageCode, fr: "LinkedIn", en: "LinkedIn", es: "LinkedIn", zh: "LinkedIn", ja: "LinkedIn", ru: "LinkedIn")
        case .social:
            return L10n.ui(for: languageCode, fr: "Réseaux sociaux", en: "Social media", es: "Redes sociales", zh: "社交媒体", ja: "SNS", ru: "Соцсети")
        case .gmail:
            return L10n.ui(for: languageCode, fr: "Contact email", en: "Contact email", es: "Correo de contacto", zh: "联系邮箱", ja: "連絡先メール", ru: "Контактный email")
        }
    }

    func triggerPhrase(for languageCode: String) -> String {
        switch self {
        case .linkedIn:
            return L10n.ui(
                for: languageCode,
                fr: "« ajoute-nous sur LinkedIn »",
                en: "\"add us on LinkedIn\"",
                es: "\"añádenos en LinkedIn\"",
                zh: "“在 LinkedIn 上关注我们”",
                ja: "「LinkedInで私たちをフォロー」",
                ru: "\"добавьте нас в LinkedIn\""
            )
        case .social:
            return L10n.ui(
                for: languageCode,
                fr: "« ajoute-nous sur notre réseau social »",
                en: "\"follow us on social media\"",
                es: "\"síguenos en redes sociales\"",
                zh: "“在社交媒体上关注我们”",
                ja: "「SNSで私たちをフォロー」",
                ru: "\"подпишитесь на нас в соцсетях\""
            )
        case .gmail:
            return L10n.ui(
                for: languageCode,
                fr: "« contacte-nous sur notre Gmail »",
                en: "\"contact us on Gmail\"",
                es: "\"contáctanos por Gmail\"",
                zh: "“通过 Gmail 联系我们”",
                ja: "「Gmailでご連絡ください」",
                ru: "\"свяжитесь с нами через Gmail\""
            )
        }
    }

    var icon: String {
        switch self {
        case .linkedIn: return "link"
        case .social: return "person.2.fill"
        case .gmail: return "envelope.fill"
        }
    }
}

struct SnippetsView: View {
    @Bindable private var appState = AppState.shared
    @AppStorage(AppState.snippetLinkedInEnabledKey) private var linkedInEnabled = true
    @AppStorage(AppState.snippetSocialEnabledKey) private var socialEnabled = true
    @AppStorage(AppState.snippetGmailEnabledKey) private var gmailEnabled = true
    @AppStorage(AppState.snippetVerboseInEmailKey) private var verboseInEmail = true

    @AppStorage(AppState.snippetLinkedInURLKey) private var linkedInURL = AppState.snippetLinkedInDefaultURL
    @AppStorage(AppState.snippetSocialURLKey) private var socialURL = AppState.snippetSocialDefaultURL
    @AppStorage(AppState.snippetContactEmailKey) private var contactEmail = AppState.snippetContactDefaultEmail
    @AppStorage(AppState.snippetLinkedInTriggersKey) private var linkedInTriggers = AppState.snippetLinkedInDefaultTriggers
    @AppStorage(AppState.snippetSocialTriggersKey) private var socialTriggers = AppState.snippetSocialDefaultTriggers
    @AppStorage(AppState.snippetGmailTriggersKey) private var gmailTriggers = AppState.snippetGmailDefaultTriggers

    @State private var previewContext: SnippetPreviewContext = .general
    private var languageCode: String { appState.selectedLanguage.id }

    private var linkedInDefaultTriggers: String {
        L10n.defaultSnippetTriggers(for: .linkedIn, languageCode: languageCode)
    }

    private var socialDefaultTriggers: String {
        L10n.defaultSnippetTriggers(for: .social, languageCode: languageCode)
    }

    private var gmailDefaultTriggers: String {
        L10n.defaultSnippetTriggers(for: .gmail, languageCode: languageCode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Snippets", "Snippets", "Snippets", "片段", "スニペット", "Сниппеты"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(
                        t(
                            "Transformez des phrases vocales en liens (LinkedIn, réseaux sociaux, contact email) selon le contexte.",
                            "Turn voice phrases into links (LinkedIn, social media, contact email) based on context.",
                            "Convierte frases de voz en enlaces (LinkedIn, redes sociales, email de contacto) según el contexto.",
                            "根据上下文将语音短语转换为链接（LinkedIn、社交媒体、联系邮箱）。",
                            "文脈に応じて音声フレーズをリンク（LinkedIn、SNS、連絡先メール）に変換します。",
                            "Преобразуйте голосовые фразы в ссылки (LinkedIn, соцсети, контактный email) в зависимости от контекста."
                        )
                    )
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#888880"))
                }

                snippetsActivationCard
                destinationsCard
                triggersCard
                contextualOutputCard
                previewCard
                if let notice = appState.advancedFeaturesNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#F0F0EE"))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 26)
        }
        .background(Color(hex: "#F7F7F5"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.light)
        .onChange(of: languageCode) { _, _ in
            resetKnownDefaultTriggersToCurrentLanguageIfNeeded()
        }
        .onAppear {
            resetKnownDefaultTriggersToCurrentLanguageIfNeeded()
        }
    }

    private var snippetsActivationCard: some View {
        VStack(spacing: 0) {
            SnippetToggleRow(
                icon: "link",
                iconColor: Color(hex: "#007AFF"),
                title: t("Snippet LinkedIn", "LinkedIn snippet", "Snippet LinkedIn", "LinkedIn 片段", "LinkedIn スニペット", "Сниппет LinkedIn"),
                subtitle: t("Remplace les formulations vocales LinkedIn par votre URL",
                            "Replace LinkedIn voice phrases with your URL",
                            "Reemplaza frases de LinkedIn por tu URL",
                            "将 LinkedIn 语音短语替换为你的 URL",
                            "LinkedIn の音声フレーズをあなたの URL に置換",
                            "Заменяет голосовые фразы LinkedIn на ваш URL"),
                isOn: $linkedInEnabled
            )
            Divider().padding(.leading, 58)
            SnippetToggleRow(
                icon: "person.2.fill",
                iconColor: Color(hex: "#34C759"),
                title: t("Snippet Réseaux sociaux", "Social snippet", "Snippet redes sociales", "社交片段", "SNS スニペット", "Сниппет соцсетей"),
                subtitle: t("Remplace les formulations réseau social par votre lien principal",
                            "Replace social-media phrases with your main link",
                            "Reemplaza frases de redes sociales por tu enlace principal",
                            "将社交媒体短语替换为你的主链接",
                            "SNS 関連フレーズをメインリンクに置換",
                            "Заменяет фразы о соцсетях на вашу основную ссылку"),
                isOn: $socialEnabled
            )
            Divider().padding(.leading, 58)
            SnippetToggleRow(
                icon: "envelope.fill",
                iconColor: Color(hex: "#FF9500"),
                title: t("Snippet Contact email", "Contact email snippet", "Snippet correo de contacto", "联系邮箱片段", "連絡先メールスニペット", "Сниппет контактного email"),
                subtitle: t("Remplace les formulations Gmail par un lien mailto:",
                            "Replace Gmail phrases with a mailto: link",
                            "Reemplaza frases de Gmail por un enlace mailto:",
                            "将 Gmail 短语替换为 mailto: 链接",
                            "Gmail フレーズを mailto: リンクに置換",
                            "Заменяет фразы Gmail на ссылку mailto:"),
                isOn: $gmailEnabled
            )
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var destinationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Destinations", "Destinations", "Destinos", "目标地址", "宛先", "Назначения"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            SnippetFieldRow(
                label: t("URL LinkedIn", "LinkedIn URL", "URL de LinkedIn", "LinkedIn URL", "LinkedIn URL", "URL LinkedIn"),
                placeholder: "https://www.linkedin.com/company/...",
                text: $linkedInURL,
                isEnabled: linkedInEnabled
            )
            SnippetFieldRow(
                label: t("URL Réseaux sociaux", "Social URL", "URL de redes sociales", "社交链接 URL", "SNS URL", "URL соцсетей"),
                placeholder: "https://linktr.ee/...",
                text: $socialURL,
                isEnabled: socialEnabled
            )
            SnippetFieldRow(
                label: t("Email de contact", "Contact email", "Email de contacto", "联系邮箱", "連絡先メール", "Контактный email"),
                placeholder: "contact@votre-domaine.com",
                text: $contactEmail,
                isEnabled: gmailEnabled
            )

            Text(
                t("Ces valeurs sont utilisées par la dictée vocale au moment de l’insertion.",
                  "These values are used by voice dictation during insertion.",
                  "Estos valores se usan durante la inserción por dictado de voz.",
                  "这些值会在语音插入时使用。",
                  "これらの値は音声入力の挿入時に使用されます。",
                  "Эти значения используются при вставке из голосовой диктовки.")
            )
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#AAAAAA"))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var contextualOutputCard: some View {
        VStack(spacing: 0) {
            SnippetToggleRow(
                icon: "text.bubble.fill",
                iconColor: Color(hex: "#AF52DE"),
                title: t("Mode phrase complète en email", "Full sentence mode in email", "Modo frase completa en email", "邮件完整句模式", "メールで完全文モード", "Режим полной фразы в email"),
                subtitle: t("Dans les apps mail, insère « Retrouvez-nous sur… » au lieu d’un lien brut",
                            "In mail apps, insert “Find us on…” instead of a raw link",
                            "En apps de correo, inserta “Encuéntranos en…” en lugar de un enlace bruto",
                            "在邮件应用中，插入“可在…找到我们”，而不是裸链接",
                            "メールアプリでは生リンクの代わりに「…でご覧ください」を挿入",
                            "В почтовых приложениях вставляет «Найдите нас на…» вместо сырой ссылки"),
                isOn: $verboseInEmail
            )
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var triggersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Phrases déclencheuses", "Trigger phrases", "Frases activadoras", "触发短语", "トリガーフレーズ", "Триггерные фразы"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            SnippetTriggersEditor(
                title: t("LinkedIn", "LinkedIn", "LinkedIn", "LinkedIn", "LinkedIn", "LinkedIn"),
                subtitle: t("Une phrase par ligne", "One phrase per line", "Una frase por línea", "每行一句", "1行に1フレーズ", "Одна фраза на строку"),
                text: $linkedInTriggers,
                defaultText: linkedInDefaultTriggers,
                isEnabled: linkedInEnabled
            )
            SnippetTriggersEditor(
                title: t("Réseaux sociaux", "Social media", "Redes sociales", "社交媒体", "SNS", "Соцсети"),
                subtitle: t("Une phrase par ligne", "One phrase per line", "Una frase por línea", "每行一句", "1行に1フレーズ", "Одна фраза на строку"),
                text: $socialTriggers,
                defaultText: socialDefaultTriggers,
                isEnabled: socialEnabled
            )
            SnippetTriggersEditor(
                title: t("Contact email", "Contact email", "Correo de contacto", "联系邮箱", "連絡先メール", "Контактный email"),
                subtitle: t("Une phrase par ligne", "One phrase per line", "Una frase por línea", "每行一句", "1行に1フレーズ", "Одна фраза на строку"),
                text: $gmailTriggers,
                defaultText: gmailDefaultTriggers,
                isEnabled: gmailEnabled
            )

            Text(
                t("Les phrases sont insensibles à la casse. Vous pouvez aussi séparer avec des virgules.",
                  "Phrases are case-insensitive. You can also separate with commas.",
                  "Las frases no distinguen mayúsculas. También puedes separar con comas.",
                  "短语不区分大小写，也可以用逗号分隔。",
                  "フレーズは大文字小文字を区別しません。カンマ区切りも可能です。",
                  "Фразы нечувствительны к регистру. Также можно разделять запятыми.")
            )
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#AAAAAA"))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Aperçu", "Preview", "Vista previa", "预览", "プレビュー", "Предпросмотр"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Spacer()
                Picker(t("Contexte", "Context", "Contexto", "上下文", "コンテキスト", "Контекст"), selection: $previewContext) {
                    ForEach(SnippetPreviewContext.allCases) { ctx in
                        Text(ctx.label(for: languageCode)).tag(ctx)
                    }
                }
                .pickerStyle(.segmented)
                .colorScheme(.light)
                .frame(width: 280)
            }

            VStack(spacing: 10) {
                ForEach(SnippetKind.allCases) { kind in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#888880"))
                            .frame(width: 14)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.triggerPhrase(for: languageCode))
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#666663"))
                            Text(previewOutput(for: kind))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var linkedInValue: String {
        let trimmed = linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppState.snippetLinkedInDefaultURL : trimmed
    }

    private var socialValue: String {
        let trimmed = socialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppState.snippetSocialDefaultURL : trimmed
    }

    private var mailtoValue: String {
        let trimmed = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.isEmpty ? AppState.snippetContactDefaultEmail : trimmed
        return raw.lowercased().hasPrefix("mailto:") ? raw : "mailto:\(raw)"
    }

    private func isEnabled(_ kind: SnippetKind) -> Bool {
        switch kind {
        case .linkedIn: return linkedInEnabled
        case .social: return socialEnabled
        case .gmail: return gmailEnabled
        }
    }

    private func previewOutput(for kind: SnippetKind) -> String {
        guard isEnabled(kind) else {
            return t("Désactivé", "Disabled", "Desactivado", "已禁用", "無効", "Отключено")
        }

        switch (previewContext, kind) {
        case (.email, .linkedIn):
            return verboseInEmail
                ? L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur LinkedIn : \(linkedInValue)",
                    en: "Find us on LinkedIn: \(linkedInValue)",
                    es: "Encuéntranos en LinkedIn: \(linkedInValue)",
                    zh: "在 LinkedIn 上找到我们：\(linkedInValue)",
                    ja: "LinkedInはこちら: \(linkedInValue)",
                    ru: "Найдите нас в LinkedIn: \(linkedInValue)"
                )
                : linkedInValue
        case (.email, .social):
            return verboseInEmail
                ? L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur nos réseaux sociaux : \(socialValue)",
                    en: "Find us on social media: \(socialValue)",
                    es: "Encuéntranos en redes sociales: \(socialValue)",
                    zh: "在社交媒体找到我们：\(socialValue)",
                    ja: "SNSはこちら: \(socialValue)",
                    ru: "Найдите нас в соцсетях: \(socialValue)"
                )
                : socialValue
        case (.email, .gmail):
            return verboseInEmail
                ? L10n.ui(
                    for: languageCode,
                    fr: "Contactez-nous : \(mailtoValue)",
                    en: "Contact us: \(mailtoValue)",
                    es: "Contáctanos: \(mailtoValue)",
                    zh: "联系我们：\(mailtoValue)",
                    ja: "お問い合わせ: \(mailtoValue)",
                    ru: "Свяжитесь с нами: \(mailtoValue)"
                )
                : mailtoValue
        case (_, .linkedIn):
            return linkedInValue
        case (_, .social):
            return socialValue
        case (_, .gmail):
            return mailtoValue
        }
    }

    private func resetKnownDefaultTriggersToCurrentLanguageIfNeeded() {
        let linkedInDefaults = knownDefaults(for: .linkedIn)
        if linkedInDefaults.contains(linkedInTriggers.trimmingCharacters(in: .whitespacesAndNewlines)) {
            linkedInTriggers = linkedInDefaultTriggers
        }

        let socialDefaults = knownDefaults(for: .social)
        if socialDefaults.contains(socialTriggers.trimmingCharacters(in: .whitespacesAndNewlines)) {
            socialTriggers = socialDefaultTriggers
        }

        let gmailDefaults = knownDefaults(for: .gmail)
        if gmailDefaults.contains(gmailTriggers.trimmingCharacters(in: .whitespacesAndNewlines)) {
            gmailTriggers = gmailDefaultTriggers
        }
    }

    private func knownDefaults(for kind: SnippetTriggerKind) -> Set<String> {
        let codes = ["fr", "en", "es", "zh", "ja", "ru"]
        return Set(codes.map {
            L10n.defaultSnippetTriggers(for: kind, languageCode: $0).trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }
}

// MARK: - Audio Transcription View

struct AudioTranscriptionView: View {
    @Bindable private var appState = AppState.shared
    @State private var selectedLanguage: WhisperLanguage = AppState.shared.selectedLanguage
    @State private var selectedAudioURL: URL?
    @State private var isImportingFile = false
    @State private var isTranscribing = false
    @State private var transcriptionText = ""
    @State private var copied = false

    private var engine: DictationEngine { DictationEngine.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                languageCard
                fileCard
                actionCard
                if !transcriptionText.isEmpty {
                    resultCard
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 26)
        }
        .background(Color(hex: "#F7F7F5"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.light)
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedAudioURL = urls.first
            case .failure(let error):
                appState.error = L10n.ui(
                    for: appState.selectedLanguage.id,
                    fr: "Import audio échoué : \(error.localizedDescription)",
                    en: "Audio import failed: \(error.localizedDescription)",
                    es: "La importación de audio falló: \(error.localizedDescription)",
                    zh: "音频导入失败：\(error.localizedDescription)",
                    ja: "音声の読み込みに失敗しました: \(error.localizedDescription)",
                    ru: "Ошибка импорта аудио: \(error.localizedDescription)"
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("Retranscription audio", "Audio transcription", "Transcripción de audio", "音频转写", "音声文字起こし", "Транскрибация аудио"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
            Text(
                t("Importez un fichier audio, choisissez la langue, puis lancez la retranscription locale avec Qwen3-ASR.",
                  "Import an audio file, choose a language, then run local transcription with Qwen3-ASR.",
                  "Importa un archivo de audio, elige el idioma y lanza la transcripción local con Qwen3-ASR.",
                  "导入音频文件，选择语言，然后用 Qwen3-ASR 本地转写。",
                  "音声ファイルを読み込み、言語を選んで Qwen3-ASR でローカル文字起こしを実行します。",
                  "Импортируйте аудиофайл, выберите язык и запустите локальную транскрибацию через Qwen3-ASR.")
            )
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#888880"))
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Langue", "Language", "Idioma", "语言", "言語", "Язык"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            Menu {
                ForEach(WhisperLanguage.all) { language in
                    Button {
                        selectedLanguage = language
                    } label: {
                        HStack {
                            Text("\(language.flag)  \(language.name)")
                            if language == selectedLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(selectedLanguage.flag)  \(selectedLanguage.name)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#888880"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "#B8B8B4"), lineWidth: 1.5)
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .frame(width: 260, alignment: .leading)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Fichier audio", "Audio file", "Archivo de audio", "音频文件", "音声ファイル", "Аудиофайл"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Spacer()
                Button {
                    isImportingFile = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(t("Importer", "Import", "Importar", "导入", "読み込む", "Импорт"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#1A1A1A"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(selectedAudioURL?.lastPathComponent
                 ?? t("Aucun fichier sélectionné", "No file selected", "Ningún archivo seleccionado", "未选择文件", "ファイル未選択", "Файл не выбран"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selectedAudioURL == nil ? Color(hex: "#AAAAAA") : Color(hex: "#1A1A1A"))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#F5F5F3"))
                .cornerRadius(10)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Task { await runTranscription() }
                } label: {
                    HStack(spacing: 6) {
                        if isTranscribing {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.white)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(
                            isTranscribing
                            ? t("Retranscription…", "Transcribing…", "Transcribiendo…", "转写中…", "文字起こし中…", "Транскрибация…")
                            : t("Lancer la retranscription", "Start transcription", "Iniciar transcripción", "开始转写", "文字起こしを開始", "Начать транскрибацию")
                        )
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canTranscribe ? Color(hex: "#1A1A1A") : Color(hex: "#BBBBBB"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canTranscribe)

                if !appState.modelStatus.isReady {
                    Text(t("Le modèle sera chargé automatiquement si nécessaire.",
                           "The model will be loaded automatically if needed.",
                           "El modelo se cargará automáticamente si es necesario.",
                           "如有需要将自动加载模型。",
                           "必要に応じてモデルを自動読み込みします。",
                           "Модель загрузится автоматически при необходимости."))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Résultat", "Result", "Resultado", "结果", "結果", "Результат"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcriptionText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(
                        copied
                        ? t("Copié", "Copied", "Copiado", "已复制", "コピー済み", "Скопировано")
                        : t("Copier", "Copy", "Copiar", "复制", "コピー", "Копировать"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: copied ? "#34C759" : "#666663"))
                }
                .buttonStyle(.plain)

                Button {
                    exportTranscription()
                } label: {
                    Label(
                        t("Exporter", "Export", "Exportar", "导出", "書き出し", "Экспорт"),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#666663"))
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $transcriptionText)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(8)
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .background(Color(hex: "#F5F5F3"))
                .cornerRadius(10)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var canTranscribe: Bool {
        selectedAudioURL != nil && !isTranscribing
    }

    private func runTranscription() async {
        guard let selectedAudioURL else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        if !appState.modelStatus.isReady {
            await engine.loadModel()
        }

        let hasSecurityAccess = selectedAudioURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                selectedAudioURL.stopAccessingSecurityScopedResource()
            }
        }

        let text = await engine.transcribeAudioFile(at: selectedAudioURL, language: selectedLanguage)
        if !text.isEmpty {
            transcriptionText = text
        }
    }

    private func exportTranscription() {
        let panel = NSSavePanel()
        panel.title = t("Exporter la retranscription", "Export transcription", "Exportar transcripción", "导出转写", "文字起こしをエクスポート", "Экспорт транскрибации")
        panel.nameFieldStringValue = "zphyr-audio-transcription.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? transcriptionText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct SnippetToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#AAAAAA"))
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SnippetFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let isEnabled: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#888880"))
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder)
                    .foregroundColor(Color(hex: "#B6B6B1"))
            )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isEnabled ? Color(hex: "#1A1A1A") : Color(hex: "#8E8E88"))
                .accentColor(Color(hex: "#22D3B8"))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isEnabled ? Color.white : Color(hex: "#F3F3F0"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isFocused && isEnabled ? Color(hex: "#1A1A1A") : Color(hex: "#E2E2DE"),
                            lineWidth: isFocused && isEnabled ? 1.4 : 1
                        )
                )
                .focused($isFocused)
                .textSelection(.enabled)
                .allowsHitTesting(isEnabled)
                .opacity(isEnabled ? 1 : 0.75)
        }
    }
}

private struct SnippetTriggersEditor: View {
    let title: String
    let subtitle: String
    @Binding var text: String
    let defaultText: String
    let isEnabled: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#888880"))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                }
                Spacer()
                Button(t("Réinitialiser", "Reset", "Restablecer", "重置", "リセット", "Сбросить")) {
                    text = defaultText
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#666663"))
            }

            TextEditor(text: $text)
                .font(.system(size: 12))
                .foregroundColor(isEnabled ? Color(hex: "#1A1A1A") : Color(hex: "#8E8E88"))
                .accentColor(Color(hex: "#22D3B8"))
                .padding(8)
                .frame(minHeight: 74, maxHeight: 90)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isEnabled ? Color.white : Color(hex: "#F3F3F0"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isFocused && isEnabled ? Color(hex: "#1A1A1A") : Color(hex: "#E2E2DE"),
                            lineWidth: isFocused && isEnabled ? 1.4 : 1
                        )
                )
                .focused($isFocused)
                .textSelection(.enabled)
                .allowsHitTesting(isEnabled)
                .opacity(isEnabled ? 1 : 0.75)
        }
    }
}


#Preview {
    MainView()
        .frame(width: 960, height: 640)
}
