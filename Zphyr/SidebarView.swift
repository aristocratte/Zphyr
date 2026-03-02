//
//  SidebarView.swift
//  Zphyr
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case audioTranscription = "AudioTranscription"
    case snippets = "Snippets"
    case style = "Style"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .dictionary: return "text.book.closed.fill"
        case .audioTranscription: return "waveform"
        case .snippets: return "doc.text.fill"
        case .style: return "textformat.size"
        case .settings: return "gearshape.fill"
        }
    }

    func label(for languageCode: String) -> String {
        switch self {
        case .home:
            return L10n.ui(for: languageCode, fr: "Accueil", en: "Home", es: "Inicio", zh: "首页", ja: "ホーム", ru: "Главная")
        case .dictionary:
            return L10n.ui(for: languageCode, fr: "Dictionnaire", en: "Dictionary", es: "Diccionario", zh: "词典", ja: "辞書", ru: "Словарь")
        case .audioTranscription:
            return L10n.ui(for: languageCode, fr: "Audio", en: "Audio", es: "Audio", zh: "音频", ja: "オーディオ", ru: "Аудио")
        case .snippets:
            return L10n.ui(for: languageCode, fr: "Snippets", en: "Snippets", es: "Snippets", zh: "片段", ja: "スニペット", ru: "Сниппеты")
        case .style:
            return L10n.ui(for: languageCode, fr: "Style", en: "Style", es: "Estilo", zh: "风格", ja: "スタイル", ru: "Стиль")
        case .settings:
            return L10n.ui(for: languageCode, fr: "Paramètres", en: "Settings", es: "Ajustes", zh: "设置", ja: "設定", ru: "Настройки")
        }
    }
}

// MARK: - Sidebar View with magnetic animated pill
struct SidebarView: View {
    @Binding var selection: SidebarItem
    var onSettingsTapped: () -> Void = {}
    @Namespace private var pillNamespace

    private let mainItems: [SidebarItem] = [.home, .dictionary, .audioTranscription, .snippets, .style]

    var body: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: Color(hex: "#22D3B8").opacity(0.25), radius: 8, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "#E5E5E0"), lineWidth: 1)
                        )
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#22D3B8"))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Zphyr")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text("v0.1 Beta")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 18)

            // Main navigation items
            VStack(spacing: 1) {
                ForEach(mainItems) { item in
                    MagneticSidebarRow(
                        item: item,
                        isSelected: selection == item,
                        namespace: pillNamespace
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72, blendDuration: 0)) {
                            selection = item
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Divider
            Rectangle()
                .fill(Color(hex: "#E4E4E2"))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Bottom items
            VStack(spacing: 1) {
                // Settings button → opens modal overlay
                MagneticSidebarRow(
                    item: .settings,
                    isSelected: false,
                    namespace: pillNamespace
                ) {
                    onSettingsTapped()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .background(Color(hex: "#EFEFED"))
    }
}

// MARK: - Magnetic Row
struct MagneticSidebarRow: View {
    @Bindable private var appState = AppState.shared
    let item: SidebarItem
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "#22D3B8") : Color(hex: "#999994"))
                    .frame(width: 18)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

                Text(item.label(for: appState.uiDisplayLanguage.rawValue))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#1A1A1A") : Color(hex: "#6A6A65"))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "#1A1A1A").opacity(0.05))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    SidebarView(selection: .constant(.home))
        .frame(width: 210, height: 560)
}
