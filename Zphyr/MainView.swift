//
//  MainView.swift
//  Zphyr
//

import SwiftUI

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
                case .snippets:
                    SnippetsView()
                case .style:
                    StyleView()
                case .settings:
                    EmptyView()
                case .account:
                    AccountView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            // Pre-load Whisper model in background on launch
            await engine.loadModel()
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
                .tint(Color(hex: "#1A1A1A"))
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
                .tint(Color(hex: "#1A1A1A"))
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
