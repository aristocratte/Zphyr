//
//  OnboardingView.swift
//  Zphyr
//

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var animateWaveform = false

    // Step 2 – permission states (read live from AppState)
    var micGranted: Bool { AppState.shared.micPermission == .granted }
    var axGranted: Bool  { AppState.shared.accessibilityGranted }

    // Step 2 – language
    @State private var selectedLangCode: String = "fr"

    let totalSteps = 3

    let languages: [(code: String, name: String, flag: String)] = [
        ("fr", "Français", "🇫🇷"),
        ("en", "English",  "🇺🇸"),
        ("es", "Español",  "🇪🇸"),
        ("de", "Deutsch",  "🇩🇪"),
        ("it", "Italiano", "🇮🇹"),
        ("pt", "Português","🇵🇹"),
        ("zh", "中文",      "🇨🇳"),
        ("ja", "日本語",     "🇯🇵"),
        ("ko", "한국어",     "🇰🇷"),
        ("ru", "Русский",  "🇷🇺"),
        ("ar", "العربية",  "🇸🇦"),
        ("hi", "हिन्दी",    "🇮🇳"),
    ]

    // Whether "Next" / "Start" should be enabled
    var canProceed: Bool {
        switch currentStep {
        case 0: return true
        case 1: return micGranted   // must have mic at minimum
        case 2: return true
        default: return true
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F7F5").ignoresSafeArea()

            VStack(spacing: 0) {
                // Step dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i == currentStep ? Color(hex: "#1A1A1A") : Color(hex: "#D5D5D0"))
                            .frame(width: i == currentStep ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                    }
                }
                .padding(.top, 40)

                Spacer()

                Group {
                    switch currentStep {
                    case 0: stepWelcome
                    case 1: stepPermissions
                    case 2: stepLanguage
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentStep)

                Spacer()

                // Navigation
                HStack {
                    if currentStep > 0 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { currentStep -= 1 }
                        } label: {
                            Text(t("Retour", "Back", "Atrás", "返回", "戻る", "Назад"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "#888880"))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        if currentStep < totalSteps - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { currentStep += 1 }
                        } else {
                            // Save language choice and finish
                            if let lang = WhisperLanguage.all.first(where: { $0.id == selectedLangCode }) {
                                AppState.shared.selectedLanguages = [lang]
                            }
                            hasCompletedOnboarding = true
                            NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentStep < totalSteps - 1
                                 ? t("Suivant", "Next", "Siguiente", "下一步", "次へ", "Далее")
                                 : t("Commencer", "Start", "Comenzar", "开始", "開始", "Начать"))
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: currentStep < totalSteps - 1 ? "arrow.right" : "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canProceed ? Color(hex: "#1A1A1A") : Color(hex: "#BBBBBB"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canProceed)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            selectedLangCode = AppState.shared.selectedLanguage.id
        }
    }

    // MARK: - Step 0: Welcome

    var stepWelcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#1A1A1A").opacity(0.06))
                    .frame(width: 88, height: 88)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
            }

            VStack(spacing: 10) {
                Text(t("Bienvenue sur Zphyr", "Welcome to Zphyr", "Bienvenido a Zphyr", "欢迎使用 Zphyr", "Zphyr へようこそ", "Добро пожаловать в Zphyr"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(
                    t("Dictée vocale locale pour développeurs.\nPropulsé par un backend ASR local.",
                      "Local voice dictation for developers.\nPowered by a local ASR backend.",
                      "Dictado local por voz para desarrolladores.\nImpulsado por un backend ASR local.",
                      "面向开发者的本地语音听写。\n由本地 ASR 后端驱动。",
                      "開発者向けのローカル音声入力。\nローカル ASR バックエンド搭載。",
                      "Локальная голосовая диктовка для разработчиков.\nНа базе локального ASR-бэкенда.")
                )
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#888880"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 14) {
                FeaturePill(icon: "lock.shield", text: t("100% local", "100% local", "100% local", "100% 本地", "100% ローカル", "100% локально"))
                FeaturePill(icon: "waveform", text: "ASR")
                FeaturePill(icon: "bolt.fill", text: t("Ultra rapide", "Ultra fast", "Ultrarrápido", "超快", "超高速", "Очень быстро"))
            }
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Step 1: Permissions

    var stepPermissions: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(t("Autorisations requises", "Required permissions", "Permisos requeridos", "所需权限", "必要な権限", "Необходимые разрешения"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(t("Zphyr a besoin de deux accès pour fonctionner.",
                       "Zphyr needs two permissions to work.",
                       "Zphyr necesita dos permisos para funcionar.",
                       "Zphyr 需要两个权限才能正常工作。",
                       "Zphyr の動作には 2 つの権限が必要です。",
                       "Zphyr требуется два разрешения для работы."))
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#888880"))
            }

            VStack(spacing: 10) {
                // Microphone
                PermissionRow(
                    icon: "mic.fill",
                    iconColor: Color(hex: "#FF3B30"),
                    title: t("Microphone", "Microphone", "Micrófono", "麦克风", "マイク", "Микрофон"),
                    subtitle: t("Pour capturer votre voix localement", "Capture your voice locally", "Captura tu voz localmente", "本地采集你的语音", "音声をローカルで収録", "Локальный захват голоса"),
                    granted: micGranted
                ) {
                    Task {
                        _ = await AppState.shared.requestMicrophoneAccess()
                    }
                }

                // Accessibility
                PermissionRow(
                    icon: "accessibility",
                    iconColor: Color(hex: "#007AFF"),
                    title: t("Accessibilité", "Accessibility", "Accesibilidad", "辅助功能", "アクセシビリティ", "Спецвозможности"),
                    subtitle: t("Pour injecter le texte dans vos éditeurs", "Insert text into your editors", "Insertar texto en tus editores", "将文本插入到编辑器中", "エディタへテキストを挿入", "Вставлять текст в редакторы"),
                    granted: axGranted
                ) {
                    AppState.shared.requestAccessibilityAccess()
                }
            }
            .padding(.horizontal, 48)

            // Info note about accessibility
            if !axGranted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#4A90D9"))
                    Text(
                        t("Sans Accessibilité, la dictée fonctionne mais l'injection automatique dans l'éditeur est désactivée.",
                          "Without Accessibility, dictation works but auto-insert in editors is disabled.",
                          "Sin Accesibilidad, el dictado funciona pero la inserción automática se desactiva.",
                          "未开启辅助功能时，听写可用，但无法自动插入到编辑器。",
                          "アクセシビリティ未許可でも音声入力は可能ですが、自動挿入は無効です。",
                          "Без доступа к спецвозможностям диктовка работает, но автовставка в редакторы отключена.")
                    )
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color(hex: "#4A90D9").opacity(0.07))
                .cornerRadius(8)
                .padding(.horizontal, 48)
            }
        }
        .onAppear {
            AppState.shared.refreshMicPermission()
            AppState.shared.refreshAccessibility()
        }
    }

    // MARK: - Step 2: Language

    var stepLanguage: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#1A1A1A").opacity(0.06))
                    .frame(width: 88, height: 88)
                Image(systemName: "globe")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
            }

            VStack(spacing: 8) {
                Text(t("Langue de dictée", "Dictation language", "Idioma de dictado", "听写语言", "音声入力言語", "Язык диктовки"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(
                    t("Choisissez la langue principale.\nVous pourrez changer cela dans les Paramètres.",
                      "Choose your primary language.\nYou can change this later in Settings.",
                      "Elige tu idioma principal.\nPodrás cambiarlo después en Ajustes.",
                      "选择主要语言。\n之后可在设置中修改。",
                      "主要言語を選択してください。\n後で設定から変更できます。",
                      "Выберите основной язык.\nПозже это можно изменить в настройках.")
                )
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#888880"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Langue", "Language", "Idioma", "语言", "言語", "Язык"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text(t("Whisper v3 Turbo · 30+ langues",
                               "Local ASR · multilingual",
                               "ASR local · multilingüe",
                               "本地 ASR · 多语言",
                               "ローカル ASR · 多言語",
                               "Локальный ASR · многоязычный"))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#AAAAAA"))
                    }
                    Spacer()
                    Picker("", selection: $selectedLangCode) {
                        ForEach(languages, id: \.code) { lang in
                            Text("\(lang.flag)  \(lang.name)").tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#FF9500"))
                    Text(t("Précision maximale : FR, EN, ES, DE, IT, PT, ZH, JA, KO, RU.",
                           "Best accuracy: FR, EN, ES, DE, IT, PT, ZH, JA, KO, RU.",
                           "Mejor precisión: FR, EN, ES, DE, IT, PT, ZH, JA, KO, RU.",
                           "最佳精度：FR、EN、ES、DE、IT、PT、ZH、JA、KO、RU。",
                           "高精度対応: FR, EN, ES, DE, IT, PT, ZH, JA, KO, RU。",
                           "Лучшая точность: FR, EN, ES, DE, IT, PT, ZH, JA, KO, RU."))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888880"))
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color(hex: "#FF9500").opacity(0.07))
                .cornerRadius(8)
            }
            .padding(.horizontal, 48)
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let granted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#AAAAAA"))
            }

            Spacer()

            if granted {
                Label(t("Accordé", "Granted", "Concedido", "已授权", "許可済み", "Разрешено"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#34C759"))
                    .labelStyle(.titleAndIcon)
            } else {
                Button(t("Autoriser", "Allow", "Permitir", "允许", "許可する", "Разрешить"), action: onRequest)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#1A1A1A"))
                    .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: granted)
    }
}

// MARK: - Feature Pill

struct FeaturePill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Color(hex: "#1A1A1A"))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Waveform (kept for potential use)

struct WaveformView: View {
    let animate: Bool
    let barCount = 24
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in WaveformBar(index: i, animate: animate) }
        }
    }
}

struct WaveformBar: View {
    let index: Int
    let animate: Bool
    @State private var height: CGFloat = 4
    let baseHeights: [CGFloat] = [6,10,18,28,36,28,18,10,6,4,8,20,34,44,34,20,8,4,10,22,16,8,12,6]
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: "#1A1A1A").opacity(0.75))
            .frame(width: 4, height: animate ? height : 4)
            .onAppear { startAnimation() }
            .onChange(of: animate) { _, v in
                if v { startAnimation() }
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { height = 4 } }
            }
    }
    func startAnimation() {
        guard animate else { return }
        let target = baseHeights[index % baseHeights.count]
        withAnimation(.easeInOut(duration: 0.5).delay(Double(index) * 0.04).repeatForever(autoreverses: true)) {
            height = target
        }
    }
}

#Preview {
    OnboardingView()
}
