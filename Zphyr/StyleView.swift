//
//  StyleView.swift
//  Zphyr
//
//  Clean, minimal style picker — one context at a time, simple row selection.
//

import SwiftUI

// MARK: - Context

private enum StyleContext: String, CaseIterable, Identifiable {
    case personal = "personal"
    case work     = "work"
    case email    = "email"
    case other    = "other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .personal: return "message"
        case .work:     return "briefcase"
        case .email:    return "envelope"
        case .other:    return "square.grid.2x2"
        }
    }

    func label(for languageCode: String) -> String {
        switch self {
        case .personal: return L10n.ui(for: languageCode, fr: "Personnel", en: "Personal",  es: "Personal",    zh: "个人",   ja: "個人",   ru: "Личное")
        case .work:     return L10n.ui(for: languageCode, fr: "Pro",       en: "Work",      es: "Trabajo",     zh: "工作",   ja: "仕事",   ru: "Работа")
        case .email:    return L10n.ui(for: languageCode, fr: "E-mail",    en: "Email",     es: "Correo",      zh: "邮件",   ja: "メール", ru: "Почта")
        case .other:    return L10n.ui(for: languageCode, fr: "Autres",    en: "Other",     es: "Otras",       zh: "其他",   ja: "その他", ru: "Другое")
        }
    }
}

// MARK: - StyleView

struct StyleView: View {
    @Bindable private var state = AppState.shared
    @State private var selectedContext: StyleContext = .personal
    @Namespace private var contextNS

    private var languageCode: String { state.selectedLanguage.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // ── Header ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Style", "Style", "Estilo", "风格", "スタイル", "Стиль"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "111111"))
                    Text(t("Adapte la mise en forme selon le contexte de saisie.",
                           "Adjusts formatting based on where you dictate.",
                           "Adapta el formato según el contexto de uso.",
                           "根据使用场景自动调整格式。",
                           "入力場所に応じてフォーマットを調整します。",
                           "Форматирование адаптируется под контекст ввода."))
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "888880"))
                }

                // ── Context picker ───────────────────────────────────────
                HStack(spacing: 2) {
                    ForEach(StyleContext.allCases) { ctx in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedContext = ctx
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: ctx.icon)
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(ctx.label(for: languageCode))
                                    .font(.system(size: 12.5,
                                                  weight: selectedContext == ctx ? .semibold : .medium))
                            }
                            .foregroundColor(selectedContext == ctx ? Color(hex: "111111") : Color(hex: "888880"))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 13)
                            .background {
                                if selectedContext == ctx {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
                                        .matchedGeometryEffect(id: "ctx_pill", in: contextNS)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color(hex: "E8E8E6"))
                .cornerRadius(11)

                // ── Tone list ────────────────────────────────────────────
                VStack(spacing: 0) {
                    ForEach(WritingTone.allCases) { tone in
                        ToneRow(
                            tone: tone,
                            context: selectedContext,
                            languageCode: languageCode,
                            isSelected: currentTone == tone
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                setTone(tone)
                            }
                        }
                        if tone != WritingTone.allCases.last {
                            Divider()
                                .padding(.leading, 58)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)

                VStack(spacing: 0) {
                    ForEach(OutputProfile.allCases) { profile in
                        OutputProfileRow(
                            profile: profile,
                            languageCode: languageCode,
                            isSelected: currentOutputProfile == profile
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                setOutputProfile(profile)
                            }
                        }
                        if profile != OutputProfile.allCases.last {
                            Divider()
                                .padding(.leading, 58)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)

                if let notice = state.advancedFeaturesNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(Color(hex: "F5F5F3"))
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

    private var currentOutputProfile: OutputProfile {
        switch selectedContext {
        case .personal: return state.outputProfilePersonal
        case .work:     return state.outputProfileWork
        case .email:    return state.outputProfileEmail
        case .other:    return state.outputProfileOther
        }
    }

    private func setOutputProfile(_ profile: OutputProfile) {
        switch selectedContext {
        case .personal: state.outputProfilePersonal = profile
        case .work:     state.outputProfileWork = profile
        case .email:    state.outputProfileEmail = profile
        case .other:    state.outputProfileOther = profile
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

    private var accentColor: Color { Color(hex: "22D3B8") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

                // Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentColor.opacity(0.12) : Color(hex: "F0F0EE"))
                        .frame(width: 36, height: 36)
                    Image(systemName: tone.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? accentColor : Color(hex: "888880"))
                }

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.displayName(for: languageCode))
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(Color(hex: "111111"))
                    Text(tone.subtitle(for: languageCode))
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }

                Spacer()

                // Preview pill
                Text(previewSnippet)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(hex: "BBBBBA"))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(hex: "F0F0EE"))
                    .cornerRadius(6)
                    .frame(maxWidth: 200, alignment: .trailing)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(isHovered && !isSelected ? Color(hex: "F8F8F7") : Color.white)
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

private struct OutputProfileRow: View {
    let profile: OutputProfile
    let languageCode: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var accentColor: Color { Color(hex: "0A84FF") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentColor.opacity(0.12) : Color(hex: "F0F0EE"))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.quote")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? accentColor : Color(hex: "888880"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName(for: languageCode))
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(Color(hex: "111111"))
                    Text(profile.subtitle(for: languageCode))
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }

                Spacer()

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(isHovered && !isSelected ? Color(hex: "F8F8F7") : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    StyleView()
        .frame(width: 780, height: 480)
}
