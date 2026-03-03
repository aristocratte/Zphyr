//
//  OnboardingAdvancedModeView.swift
//  Zphyr
//
//  Preflight slide: optional Qwen2.5-1.5B-Instruct-4bit installation.
//  Shown after the Whisper model slide. User can skip and install later in Settings.
//

import SwiftUI

struct OnboardingAdvancedModeView: View {

    // Callbacks from PreflightView
    var onInstall: () -> Void
    var onSkip: () -> Void

    @State private var isHoveringInstall = false
    @State private var isHoveringSkip    = false

    // Color tokens (matching the Preflight light theme)
    private let zBg      = Color(hex: "#F8F8F6")
    private let zSurface = Color(hex: "#FFFFFF")
    private let zBorder  = Color(hex: "#E5E5E0")
    private let zText    = Color(hex: "#1A1A1A")
    private let zTextSub = Color(hex: "#666660")
    private let zTextDim = Color(hex: "#AAAAAA")
    private let zAccent  = Color(hex: "#22D3B8")

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + title
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
                    Text("Mode Avancé IA locale")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(zText)

                    Text("Optionnel — vous pouvez l'activer plus tard dans les Réglages")
                        .font(.system(size: 13))
                        .foregroundColor(zTextDim)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer().frame(height: 32)

            // Feature card
            VStack(alignment: .leading, spacing: 14) {
                AdvFeatureRow(icon: "wand.and.stars",
                              color: Color(hex: "#AF52DE"),
                              title: "Détection automatique",
                              subtitle: "Détecte et formate les identifiants sans mot-clé déclencheur")
                Divider().background(Color(hex: "#F0F0EE"))
                AdvFeatureRow(icon: "cpu",
                              color: Color(hex: "#007AFF"),
                              title: "100% local · Metal / ANE",
                              subtitle: "Tourne sur votre Apple Silicon — aucune donnée ne quitte votre Mac")
                Divider().background(Color(hex: "#F0F0EE"))
                AdvFeatureRow(icon: "arrow.down.circle",
                              color: Color(hex: "#34C759"),
                              title: "Téléchargement unique",
                              subtitle: "Qwen2.5-1.5B-Instruct-4bit · ~900 Mo · stocké en cache local")
            }
            .padding(20)
            .background(zSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(zBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Buttons
            VStack(spacing: 12) {
                // Install button
                Button(action: onInstall) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Installer maintenant (~900 Mo)")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(zAccent)
                            .shadow(color: zAccent.opacity(isHoveringInstall ? 0.45 : 0.25),
                                    radius: isHoveringInstall ? 12 : 8, x: 0, y: 4)
                    )
                    .scaleEffect(isHoveringInstall ? 1.01 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHoveringInstall)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringInstall = $0 }

                // Skip button
                Button(action: onSkip) {
                    Text("Non merci — mode Normal seulement")
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

// MARK: - Feature row helper

private struct AdvFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#666660"))
                    .lineSpacing(1)
            }
            Spacer()
        }
    }
}

#Preview {
    OnboardingAdvancedModeView(onInstall: {}, onSkip: {})
        .frame(width: 560, height: 520)
}
