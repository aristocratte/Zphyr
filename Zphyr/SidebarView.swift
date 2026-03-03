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

    // Outline icon (default state)
    var icon: String {
        switch self {
        case .home:               return "house"
        case .dictionary:         return "text.book.closed"
        case .audioTranscription: return "waveform"
        case .snippets:           return "doc.text"
        case .style:              return "textformat"
        case .settings:           return "gearshape"
        }
    }

    // Filled icon (selected state)
    var iconSelected: String {
        switch self {
        case .home:               return "house.fill"
        case .dictionary:         return "text.book.closed.fill"
        case .audioTranscription: return "waveform"
        case .snippets:           return "doc.text.fill"
        case .style:              return "textformat"
        case .settings:           return "gearshape.fill"
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

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: SidebarItem
    var onSettingsTapped: () -> Void = {}
    @Namespace private var pillNamespace

    private let mainItems: [SidebarItem] = [.home, .dictionary, .audioTranscription, .snippets, .style]

    var body: some View {
        VStack(spacing: 0) {

            // ── App header ────────────────────────────────────────────
            HStack(spacing: 10) {
                // Real app icon from asset catalog
                if let nsIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: nsIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                } else {
                    // Fallback: replicate the icon style
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#1A1A1A"))
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                // Name
                Text("Zphyr")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Spacer()

                // Version badge
                Text("β 0.1")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#22D3B8"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#22D3B8").opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: "#22D3B8").opacity(0.18), lineWidth: 0.5))
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // ── Main nav items ────────────────────────────────────────
            VStack(spacing: 2) {
                ForEach(mainItems) { item in
                    MagneticSidebarRow(
                        item: item,
                        isSelected: selection == item,
                        namespace: pillNamespace
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                            selection = item
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // ── Bottom items ──────────────────────────────────────────
            VStack(spacing: 2) {
                // Updates
                BottomSidebarRow(
                    icon: "arrow.down.circle",
                    label: L10n.ui(
                        for: AppState.shared.uiDisplayLanguage.rawValue,
                        fr: "Mises à jour",
                        en: "Updates",
                        es: "Actualizaciones",
                        zh: "检查更新",
                        ja: "アップデート",
                        ru: "Обновления"
                    )
                ) {
                    if let url = URL(string: "https://zphyr.app/changelog") {
                        NSWorkspace.shared.open(url)
                    }
                }

                // Settings
                BottomSidebarRow(
                    icon: SidebarItem.settings.icon,
                    label: SidebarItem.settings.label(for: AppState.shared.uiDisplayLanguage.rawValue),
                    action: onSettingsTapped
                )
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .background(Color(hex: "#F0F0EE"))
    }
}

// MARK: - Magnetic Nav Row

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
                Image(systemName: isSelected ? item.iconSelected : item.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#22D3B8") : Color(hex: "#9A9A94"))
                    .frame(width: 18)
                    .scaleEffect(isSelected ? 1.06 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSelected)

                Text(item.label(for: appState.uiDisplayLanguage.rawValue))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#111111") : Color(hex: "#6A6A65"))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.black.opacity(0.04))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Bottom Row (Updates / Settings)

private struct BottomSidebarRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(hex: "#9A9A94"))
                    .frame(width: 18)

                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(hex: "#6A6A65"))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isHovered ? Color.black.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isPressed)
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
        .frame(width: 196, height: 560)
}
