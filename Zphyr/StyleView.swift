//
//  StyleView.swift
//  Zphyr
//
//  Clean, minimal style picker — one context at a time, simple row selection.
//

import SwiftUI

// MARK: - Context tab

private enum StyleContext: String, CaseIterable, Identifiable {
    case personal = "personal"
    case work     = "work"
    case email    = "email"
    case other    = "other"

    var id: String { rawValue }

    func label(for languageCode: String) -> String {
        switch self {
        case .personal:
            return L10n.ui(for: languageCode, fr: "Messages perso", en: "Personal messages", es: "Mensajes personales", zh: "个人消息", ja: "個人メッセージ", ru: "Личные сообщения")
        case .work:
            return L10n.ui(for: languageCode, fr: "Messages pro", en: "Work messages", es: "Mensajes de trabajo", zh: "工作消息", ja: "仕事メッセージ", ru: "Рабочие сообщения")
        case .email:
            return L10n.ui(for: languageCode, fr: "E-mail", en: "Email", es: "Correo", zh: "邮件", ja: "メール", ru: "Почта")
        case .other:
            return L10n.ui(for: languageCode, fr: "Autres apps", en: "Other apps", es: "Otras apps", zh: "其他应用", ja: "その他のアプリ", ru: "Другие приложения")
        }
    }

    func contextNote(for languageCode: String) -> String {
        switch self {
        case .personal:
            return L10n.ui(for: languageCode, fr: "S'applique dans les messageries personnelles", en: "Applies in personal messaging apps", es: "Se aplica en apps de mensajería personal", zh: "适用于个人聊天应用", ja: "個人向けメッセージアプリで適用", ru: "Применяется в личных мессенджерах")
        case .work:
            return L10n.ui(for: languageCode, fr: "S'applique dans les messageries professionnelles", en: "Applies in work messaging apps", es: "Se aplica en apps de mensajería profesional", zh: "适用于工作沟通应用", ja: "業務向けメッセージアプリで適用", ru: "Применяется в рабочих мессенджерах")
        case .email:
            return L10n.ui(for: languageCode, fr: "S'applique dans toutes les apps mail", en: "Applies in all email apps", es: "Se aplica en todas las apps de correo", zh: "适用于所有邮件应用", ja: "すべてのメールアプリで適用", ru: "Применяется во всех почтовых приложениях")
        case .other:
            return L10n.ui(for: languageCode, fr: "S'applique dans toutes les autres apps", en: "Applies in all other apps", es: "Se aplica en todas las demás apps", zh: "适用于所有其他应用", ja: "その他すべてのアプリで適用", ru: "Применяется во всех остальных приложениях")
        }
    }
}

// MARK: - StyleView

struct StyleView: View {
    @Bindable private var state = AppState.shared
    @State private var selectedContext: StyleContext = .personal

