//
//  OnboardingAdvancedModeView.swift
//  Zphyr
//
//  Preflight slide for choosing and optionally installing one local formatting model.
//

import SwiftUI

struct OnboardingAdvancedModeView: View {

    @Binding var selectedModel: FormattingModelID
    var status: FormattingModelInstallStatus
    var primaryTitle: String
    var primaryEnabled: Bool
    var onPrimaryAction: () -> Void
    var onSkip: () -> Void

    @State private var isHoveringPrimary = false
    @State private var isHoveringSkip = false

    private let zBg      = Color(hex: "#F8F8F6")
    private let zSurface = Color(hex: "#FFFFFF")
    private let zBorder  = Color(hex: "#E5E5E0")
    private let zText    = Color(hex: "#1A1A1A")
    private let zTextSub = Color(hex: "#666660")
    private let zTextDim = Color(hex: "#AAAAAA")
    private let zAccent  = Color(hex: "#22D3B8")

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    private var selectedSizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: FormattingModelCatalog.descriptor(for: selectedModel).approximateBytes,
            countStyle: .file
        )
    }

    private var statusText: String {
        switch status {
        case .installed:
            return L10n.ui(for: lang, fr: "Installé", en: "Installed", es: "Instalado", zh: "已安装", ja: "インストール済み", ru: "Установлен")
        case .notInstalled:
            return L10n.ui(for: lang, fr: "Non installé", en: "Not installed", es: "No instalado", zh: "未安装", ja: "未インストール", ru: "Не установлен")
        case .downloading(let progress):
            return L10n.ui(for: lang, fr: "Téléchargement \(Int(progress * 100))%", en: "Downloading \(Int(progress * 100))%", es: "Descargando \(Int(progress * 100))%", zh: "下载中 \(Int(progress * 100))%", ja: "ダウンロード中 \(Int(progress * 100))%", ru: "Загрузка \(Int(progress * 100))%")
        case .preparing:
            return L10n.ui(for: lang, fr: "Préparation…", en: "Preparing…", es: "Preparando…", zh: "准备中…", ja: "準備中…", ru: "Подготовка…")
        case .unavailable(let reason), .error(let reason):
            return reason
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(zAccent.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(zAccent)
                }

                VStack(spacing: 8) {
                    Text("Choisissez un modèle de formatage local")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(zText)

                    Text("Vous pouvez en installer un maintenant, puis en changer plus tard dans les Réglages.")
                        .font(.system(size: 13))
                        .foregroundColor(zTextDim)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(FormattingModelID.allCases) { modelID in
                    FormatterChoiceCard(
                        modelID: modelID,
                        isSelected: modelID == selectedModel,
                        statusText: modelID == selectedModel ? statusText : nil
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            selectedModel = modelID
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(selectedSizeLabel, systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(zTextSub)
                    Text("•")
                        .foregroundColor(zTextDim)
                    Text(selectedModel.recommendedUsage(for: lang))
                        .font(.system(size: 11))
                        .foregroundColor(zTextSub)
                        .lineLimit(2)
                }

                Button(action: onPrimaryAction) {
                    HStack(spacing: 10) {
                        Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(primaryTitle)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(primaryEnabled ? zAccent : Color(hex: "#C8C8C3"))
                            .shadow(color: zAccent.opacity(primaryEnabled && isHoveringPrimary ? 0.45 : 0.18),
                                    radius: primaryEnabled && isHoveringPrimary ? 12 : 8, x: 0, y: 4)
                    )
                    .scaleEffect(primaryEnabled && isHoveringPrimary ? 1.01 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHoveringPrimary)
                }
                .buttonStyle(.plain)
                .disabled(!primaryEnabled)
                .onHover { isHoveringPrimary = $0 }

                Button(action: onSkip) {
                    Text("Installer plus tard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isHoveringSkip ? zText : zTextSub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isHoveringSkip ? Color(hex: "#1A1A1A").opacity(0.05) : .clear)
                        )
                        .animation(.easeOut(duration: 0.15), value: isHoveringSkip)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringSkip = $0 }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(zBg)
    }
}

private struct FormatterChoiceCard: View {
    let modelID: FormattingModelID
    let isSelected: Bool
    let statusText: String?

    private var lang: String { AppState.shared.uiDisplayLanguage.rawValue }

    private var sizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: FormattingModelCatalog.descriptor(for: modelID).approximateBytes,
            countStyle: .file
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isSelected ? Color(hex: "#22D3B8").opacity(0.12) : Color(hex: "#F8F8F6"))
                        .frame(width: 40, height: 40)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "#22D3B8") : Color(hex: "#AAAAAA"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(modelID.displayName(for: lang))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text(sizeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#666660"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#F0F0EE"))
                            .cornerRadius(6)
                        if let statusText, !statusText.isEmpty {
                            Text(statusText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#007AFF"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#007AFF").opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    Text(modelID.shortDescription(for: lang))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#666660"))
                    Text(modelID.recommendedUsage(for: lang))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                        .lineSpacing(1)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: "#22D3B8") : Color(hex: "#E5E5E0"), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 10 : 6, x: 0, y: 4)
    }
}

#Preview {
    OnboardingAdvancedModeView(
        selectedModel: .constant(.qwen3_4b),
        status: .notInstalled,
        primaryTitle: "Installer Qwen3.5-4B",
        primaryEnabled: true,
        onPrimaryAction: {},
        onSkip: {}
    )
    .frame(width: 640, height: 640)
}