    private var languageCode: String { state.selectedLanguage.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Style", "Style", "Estilo", "风格", "スタイル", "Стиль"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                Text(
                    t("Choisissez comment Zphyr formate votre dictée selon le contexte.",
                      "Choose how Zphyr formats your dictation by context.",
                      "Elige cómo Zphyr formatea tu dictado según el contexto.",
                      "选择 Zphyr 如何根据上下文格式化你的听写。",
                      "文脈ごとに Zphyr の整形方法を選択します。",
                      "Выберите, как Zphyr форматирует диктовку в зависимости от контекста.")
                )
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "888880"))
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Context tabs — underline style
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(StyleContext.allCases) { ctx in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedContext = ctx
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Text(ctx.label(for: languageCode))
                                    .font(.system(size: 13, weight: selectedContext == ctx ? .semibold : .regular))
                                    .foregroundColor(selectedContext == ctx ? Color(hex: "1A1A1A") : Color(hex: "999994"))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)

                                Rectangle()
                                    .fill(selectedContext == ctx ? Color(hex: "1A1A1A") : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(hex: "E8E8E6")).frame(height: 1)
            }
            .padding(.horizontal, 32)

            // Context note
            Text(selectedContext.contextNote(for: languageCode))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "AAAAAA"))
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tone rows
            VStack(spacing: 0) {
                ForEach(WritingTone.allCases) { tone in
                    ToneRow(
                        tone: tone,
                        context: selectedContext,
                        languageCode: languageCode,
                        isSelected: currentTone == tone
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            setTone(tone)
                        }
                    }

                    if tone != WritingTone.allCases.last {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 32)

            if let notice = state.advancedFeaturesNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "888880"))
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
            }

            Spacer()
        }
        .background(Color(hex: "F7F7F5"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentTone: WritingTone {
        switch selectedContext {
        case .personal: return state.stylePersonal
        case .work:     return state.styleWork
        case .email:    return state.styleEmail
        case .other:    return state.styleOther
        }
    }

    private func setTone(_ tone: WritingTone) {
        switch selectedContext {
        case .personal: state.stylePersonal = tone
        case .work:     state.styleWork     = tone
        case .email:    state.styleEmail    = tone
        case .other:    state.styleOther    = tone
        }
    }
}

// MARK: - Tone Row

private struct ToneRow: View {
    let tone: WritingTone
    let context: StyleContext
    let languageCode: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(hex: "1A1A1A") : Color(hex: "DDDDDA"), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "1A1A1A"))
                            .frame(width: 10, height: 10)
                    }
                }

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.displayName(for: languageCode))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(Color(hex: "1A1A1A"))
                    Text(tone.subtitle(for: languageCode))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }

                Spacer()

                // Preview snippet
                Text(previewSnippet)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "BBBBBB"))
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isHovered && !isSelected
                    ? Color(hex: "F7F7F5")
                    : Color.white
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var previewSnippet: String {
        switch (context, tone) {
        case (.personal, .formal):
            return L10n.ui(for: languageCode, fr: "Hey, es-tu libre demain ?", en: "Hey, are you free tomorrow?", es: "Oye, ¿estás libre mañana?", zh: "嘿，你明天有空吗？", ja: "ねえ、明日空いてる？", ru: "Привет, ты завтра свободен?")
        case (.personal, .casual):
            return L10n.ui(for: languageCode, fr: "hey, t'es libre demain ?", en: "hey, free tomorrow?", es: "oye, ¿libre mañana?", zh: "嘿，明天有空吗？", ja: "ねえ、明日空いてる？", ru: "привет, завтра свободен?")
        case (.personal, .veryCasual):
            return L10n.ui(for: languageCode, fr: "hey t'es libre demain", en: "hey free tomorrow", es: "oye libre mañana", zh: "嘿明天有空吗", ja: "ねえ明日空いてる", ru: "привет завтра свободен")

        case (.work, .formal):
            return L10n.ui(for: languageCode, fr: "Si tu es disponible, discutons.", en: "If you're available, let's discuss.", es: "Si estás disponible, conversemos.", zh: "如果你有空，我们聊一下。", ja: "ご都合が良ければ、お話ししましょう。", ru: "Если вы свободны, давайте обсудим.")
        case (.work, .casual):
            return L10n.ui(for: languageCode, fr: "Si t'es libre on peut parler.", en: "If you're free we can talk.", es: "Si estás libre, hablamos.", zh: "你有空的话我们可以聊聊。", ja: "時間があれば話そう。", ru: "Если свободен, можем поговорить.")
        case (.work, .veryCasual):
            return L10n.ui(for: languageCode, fr: "si t'es libre on peut parler", en: "if you're free we can talk", es: "si estás libre hablamos", zh: "有空就聊", ja: "時間あれば話そう", ru: "если свободен можем поговорить")

        case (.email, .formal):
            return L10n.ui(for: languageCode, fr: "Bonjour, cordialement,", en: "Hello, kind regards,", es: "Hola, saludos cordiales,", zh: "您好，致以诚挚问候，", ja: "こんにちは、よろしくお願いいたします。", ru: "Здравствуйте, с уважением,")
        case (.email, .casual):
            return L10n.ui(for: languageCode, fr: "Salut, bien à toi,", en: "Hi, thanks,", es: "Hola, gracias,", zh: "嗨，谢谢，", ja: "こんにちは、ありがとう。", ru: "Привет, спасибо,")
        case (.email, .veryCasual):
            return L10n.ui(for: languageCode, fr: "salut merci", en: "hi thanks", es: "hola gracias", zh: "嗨谢谢", ja: "やあありがとう", ru: "привет спасибо")

        case (.other, .formal):
            return L10n.ui(for: languageCode, fr: "J'apprécie cette routine.", en: "I appreciate this routine.", es: "Aprecio esta rutina.", zh: "我很认可这个流程。", ja: "このルーティンは良いですね。", ru: "Мне нравится этот процесс.")
        case (.other, .casual):
            return L10n.ui(for: languageCode, fr: "J'aime bien cette routine.", en: "I like this routine.", es: "Me gusta esta rutina.", zh: "这个流程不错。", ja: "このルーティンいいね。", ru: "Мне нравится этот процесс.")
        case (.other, .veryCasual):
            return L10n.ui(for: languageCode, fr: "j'aime bien cette routine", en: "i like this routine", es: "me gusta esta rutina", zh: "这个流程不错", ja: "このルーティンいい", ru: "мне нравится этот процесс")
        }
    }
}

#Preview {
    StyleView()
        .frame(width: 780, height: 480)
}
