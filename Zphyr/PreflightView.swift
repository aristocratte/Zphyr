//
//  PreflightView.swift
//  Zphyr
//
//  Redesigned preflight: 9-step immersive slideshow
//  Dark premium macOS aesthetic · Inspired by Wispr Flow
//

import SwiftUI
import AppKit

// MARK: - Design Tokens

private extension Color {
    static let zBg       = Color(hex: "F8F8F6")
    static let zSurface  = Color(hex: "FFFFFF")
    static let zSurface2 = Color(hex: "F0F0EE")
    static let zBorder   = Color(hex: "E5E5E0")
    static let zAccent   = Color(hex: "22D3B8")
    static let zBlue     = Color(hex: "4F7EF7")
    static let zPurple   = Color(hex: "AF52DE")
    static let zOrange   = Color(hex: "FF9500")
    static let zRed      = Color(hex: "FF3B30")
    static let zGreen    = Color(hex: "34C759")
    static let zText     = Color(hex: "1A1A1A")
    static let zTextSub  = Color(hex: "666660")
    static let zTextDim  = Color(hex: "AAAAAA")
}

// MARK: - Slide Definition

private enum PreflightSlide: Int, CaseIterable {
    case welcome      = 0
    case speed        = 1
    case features     = 2
    case demos        = 3
    case language     = 4
    case model        = 5
    case advancedMode = 6   // NEW
    case permissions  = 7
    case shortcut     = 8
    case ready        = 9

    func stepLabel(for lang: String) -> String {
        switch self {
        case .welcome:
            return L10n.ui(for: lang, fr: "Bienvenue", en: "Welcome", es: "Bienvenida", zh: "欢迎", ja: "ようこそ", ru: "Привет")
        case .speed:
            return L10n.ui(for: lang, fr: "Vitesse", en: "Speed", es: "Velocidad", zh: "速度", ja: "速度", ru: "Скорость")
        case .features:
            return L10n.ui(for: lang, fr: "Fonctions", en: "Features", es: "Funciones", zh: "功能", ja: "機能", ru: "Функции")
        case .demos:
            return L10n.ui(for: lang, fr: "Démos", en: "Demos", es: "Demos", zh: "演示", ja: "デモ", ru: "Демо")
        case .language:
            return L10n.ui(for: lang, fr: "Langue", en: "Language", es: "Idioma", zh: "语言", ja: "言語", ru: "Язык")
        case .model:
            return L10n.ui(for: lang, fr: "Modèle", en: "Model", es: "Modelo", zh: "模型", ja: "モデル", ru: "Модель")
        case .advancedMode:
            return L10n.ui(for: lang, fr: "Mode IA", en: "AI Mode", es: "Modo IA", zh: "AI 模式", ja: "AI モード", ru: "ИИ режим")
        case .permissions:
            return L10n.ui(for: lang, fr: "Accès", en: "Access", es: "Acceso", zh: "权限", ja: "権限", ru: "Доступ")
        case .shortcut:
            return L10n.ui(for: lang, fr: "Raccourci", en: "Shortcut", es: "Atajo", zh: "快捷键", ja: "ショートカット", ru: "Клавиша")
        case .ready:
            return L10n.ui(for: lang, fr: "Prêt !", en: "Ready!", es: "¡Listo!", zh: "就绪！", ja: "完了！", ru: "Готово!")
        }
    }
}

// MARK: - PreflightView

struct PreflightView: View {
    var onReady: () -> Void

    @State private var currentSlide: PreflightSlide = .welcome
    @State private var goingForward: Bool = true
    @State private var didStartModel: Bool = false
    @State private var glowPulse: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.14
    @State private var waveOffset: CGFloat = 0
    @State private var readyScale: CGFloat = 0.6
    @State private var readyOpacity: Double = 0

    // Welcome slide staggered reveal (0 = hidden, 1..5 = each element visible)
    @State private var welcomeReveal: Int = 0

    // Speed slide states
    @State private var keyboardText: String = ""
    @State private var keyboardDone: Bool = false
    @State private var keyboardErrorStart: Int? = nil
    @State private var voiceChunks: [VoiceChunk] = []
    @State private var voiceDone: Bool = false
    @State private var speedCursorBlink: Bool = true
    @State private var speedReveal: Int = 0

    // Welcome app rotator
    @State private var appRotatorIndex: Int = 0
    @State private var appRotatorPrevIndex: Int = 0
    @State private var appRotatorFlip: Double = 0

    // Features bento slide states
    @State private var featReveal: Int = 0

    // Profile (demos) slide states
    @State private var selectedProfileIdx: Int? = nil
    @State private var profileSnippetValue: String = ""
    @State private var profileReveal: Int = 0
    @State private var profileConfigReveal: Bool = false
    // Custom profile editable state
    @State private var customStyleWork: WritingTone = .formal
    @State private var customStylePersonal: WritingTone = .casual
    @State private var customStyleEmail: WritingTone = .formal
    @State private var customSnippetTrigger: String = ""
    @State private var customSnippetExpansion: String = ""

    // Language slide staggered reveal
    @State private var langReveal: Int = 0
    // Model slide staggered reveal
    @State private var modelReveal: Int = 0
    // Shortcut slide reveal + key press animation
    @State private var shortcutReveal: Int = 0
    @State private var shortcutKeyPressed: Bool = false

    @State private var permissionPollTask: Task<Void, Never>? = nil
    @State private var featTask: Task<Void, Never>? = nil
    @State private var advancedModeInstallTask: Task<Void, Never>? = nil
    @State private var showModelTest = false

    private var modelStatus: ModelStatus    { AppState.shared.modelStatus }
    private var downloadStats: DownloadStats { AppState.shared.downloadStats }
    private var lang: String                 { AppState.shared.uiDisplayLanguage.rawValue }
    private var asrDescriptor: ASRBackendDescriptor { DictationEngine.shared.currentASRDescriptor }
    private var asrRequiresInstall: Bool { asrDescriptor.requiresModelInstall }
    private var isProModeUnlocked: Bool { AppState.shared.isProModeUnlocked }
    private var performanceProfile: PerformanceProfile { AppState.shared.performanceProfile }
    private var isPreparingModelDownload: Bool {
        guard asrRequiresInstall else { return false }
        guard case .downloading = modelStatus else { return false }
        guard !AppState.shared.isDownloadPaused else { return false }
        return downloadStats.bytesReceived < 256_000 && downloadStats.speedBytesPerSec < 20_000
    }

    private func percentLabel(_ progress: Double) -> String {
        let pct = max(0, progress * 100)
        if pct > 0 && pct < 10 {
            return String(format: "%.1f%%", pct)
        }
        return "\(Int(pct))%"
    }

    var body: some View {
        ZStack {
            // Background — animated aurora on welcome, static elsewhere
            Color.zBg.ignoresSafeArea()
            if currentSlide == .welcome {
                WelcomeAnimatedBackground()
                    .transition(.opacity)
            } else {
                ambientBackground
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // Step indicator bar
                stepIndicator
                    .padding(.top, 26)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 18)

                // Slide content
                slideContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentSlide)
                    .animation(.spring(response: 0.46, dampingFraction: 0.84), value: currentSlide)

                // Navigation footer
                navigationBar
                    .padding(.horizontal, 44)
                    .padding(.bottom, 26)
            }
        }
        .onAppear {
            AppState.shared.refreshPerformanceProfile()
            DictationEngine.shared.refreshASRBackendSelection()
            startBackgroundAnimations()
            startModelInBackground()
            startWelcomeReveal()
        }
        .onChange(of: modelStatus) { _, newStatus in
            if newStatus.isReady && currentSlide == .model {
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    advance()
                }
            }
        }
        .onChange(of: AppState.shared.advancedModeInstalled) { _, installed in
            if installed && currentSlide == .advancedMode {
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    advance()
                }
            }
        }
        .colorScheme(.light)
        .onChange(of: currentSlide) { _, newSlide in
            permissionPollTask?.cancel()
            featTask?.cancel()

            if newSlide == .permissions {
                permissionPollTask = Task {
                    while !Task.isCancelled, currentSlide == .permissions {
                        AppState.shared.refreshMicPermission()
                        AppState.shared.refreshAccessibility()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
            if newSlide == .model && !modelStatus.isReady {
                modelReveal = 0
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { modelReveal = 1 }
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { modelReveal = 2 }
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { modelReveal = 3 }
                }
                Task { await startLoadModelIfNeeded() }
            }
            if newSlide == .model && modelStatus.isReady {
                modelReveal = 3
            }
            if newSlide == .advancedMode {
                // No special init needed — OnboardingAdvancedModeView handles its own state
            }
            if newSlide == .ready {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    readyScale = 1.0
                    readyOpacity = 1.0
                }
            }
            if newSlide == .speed {
                startSpeedAnimations()
            }
            if newSlide == .features {
                featReveal = 0
                featTask = Task { await startFeaturesReveal() }
            }
            if newSlide == .welcome {
                welcomeReveal = 0
                appRotatorIndex = 0
                appRotatorPrevIndex = 0
                appRotatorFlip = 0
                startWelcomeReveal()
            }
            if newSlide == .demos {
                profileReveal = 0
                profileConfigReveal = false
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { profileReveal = 1 }
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { profileReveal = 2 }
                }
            }
            if newSlide == .language {
                langReveal = 0
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { langReveal = 1 }
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { langReveal = 2 }
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { langReveal = 3 }
                }
            }
            if newSlide == .shortcut {
                shortcutReveal = 0
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { shortcutReveal = 1 }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { shortcutReveal = 2 }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { shortcutReveal = 3 }
                    // Key press demo animation
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { shortcutKeyPressed = true }
                    try? await Task.sleep(for: .milliseconds(260))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shortcutKeyPressed = false }
                }
            }
        }
        .onDisappear {
            permissionPollTask?.cancel()
            featTask?.cancel()
            advancedModeInstallTask?.cancel()
            advancedModeInstallTask = nil
        }
        .sheet(isPresented: $showModelTest) {
            ModelTestView()
                .frame(width: 760, height: 520)
                .background(Color.zBg)
        }
    }

    // MARK: - Ambient Background

    private var ambientBackground: some View {
        ZStack {
            // Teal glow — top-left
            RadialGradient(
                colors: [Color.zAccent.opacity(0.09), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            // Blue glow — bottom-right
            RadialGradient(
                colors: [Color.zBlue.opacity(0.055), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 440
            )
            .ignoresSafeArea()

            // Warm accent — bottom-left, very faint
            RadialGradient(
                colors: [Color.zOrange.opacity(0.025), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 5) {
            ForEach(PreflightSlide.allCases, id: \.rawValue) { slide in
                let isCompleted = slide.rawValue < currentSlide.rawValue
                let isCurrent   = slide == currentSlide
                Capsule()
                    .fill(
                        isCompleted ? Color.zAccent :
                        (isCurrent  ? Color(hex: "1A1A1A").opacity(0.75) : Color(hex: "1A1A1A").opacity(0.13))
                    )
                    .frame(width: isCurrent ? 26 : 7, height: 4)
                    .animation(.spring(response: 0.38, dampingFraction: 0.75), value: currentSlide)
            }

            Spacer()

            Text(currentSlide.stepLabel(for: lang))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.zTextDim)
                .animation(.easeInOut(duration: 0.18), value: currentSlide)
        }
    }

    // MARK: - Slide Content

    @ViewBuilder
    private var slideContent: some View {
        let insertion: Edge  = goingForward ? .trailing : .leading
        let removal: Edge    = goingForward ? .leading  : .trailing

        switch currentSlide {
        case .welcome:
            welcomeSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .speed:
            speedSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .features:
            featuresSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .demos:
            demosSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .language:
            languageSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .model:
            modelSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .advancedMode:
            advancedModeSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .permissions:
            permissionsSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .shortcut:
            shortcutSlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        case .ready:
            readySlide
                .transition(.asymmetric(
                    insertion: .move(edge: insertion).combined(with: .opacity),
                    removal: .move(edge: removal).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button — hidden during active download, loading, and on ready slide
            let canGoBack: Bool = {
                if currentSlide.rawValue == 0 { return false }
                if currentSlide == .ready { return false }
                if currentSlide == .model {
                    // Allow back only if not actively downloading/loading
                    if case .downloading = modelStatus { return false }
                    if case .loading = modelStatus { return false }
                    return true
                }
                if currentSlide == .advancedMode {
                    return !AdvancedLLMFormatter.shared.isInstalling
                }
                return true
            }()
            if canGoBack {
                Button { goBack() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(t("Retour", "Back", "Volver", "返回", "戻る", "Назад"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color.zTextSub)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(hex: "1A1A1A").opacity(0.05))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.zBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else if currentSlide == .welcome {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.zTextDim)
                    Text(t("100% local — aucune donnée envoyée",
                           "100% local — no data sent",
                           "100% local — sin datos enviados",
                           "100% 本地 — 不传输数据",
                           "100% ローカル — データ送信なし",
                           "100% локально — данные не передаются"))
                        .font(.system(size: 11))
                        .foregroundColor(Color.zTextDim)
                }
            } else {
                Spacer().frame(width: 1)
            }

            Spacer()

            nextButtonView
        }
    }

    @ViewBuilder
    private var nextButtonView: some View {
        switch currentSlide {
        case .welcome:
            PFPrimaryButton(
                label: t("Commencer", "Get Started", "Comenzar", "开始", "始める", "Начать"),
                icon: "arrow.right"
            ) { advance() }
            .opacity(welcomeReveal >= 5 ? 1 : 0)
            .offset(y: welcomeReveal >= 5 ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: welcomeReveal)

        case .speed:
            PFPrimaryButton(
                label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                icon: "arrow.right"
            ) { advance() }

        case .features:
            PFPrimaryButton(
                label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                icon: "arrow.right"
            ) { advance() }

        case .demos:
            PFPrimaryButton(
                label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                icon: "arrow.right"
            ) { advance() }

        case .language:
            PFPrimaryButton(
                label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                icon: "arrow.right"
            ) { advance() }

        case .model:
            if modelStatus.isReady {
                PFPrimaryButton(
                    label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                    icon: "arrow.right"
                ) { advance() }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.zTextSub)
                    Text(
                        t("Installation…", "Installing…", "Instalando…", "安装中…", "インストール中…", "Установка…")
                    )
                    .font(.system(size: 13))
                    .foregroundColor(Color.zTextSub)
                }
            }

        case .advancedMode:
            if !isProModeUnlocked {
                PFPrimaryButton(
                    label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                    icon: "arrow.right"
                ) { advance() }
            } else if AdvancedLLMFormatter.shared.isInstalling {
                EmptyView()
            } else if AppState.shared.advancedModeInstalled {
                PFPrimaryButton(
                    label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                    icon: "arrow.right"
                ) { advance() }
            }
            // else: OnboardingAdvancedModeView has its own Skip button

        case .permissions:
            PFPrimaryButton(
                label: t("Continuer", "Continue", "Continuar", "继续", "続ける", "Продолжить"),
                icon: "arrow.right"
            ) { advance() }

        case .shortcut:
            PFPrimaryButton(
                label: t("Presque fini", "Almost there", "Casi listo", "快完成了", "もう少し", "Почти готово"),
                icon: "arrow.right"
            ) { advance() }

        case .ready:
            PFPrimaryButton(
                label: t("Ouvrir Zphyr", "Open Zphyr", "Abrir Zphyr", "打开 Zphyr", "Zphyr を開く", "Открыть Zphyr"),
                icon: "waveform.and.mic",
                isAccent: true
            ) {
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    NotificationCenter.default.post(name: .preflightCompleted, object: nil)
                    onReady()
                }
            }
        }
    }

    // MARK: - Navigation helpers

    private func advance() {
        guard currentSlide.rawValue < PreflightSlide.allCases.count - 1 else { return }
        goingForward = true
        withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
            currentSlide = PreflightSlide(rawValue: currentSlide.rawValue + 1) ?? currentSlide
        }
    }

    private func goBack() {
        guard currentSlide.rawValue > 0 else { return }
        goingForward = false
        withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
            currentSlide = PreflightSlide(rawValue: currentSlide.rawValue - 1) ?? currentSlide
        }
    }

    // MARK: - Advanced Mode Slide

    @ViewBuilder
    private var advancedModeSlide: some View {
        let formatter = AdvancedLLMFormatter.shared
        if !isProModeUnlocked {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.zSurface2)
                        .frame(width: 84, height: 84)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Color.zTextDim)
                }

                Text(t("Mode Pro indisponible sur cette machine", "Pro mode is unavailable on this machine", "El modo Pro no está disponible en esta máquina", "此设备不支持专业模式", "このマシンでは Pro モードを利用できません", "Режим Pro недоступен на этом устройстве"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color.zText)
                    .multilineTextAlignment(.center)

                Text(
                    t(
                        "Profil détecté : \(performanceProfile.displayLabel(for: lang)). Zphyr reste en mode Éco (Regex) pour garantir fluidité et stabilité.",
                        "Detected profile: \(performanceProfile.displayLabel(for: lang)). Zphyr stays in Eco mode (regex) for smooth and stable performance.",
                        "Perfil detectado: \(performanceProfile.displayLabel(for: lang)). Zphyr permanece en modo Eco (regex) para mayor fluidez y estabilidad.",
                        "检测到的配置：\(performanceProfile.displayLabel(for: lang))。Zphyr 将保持在节能模式（正则）以确保流畅稳定。",
                        "検出されたプロファイル: \(performanceProfile.displayLabel(for: lang))。安定性のため Zphyr はエコモード（Regex）のまま動作します。",
                        "Обнаруженный профиль: \(performanceProfile.displayLabel(for: lang)). Zphyr остаётся в эко-режиме (regex) для стабильной работы."
                    )
                )
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
                .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.zBg)
        } else if formatter.isInstalling {
            // Installing — show progress ring
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(Color.zBorder, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: formatter.downloadProgress)
                        .stroke(Color.zAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: formatter.downloadProgress)
                    Text("\(Int(formatter.downloadProgress * 100))%")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color.zText)
                }

                VStack(spacing: 8) {
                    Text(t("Installation du modèle IA…", "Installing AI model…", "Instalando modelo IA…", "安装 AI 模型…", "AI モデルをインストール中…", "Установка модели ИИ…"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.zText)

                    Text("Qwen3-1.7B-4bit · ~1.1 GB")
                        .font(.system(size: 13))
                        .foregroundColor(Color.zTextDim)

                    // Download progress details
                    if !formatter.downloadedMB.isEmpty || !formatter.downloadSpeed.isEmpty {
                        HStack(spacing: 6) {
                            if !formatter.downloadedMB.isEmpty {
                                Text(formatter.downloadedMB)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color.zTextSub)
                            }
                            if !formatter.downloadSpeed.isEmpty {
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.zTextDim)
                                Text(formatter.downloadSpeed)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color.zAccent)
                            }
                        }
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.3), value: formatter.downloadedMB)
                    }
                }

                // Cancel button
                Button(t("Annuler le téléchargement", "Cancel download", "Cancelar descarga", "取消下载", "ダウンロードをキャンセル", "Отменить загрузку")) {
                    AdvancedLLMFormatter.shared.cancelInstall()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.zTextSub)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.zSurface2)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.zBorder, lineWidth: 1))
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.zBg)
        } else if AppState.shared.advancedModeInstalled {
            // Success state — briefly shown before auto-advance
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.zAccent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color.zAccent)
                }
                Text(t("Mode IA installé !", "AI mode installed!", "¡Modo IA instalado!", "AI 模式已安装！", "AI モードがインストールされました！", "Режим ИИ установлен!"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.zText)
                Text("Qwen3-1.7B-4bit · prêt")
                    .font(.system(size: 13))
                    .foregroundColor(Color.zTextDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.zBg)
        } else {
            // Default — show OnboardingAdvancedModeView with callbacks
            OnboardingAdvancedModeView(
                onInstall: {
                    advancedModeInstallTask = Task {
                        await AdvancedLLMFormatter.shared.installModel()
                    }
                },
                onSkip: {
                    advance()
                }
            )
        }
    }

    // MARK: - Model helpers

    private func startModelInBackground() {
        guard !didStartModel else { return }
        didStartModel = true
        Task { await startLoadModelIfNeeded() }
    }

    private func startLoadModelIfNeeded() async {
        guard !modelStatus.isReady else { return }
        await DictationEngine.shared.loadModel()
    }

    // MARK: - Animations

    private func startBackgroundAnimations() {
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            glowPulse = 1.32
        }
        withAnimation(.easeInOut(duration: 2.8).delay(0.6).repeatForever(autoreverses: true)) {
            glowOpacity = 0.26
        }
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            waveOffset = 1.0
        }
    }

    private let pfCompatApps = [
        "Mail", "Slack", "Notion", "Notes", "Messages",
        "VS Code", "Cursor", "Xcode", "Terminal",
        "Claude Code", "GitHub Copilot", "Zed", "Figma", "Linear"
    ]

    private func buildKeyboardDisplayText() -> Text {
        let cursor: Text = (!keyboardDone && speedCursorBlink)
            ? Text("│").foregroundColor(Color.zText)
            : Text("")
        if let errIdx = keyboardErrorStart, errIdx <= keyboardText.count {
            let correct = String(keyboardText.prefix(errIdx))
            let wrong   = String(keyboardText.dropFirst(errIdx))
            return Text(correct).foregroundColor(Color.zText)
                 + Text(wrong).foregroundColor(Color(red: 0.88, green: 0.15, blue: 0.15))
                 + cursor
        }
        return Text(keyboardText).foregroundColor(Color.zText) + cursor
    }

    private func startWelcomeReveal() {
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { welcomeReveal = 1 }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { welcomeReveal = 2 }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { welcomeReveal = 3 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { welcomeReveal = 4 }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { welcomeReveal = 5 }

            // App compatibility rotator appears after ~1s
            try? await Task.sleep(for: .milliseconds(1000))
            guard currentSlide == .welcome else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { welcomeReveal = 6 }

            // Cycling loop — true two-face 3D flip every 2s
            while currentSlide == .welcome {
                try? await Task.sleep(for: .milliseconds(2000))
                guard currentSlide == .welcome else { return }
                let nextIdx = (appRotatorIndex + 1) % pfCompatApps.count
                appRotatorPrevIndex = appRotatorIndex
                appRotatorIndex = nextIdx
                withAnimation(.easeInOut(duration: 0.38)) { appRotatorFlip = 88 }
                try? await Task.sleep(for: .milliseconds(420))
                guard currentSlide == .welcome else { return }
                // Snap back: both faces hidden at 88° so no flash
                appRotatorFlip = 0
                appRotatorPrevIndex = appRotatorIndex
            }
        }
    }

    private func startFeaturesReveal() async {
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { featReveal = 1 }
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { featReveal = 2 }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { featReveal = 3 }
    }

    private func startSpeedAnimations() {
        keyboardText = ""
        keyboardDone = false
        keyboardErrorStart = nil
        voiceChunks = []
        voiceDone = false
        speedCursorBlink = true
        speedReveal = 0

        // Staggered slide-in reveal
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) { speedReveal = 1 }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) { speedReveal = 2 }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) { speedReveal = 3 }
        }

        // Cursor blink loop
        Task { @MainActor in
            while currentSlide == .speed {
                try? await Task.sleep(for: .milliseconds(520))
                guard currentSlide == .speed else { return }
                speedCursorBlink.toggle()
            }
        }

        // Keyboard typing — starts after 1s, finishes ~12s later
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard currentSlide == .speed else { return }

            let script: [SpeedTypeOp] = {
                var ops: [SpeedTypeOp] = []

                // Phase 1 — correct prefix + typo "baucoup"
                let p1pre  = t("Vous voyez que c'est ", "You can see that it is ", "Pueden ver que es ", "你会发现", "話す方がタイプするより", "Вы видите что ")
                let p1typo = t("baucoup", "mush", "mmas", "简单很", "まます", "многоо")
                let p1fix  = t("beaucoup ", "much ", "más ", "简单得多", "す", "намного ")
                for ch in p1pre  { ops.append(.char(ch)) }
                ops.append(.markError)
                for ch in p1typo { ops.append(.char(ch)) }
                ops.append(.pause(360))
                for _ in 0..<p1typo.count { ops.append(.backspace) }
                ops.append(.clearError)
                for ch in p1fix  { ops.append(.char(ch)) }

                // Phase 2 — correct prefix + typo "simppe"
                let p2pre  = t("plus ", "simpler to ", "más ", "更", "ずっと", "говорить чем ")
                let p2typo = t("simppe", "speeak", "simppe", "simppe", "simppe", "печатаать")
                let p2fix  = t("simple de parler ", "speak ", "hablar ", "简单得多 ", "です ", " ")
                for ch in p2pre  { ops.append(.char(ch)) }
                ops.append(.markError)
                for ch in p2typo { ops.append(.char(ch)) }
                ops.append(.pause(310))
                for _ in 0..<p2typo.count { ops.append(.backspace) }
                ops.append(.clearError)
                for ch in p2fix  { ops.append(.char(ch)) }

                // Phase 3 — correct prefix + typo "tapr"
                let p3pre  = t("plutôt que de ", "rather than typing on ", "en lugar de ", "而不是在键盘上", "キーボードで", "чем набирать текст на ")
                let p3typo = t("tapr", "teh keyborad", "escirbir", "tapr", "tapr", "клавуатуре")
                let p3fix  = t("taper sur un clavier, surtout quand on a beaucoup de choses à dire.",
                               " keyboard, especially when you have a lot to say.",
                               " el teclado, sobre todo cuando tienes mucho que decir.",
                               "键盘上打字，尤其是当你有很多话要说的时候。",
                               "することで、特にたくさんのことを言いたいときに便利です。",
                               " клавиатуре, особенно когда вам есть что сказать.")
                for ch in p3pre  { ops.append(.char(ch)) }
                ops.append(.markError)
                for ch in p3typo { ops.append(.char(ch)) }
                ops.append(.pause(280))
                for _ in 0..<p3typo.count { ops.append(.backspace) }
                ops.append(.clearError)
                for ch in p3fix  { ops.append(.char(ch)) }

                return ops
            }()

            for op in script {
                guard currentSlide == .speed else { return }
                switch op {
                case .char(let ch):
                    keyboardText.append(ch)
                    let ms = Int.random(in: 48...115)
                    try? await Task.sleep(for: .milliseconds(ms))
                case .backspace:
                    if !keyboardText.isEmpty { keyboardText.removeLast() }
                    try? await Task.sleep(for: .milliseconds(75))
                case .pause(let ms):
                    try? await Task.sleep(for: .milliseconds(ms))
                case .markError:
                    keyboardErrorStart = keyboardText.count
                case .clearError:
                    keyboardErrorStart = nil
                }
            }
            guard currentSlide == .speed else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { keyboardDone = true }
        }

        // Voice dictation — starts after 1s, finishes ~3.5s later
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard currentSlide == .speed else { return }

            let voiceSequence: [(String, Int)] = [
                (t("Vous voyez que",
                   "You can see that",
                   "Pueden ver que",
                   "你会发现",
                   "話す方が",
                   "Вы видите, что"), 0),
                (t("c'est beaucoup",
                   "it is much",
                   "es mucho más",
                   "说话比打字",
                   "タイプするより",
                   "говорить намного"), 420),
                (t("plus simple de parler",
                   "simpler to speak",
                   "más simple hablar",
                   "要简单得多，",
                   "ずっと簡単で、",
                   "проще, чем набирать,"), 370),
                (t("plutôt que de taper",
                   "rather than to type",
                   "en lugar de escribir",
                   "而不是在键盘上",
                   "特にたくさんのことを",
                   "особенно когда"), 340),
                (t("sur un clavier,",
                   "on a keyboard,",
                   "en un teclado,",
                   "打字，尤其是",
                   "言いたいときに",
                   "вам есть"), 320),
                (t("surtout quand on a beaucoup de choses à dire.",
                   "especially when you have a lot to say.",
                   "sobre todo cuando tienes mucho que decir.",
                   "当你有很多话要说的时候。",
                   "便利です。",
                   "что сказать."), 300),
            ]

            for (text, waitMs) in voiceSequence {
                if waitMs > 0 { try? await Task.sleep(for: .milliseconds(waitMs)) }
                guard currentSlide == .speed else { return }
                withAnimation { voiceChunks.append(VoiceChunk(words: text)) }
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard currentSlide == .speed else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { voiceDone = true }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 0: Welcome
    // ═══════════════════════════════════════════════════════════

    private var welcomeSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated waveform equalizer
            WelcomeWaveformHero()
                .opacity(welcomeReveal >= 1 ? 1 : 0)
                .scaleEffect(welcomeReveal >= 1 ? 1.0 : 0.78)
                .blur(radius: welcomeReveal >= 1 ? 0 : 4)
                .animation(.spring(response: 0.75, dampingFraction: 0.70), value: welcomeReveal)
                .padding(.bottom, 36)

            // App name + accent underline
            VStack(spacing: 8) {
                Text("Zphyr")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "111111"), Color.zAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.zAccent.opacity(0.15), radius: 20, x: 0, y: 4)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.zAccent.opacity(0.6), Color.zBlue.opacity(0.4), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: 180, maxHeight: 1.5)
                    .cornerRadius(1)
            }
            .opacity(welcomeReveal >= 2 ? 1 : 0)
            .offset(y: welcomeReveal >= 2 ? 0 : 18)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: welcomeReveal)
            .padding(.bottom, 16)

            // Tagline
            Text(t(
                "Ta voix. Ton Mac. Zéro cloud.",
                "Your voice. Your Mac. No cloud.",
                "Tu voz. Tu Mac. Sin nube.",
                "你的声音。你的 Mac。零云端。",
                "あなたの声。あなたの Mac。クラウドなし。",
                "Твой голос. Твой Mac. Без облака."
            ))
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Color.zTextSub)
            .opacity(welcomeReveal >= 3 ? 1 : 0)
            .offset(y: welcomeReveal >= 3 ? 0 : 14)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: welcomeReveal)
            .padding(.bottom, 14)

            // App compatibility rotator — true 3D rectangular prism flip
            ZStack {
                if welcomeReveal >= 6 {
                    HStack(spacing: 8) {
                        Text(t("Compatible avec :", "Works with:", "Compatible con:", "兼容：", "対応：", "Работает с:"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.zTextSub)
                        // 3D prism: outgoing tilts back from bottom, incoming swings in from top
                        ZStack {
                            // Ghost for sizing (always matches incoming text width)
                            Text(pfCompatApps[appRotatorIndex])
                                .opacity(0)
                            // Outgoing face — anchored at bottom, rotates 0° → 90° (tilts backward)
                            Text(pfCompatApps[appRotatorPrevIndex])
                                .rotation3DEffect(
                                    .degrees(appRotatorFlip),
                                    axis: (1, 0, 0),
                                    anchor: .bottom,
                                    perspective: 0.4
                                )
                                .opacity(appRotatorFlip < 82 ? 1 : 0)
                            // Incoming face — anchored at top, starts at −88° → rotates to 0°
                            Text(pfCompatApps[appRotatorIndex])
                                .rotation3DEffect(
                                    .degrees(appRotatorFlip - 88),
                                    axis: (1, 0, 0),
                                    anchor: .top,
                                    perspective: 0.4
                                )
                                .opacity(appRotatorFlip > 6 ? 1 : 0)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.zAccent)
                        .fixedSize()
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.zAccent.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.zAccent.opacity(0.25), lineWidth: 1))
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: appRotatorIndex)
                        .clipped()
                    }
                    .transition(.opacity.combined(with: .offset(y: 5)))
                }
            }
            .frame(height: 36)
            .padding(.bottom, 22)

            // Feature pills in frosted glass tray
            HStack(spacing: 10) {
                PFFeaturePill(icon: "lock.fill",
                              text: t("100% local", "100% local", "100% local", "100% 本地", "100% ローカル", "100% локально"),
                              color: Color.zAccent)
                PFFeaturePill(icon: "bolt.fill",
                              text: t("Ultra rapide", "Ultra fast", "Ultra rápido", "极速", "超高速", "Мгновенно"),
                              color: Color.zOrange)
                PFFeaturePill(icon: "cpu",
                              text: "Apple Silicon",
                              color: Color.zBlue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Color.white.opacity(0.55)
                    Color.zAccent.opacity(0.025)
                }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
            )
            .opacity(welcomeReveal >= 4 ? 1 : 0)
            .offset(y: welcomeReveal >= 4 ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: welcomeReveal)

            // Language picker — full names, bigger pills
            HStack(spacing: 8) {
                ForEach([
                    (SupportedUILanguage.fr, "Français"),
                    (.en,                    "English"),
                    (.es,                    "Español"),
                    (.zh,                    "中文"),
                    (.ja,                    "日本語"),
                    (.ru,                    "Русский"),
                ], id: \.0.rawValue) { (uiLang, name) in
                    let active = AppState.shared.uiDisplayLanguage == uiLang
                    Button { AppState.shared.uiDisplayLanguage = uiLang } label: {
                        Text(name)
                            .font(.system(size: 13, weight: active ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(active ? Color.zAccent : Color.zSurface)
                            .foregroundColor(active ? .white : Color.zTextSub)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(active ? Color.clear : Color.zBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25), value: active)
                }
            }
            .padding(.top, 16)
            .opacity(welcomeReveal >= 5 ? 1 : 0)
            .offset(y: welcomeReveal >= 5 ? 0 : 8)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: welcomeReveal)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 44)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 1: Speed
    // ═══════════════════════════════════════════════════════════

    private var speedSlide: some View {
        VStack(spacing: 0) {
            // Heading — staggered reveal
            VStack(spacing: 6) {
                Text(t(
                    "3× plus rapide que le clavier",
                    "3× faster than typing",
                    "3× más rápido que escribir",
                    "比打字快 3 倍",
                    "タイピングの 3 倍速",
                    "В 3 раза быстрее набора"
                ))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)
                .opacity(speedReveal >= 1 ? 1 : 0)
                .offset(y: speedReveal >= 1 ? 0 : 10)
                .animation(.spring(response: 0.52, dampingFraction: 0.82), value: speedReveal)

                Text(t(
                    "Regardez la différence en temps réel.",
                    "Watch the difference in real time.",
                    "Observa la diferencia en tiempo real.",
                    "实时观察两者的差异。",
                    "リアルタイムで違いをご覧ください。",
                    "Наблюдайте разницу в реальном времени."
                ))
                .font(.system(size: 14))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
                .opacity(speedReveal >= 2 ? 1 : 0)
                .offset(y: speedReveal >= 2 ? 0 : 8)
                .animation(.spring(response: 0.52, dampingFraction: 0.82), value: speedReveal)
            }
            .padding(.top, 4)
            .padding(.bottom, 20)

            // Two comparison cards
            HStack(alignment: .top, spacing: 16) {

                // ── Keyboard card ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.zTextSub)
                        Text(t("Clavier", "Keyboard", "Teclado", "键盘", "キーボード", "Клавиатура"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.zTextSub)
                        Spacer()
                        if keyboardDone {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text(t("Terminé", "Done", "Hecho", "完成", "完了", "Готово"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(Color.zTextSub)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.zTextSub.opacity(0.12))
                            .clipShape(Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if keyboardText.isEmpty {
                            Text(t("En attente…", "Waiting…", "Esperando…", "等待中…", "待機中…", "Ожидание…"))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color.zTextDim.opacity(0.4))
                        }
                        buildKeyboardDisplayText()
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .lineLimit(nil)
                    }
                    .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.zSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.zBorder, lineWidth: 1))
                )
                .frame(maxWidth: .infinity)

                // ── Voice card ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: voiceDone ? "mic.fill" : "waveform.and.mic")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.zAccent)
                        Text(t("Voix (Zphyr)", "Voice (Zphyr)", "Voz (Zphyr)", "语音 (Zphyr)", "音声 (Zphyr)", "Голос (Zphyr)"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.zAccent)
                        Spacer()
                        if voiceDone {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(t("Terminé", "Done", "Hecho", "完成", "完了", "Готово"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.zAccent)
                            .clipShape(Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }

                    // Horizontal wrapping flow of blur-reveal chunks
                    FlowLayout(spacing: 7) {
                        ForEach(voiceChunks) { chunk in
                            BlurRevealChunk(
                                words: chunk.words,
                                textFont: .system(size: 13, weight: .regular),
                                textColor: Color.zAccent
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.zAccent.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.zAccent.opacity(0.25), lineWidth: 1))
                )
                .frame(maxWidth: .infinity)
            }
            .opacity(speedReveal >= 3 ? 1 : 0)
            .offset(y: speedReveal >= 3 ? 0 : 14)
            .animation(.spring(response: 0.52, dampingFraction: 0.82), value: speedReveal)

            // Live race bars
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Vitesse en direct", "Live speed", "Velocidad en directo", "实时速度", "リアルタイム速度", "Скорость в реальном времени"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.zTextDim)
                    .tracking(0.9)
                    .textCase(.uppercase)

                raceRow(
                    icon: "keyboard",
                    label: t("Clavier", "Keyboard", "Teclado", "键盘", "キーボード", "Клав."),
                    progress: min(1.0, Double(keyboardText.count) / 134.0),
                    color: Color.zTextSub,
                    done: keyboardDone
                )
                raceRow(
                    icon: "mic.fill",
                    label: t("Voix", "Voice", "Voz", "语音", "音声", "Голос"),
                    progress: min(1.0, Double(voiceChunks.count) / 6.0),
                    color: Color.zAccent,
                    done: voiceDone
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.zSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.zBorder, lineWidth: 1))
            )
            .padding(.top, 16)
            .opacity(speedReveal >= 3 ? 1 : 0)
            .offset(y: speedReveal >= 3 ? 0 : 14)
            .animation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.06), value: speedReveal)

            // Disclaimer
            Text(t(
                "* Les performances varient selon votre configuration (chip, RAM disponible, charge CPU).",
                "* Performance varies depending on your hardware (chip, available RAM, CPU load).",
                "* El rendimiento varía según tu hardware (chip, RAM disponible, carga de CPU).",
                "* 性能因硬件配置而异（芯片、可用 RAM、CPU 负载）。",
                "* パフォーマンスはハードウェア構成（チップ、利用可能な RAM、CPU 負荷）によって異なります。",
                "* Производительность зависит от конфигурации (чип, доступная RAM, нагрузка CPU)."
            ))
            .font(.system(size: 10))
            .foregroundColor(Color.zTextDim)
            .multilineTextAlignment(.center)
            .padding(.top, 10)
            .opacity(speedReveal >= 3 ? 1 : 0)
            .animation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.1), value: speedReveal)
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func raceRow(icon: String, label: String, progress: Double, color: Color, done: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(color)
            .frame(width: 90, alignment: .leading)

            Capsule()
                .fill(color.opacity(0.10))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(color.opacity(done ? 1.0 : 0.75))
                            .frame(width: geo.size.width * CGFloat(progress), height: 7)
                            .animation(.easeOut(duration: 0.18), value: progress)
                    }
                    .frame(height: 7)
                }

            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(color)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(percentLabel(progress))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(color.opacity(0.55))
                }
            }
            .frame(width: 34)
            .animation(.spring(response: 0.3), value: done)
        }
    }



    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 2: Features (Bento Grid)
    // ═══════════════════════════════════════════════════════════

    private var featuresSlide: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 5) {
                Text(t(
                    "Conçu pour s'effacer.",
                    "Built to disappear.",
                    "Diseñado para desaparecer.",
                    "设计为无感存在。",
                    "消えるように設計された。",
                    "Создан быть невидимым."
                ))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)

                Text(t(
                    "Tu parles. Zphyr transcrit. C'est tout.",
                    "You speak. Zphyr transcribes. That's it.",
                    "Hablas. Zphyr transcribe. Eso es todo.",
                    "你说话，Zphyr 转写，就这样。",
                    "話す。Zphyr が転写する。それだけ。",
                    "Говоришь. Zphyr пишет. Вот и всё."
                ))
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
            }
            .opacity(featReveal >= 1 ? 1 : 0)
            .offset(y: featReveal >= 1 ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: featReveal)
            .padding(.bottom, 20)

            // Bento Grid
            GeometryReader { geo in
                let g: CGFloat = 10
                let w = geo.size.width
                let col = (w - g * 2) / 3

                VStack(spacing: g) {
                    // Row 1: Local (2 cols) + Hold-to-talk (1 col)
                    HStack(alignment: .top, spacing: g) {
                        BentoLocalCard()
                            .frame(width: col * 2 + g, height: 192)
                            .opacity(featReveal >= 2 ? 1 : 0)
                            .offset(y: featReveal >= 2 ? 0 : 14)
                            .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.0), value: featReveal)

                        BentoHoldCard()
                            .frame(width: col, height: 192)
                            .opacity(featReveal >= 2 ? 1 : 0)
                            .offset(y: featReveal >= 2 ? 0 : 14)
                            .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.07), value: featReveal)
                    }

                    // Row 2: Code + Languages + Style
                    HStack(alignment: .top, spacing: g) {
                        BentoCodeCard()
                            .frame(width: col, height: 158)
                            .opacity(featReveal >= 3 ? 1 : 0)
                            .offset(y: featReveal >= 3 ? 0 : 14)
                            .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.0), value: featReveal)

                        BentoLangCard()
                            .frame(width: col, height: 158)
                            .opacity(featReveal >= 3 ? 1 : 0)
                            .offset(y: featReveal >= 3 ? 0 : 14)
                            .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.07), value: featReveal)

                        BentoStyleCard()
                            .frame(width: col, height: 158)
                            .opacity(featReveal >= 3 ? 1 : 0)
                            .offset(y: featReveal >= 3 ? 0 : 14)
                            .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.14), value: featReveal)
                    }
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 3: Profile Setup
    // ═══════════════════════════════════════════════════════════

    private var demosSlide: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 5) {
                Text(t(
                    "Personnalise Zphyr.",
                    "Personalise Zphyr.",
                    "Personaliza Zphyr.",
                    "个性化 Zphyr。",
                    "Zphyr をカスタマイズ。",
                    "Настрой Zphyr."
                ))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)

                Text(t(
                    "Choisis ton profil — on configure les styles et ton premier snippet.",
                    "Pick your profile — we'll set up styles and your first snippet.",
                    "Elige tu perfil — configuramos los estilos y tu primer snippet.",
                    "选择你的用途 — 自动配置风格和首个 snippet。",
                    "プロフィールを選ぶ — スタイルと最初のスニペットを設定。",
                    "Выбери профиль — настроим стили и первый сниппет."
                ))
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
            }
            .opacity(profileReveal >= 1 ? 1 : 0)
            .offset(y: profileReveal >= 1 ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: profileReveal)
            .padding(.bottom, 10)

            // Instruction hint (visible until a profile is selected)
            if selectedProfileIdx == nil {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zAccent)
                    Text(t(
                        "Sélectionne un profil ci-dessous",
                        "Select a profile below",
                        "Selecciona un perfil abajo",
                        "请在下方选择一个用途",
                        "下のプロフィールを選んでください",
                        "Выберите профиль ниже"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.zTextSub)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.zAccent.opacity(0.07), in: Capsule())
                .opacity(profileReveal >= 2 ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: profileReveal)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .padding(.bottom, 14)
            } else {
                Spacer().frame(height: 14)
            }

            // Profile cards — compact row, 5 cards
            let profileCount = PFOnboardingProfile.all.count
            let isCustomSelected = selectedProfileIdx == profileCount

            HStack(spacing: 10) {
                ForEach(Array(PFOnboardingProfile.all.enumerated()), id: \.offset) { idx, profile in
                    ProfileCard(
                        profile: profile,
                        isSelected: selectedProfileIdx == idx
                    ) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            selectedProfileIdx = idx
                            profileSnippetValue = profile.snippetDefaultValue
                        }
                        AppState.shared.styleWork     = profile.styleWork
                        AppState.shared.stylePersonal = profile.stylePersonal
                        AppState.shared.styleEmail    = profile.styleEmail
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.08)) {
                            profileConfigReveal = true
                        }
                    }
                    .opacity(profileReveal >= 2 ? 1 : 0)
                    .offset(y: profileReveal >= 2 ? 0 : 14)
                    .animation(
                        .spring(response: 0.52, dampingFraction: 0.8)
                            .delay(0.04 * Double(idx)),
                        value: profileReveal
                    )
                }

                // Custom card
                ProfileCard(
                    profile: PFOnboardingProfile(
                        icon: "slider.horizontal.3",
                        color: Color.zTextSub,
                        name: t("Personnalisé", "Custom", "Personalizado", "自定义", "カスタム", "Свой"),
                        tagline: t("Configure tout toi-même", "Configure everything yourself", "Configura todo tú mismo", "自行配置一切", "すべて自分で設定", "Настрой всё сам"),
                        styleWork: customStyleWork,
                        stylePersonal: customStylePersonal,
                        styleEmail: customStyleEmail,
                        snippetTrigger: "",
                        snippetExpansion: "",
                        snippetFieldLabel: "",
                        snippetDefaultValue: "",
                        snippetUserDefaultsKey: ""
                    ),
                    isSelected: isCustomSelected
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        selectedProfileIdx = profileCount
                    }
                    AppState.shared.styleWork     = customStyleWork
                    AppState.shared.stylePersonal = customStylePersonal
                    AppState.shared.styleEmail    = customStyleEmail
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.08)) {
                        profileConfigReveal = true
                    }
                }
                .opacity(profileReveal >= 2 ? 1 : 0)
                .offset(y: profileReveal >= 2 ? 0 : 14)
                .animation(
                    .spring(response: 0.52, dampingFraction: 0.8)
                        .delay(0.04 * Double(profileCount)),
                    value: profileReveal
                )
            }
            .frame(height: 170)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)

            // Configuration panel — scrollable if needed
            if profileConfigReveal {
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        if isCustomSelected {
                            CustomProfilePanel(
                                styleWork: $customStyleWork,
                                stylePersonal: $customStylePersonal,
                                styleEmail: $customStyleEmail,
                                snippetTrigger: $customSnippetTrigger,
                                snippetExpansion: $customSnippetExpansion
                            )
                        } else if let idx = selectedProfileIdx, idx < PFOnboardingProfile.all.count {
                            let profile = PFOnboardingProfile.all[idx]
                            ProfileConfigPanel(profile: profile, snippetValue: $profileSnippetValue)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 4: Language
    // ═══════════════════════════════════════════════════════════

    private var languageSlide: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            VStack(spacing: 6) {
                Text(t(
                    "Tes langues.",
                    "Your languages.",
                    "Tus idiomas.",
                    "你的语言。",
                    "あなたの言語。",
                    "Твои языки."
                ))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)

                Text(t(
                    "Configure l'interface et sélectionne les langues que tu parles.",
                    "Set up the interface and select the languages you speak.",
                    "Configura la interfaz y selecciona los idiomas que hablas.",
                    "配置界面并选择你说的语言。",
                    "インターフェースを設定し、話す言語を選んでください。",
                    "Настрой интерфейс и выбери языки, на которых говоришь."
                ))
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
            }
            .opacity(langReveal >= 1 ? 1 : 0)
            .offset(y: langReveal >= 1 ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: langReveal)
            .padding(.bottom, 16)

            // ── Two-column layout ─────────────────────────────────────
            HStack(alignment: .top, spacing: 16) {

                // ── Left: UI Language ─────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        Text(t("Langue de l'interface", "Interface language", "Idioma de la interfaz", "界面语言", "インターフェース言語", "Язык интерфейса"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.zText)
                    } icon: {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.zBlue)
                    }

                    VStack(spacing: 8) {
                        langUIRow(flag: "🇫🇷", label: "Français", lang: .fr)
                        langUIRow(flag: "🇺🇸", label: "English", lang: .en)
                        langUIRow(flag: "🇪🇸", label: "Español", lang: .es)
                        langUIRow(flag: "🇨🇳", label: "中文", lang: .zh)
                        langUIRow(flag: "🇯🇵", label: "日本語", lang: .ja)
                        langUIRow(flag: "🇷🇺", label: "Русский", lang: .ru)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                )
                .opacity(langReveal >= 2 ? 1 : 0)
                .offset(y: langReveal >= 2 ? 0 : 12)
                .animation(.spring(response: 0.52, dampingFraction: 0.8), value: langReveal)

                // ── Right: Dictation Languages ───────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label {
                            Text(t("Langues de dictée", "Dictation languages", "Idiomas de dictado", "听写语言", "音声入力言語", "Языки диктовки"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.zText)
                        } icon: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.zAccent)
                        }

                        Spacer()

                        // Selected count badge
                        let selCount = AppState.shared.selectedLanguages.count
                        Text("\(selCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.zAccent, in: Circle())
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                            ],
                            spacing: 8
                        ) {
                            ForEach(WhisperLanguage.all, id: \.id) { language in
                                PFLanguageCell(
                                    language: language,
                                    isSelected: AppState.shared.selectedLanguages.contains(where: { $0.id == language.id })
                                ) {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        if AppState.shared.selectedLanguages.contains(where: { $0.id == language.id }) {
                                            if AppState.shared.selectedLanguages.count > 1 {
                                                AppState.shared.selectedLanguages.removeAll { $0.id == language.id }
                                            }
                                        } else {
                                            AppState.shared.selectedLanguages.append(language)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }

                    // Multi-language hint
                    if AppState.shared.selectedLanguages.count > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(Color.zBlue)
                            Text(t("Détection automatique activée",
                                   "Auto-detection enabled",
                                   "Detección automática activada",
                                   "已启用自动检测",
                                   "自動検出有効",
                                   "Автоопределение включено"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.zTextSub)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.zBlue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                )
                .opacity(langReveal >= 3 ? 1 : 0)
                .offset(y: langReveal >= 3 ? 0 : 12)
                .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.06), value: langReveal)
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    // Helper for UI language rows
    @ViewBuilder
    private func langUIRow(flag: String, label: String, lang: SupportedUILanguage) -> some View {
        let active = AppState.shared.uiDisplayLanguage == lang
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                AppState.shared.uiDisplayLanguage = lang
            }
        } label: {
            HStack(spacing: 10) {
                Text(flag)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundColor(active ? Color.zText : Color.zTextSub)
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.zBlue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? Color.zBlue.opacity(0.08) : Color.black.opacity(0.02))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(active ? Color.zBlue.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 5: Model Download
    // ═══════════════════════════════════════════════════════════

    private var modelSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Ring + center ─────────────────────────────────────────
            ZStack {
                // Ambient glow
                Circle()
                    .fill(
                        modelStatus.isReady
                            ? Color.zAccent.opacity(0.18)
                            : (modelStatus.progress > 0 ? Color.zBlue.opacity(0.10) : Color.zBlue.opacity(0.05))
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 32)
                    .animation(.easeInOut(duration: 0.6), value: modelStatus.isReady)

                // Track
                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 8)
                    .frame(width: 148, height: 148)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(modelStatus.progress))
                    .stroke(
                        LinearGradient(
                            colors: modelStatus.isReady
                                ? [Color.zAccent, Color(hex: "34D399")]
                                : [Color.zAccent, Color.zBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 148, height: 148)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: modelStatus.progress)

                // Center content
                Group {
                    if modelStatus.isReady {
                        Image(systemName: "checkmark")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Color.zAccent)
                            .transition(.scale.combined(with: .opacity))
                    } else if case .failed = modelStatus {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color.zRed)
                            .transition(.scale.combined(with: .opacity))
                    } else if case .loading = modelStatus {
                        VStack(spacing: 4) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(Color.zAccent)
                                .symbolEffect(.pulse, isActive: true)
                            Text("Neural\nEngine")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color.zTextDim)
                                .multilineTextAlignment(.center)
                                .tracking(0.5)
                        }
                    } else if isPreparingModelDownload {
                        VStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.zAccent)
                            Text(t(
                                "Connexion",
                                "Connecting",
                                "Conexión",
                                "连接中",
                                "接続中",
                                "Подключение"
                            ))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.zTextDim)
                            .tracking(0.3)
                        }
                    } else {
                        Text(percentLabel(modelStatus.progress))
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.zText)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.28), value: modelStatus.progress)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: modelStatus.isReady)
            }
            .opacity(modelReveal >= 1 ? 1 : 0)
            .scaleEffect(modelReveal >= 1 ? 1 : 0.85)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: modelReveal)
            .padding(.bottom, 28)

            // ── Status title ──────────────────────────────────────────
            Text(modelTitleText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: modelTitleText)
                .opacity(modelReveal >= 2 ? 1 : 0)
                .offset(y: modelReveal >= 2 ? 0 : 6)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: modelReveal)
                .padding(.bottom, 8)

            // ── Status subtitle ───────────────────────────────────────
            Text(modelSubtitleText)
                .font(.system(size: 14))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 64)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: modelSubtitleText)
                .opacity(modelReveal >= 2 ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: modelReveal)
                .padding(.bottom, 24)

            // ── Download detail card ──────────────────────────────────
            if asrRequiresInstall, case .downloading = modelStatus {
                DownloadCard(
                    progress: modelStatus.progress,
                    stats: downloadStats,
                    isPaused: AppState.shared.isDownloadPaused,
                    lang: lang
                )
                .frame(maxWidth: 360)
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // ── Model info chips ──────────────────────────────────────
            HStack(spacing: 8) {
                if asrRequiresInstall {
                    PFInfoChip(icon: "cpu", text: asrDescriptor.displayName)
                    PFInfoChip(icon: "memorychip", text: "MLX 8-bit · ANE")
                } else {
                    PFInfoChip(icon: "apple.logo", text: "Apple Speech Analyzer")
                    PFInfoChip(icon: "bolt.horizontal", text: t("Aucun téléchargement", "No download", "Sin descarga", "无需下载", "ダウンロード不要", "Без загрузки"))
                }
                PFInfoChip(
                    icon: "lock.shield",
                    text: t("100% local", "100% local", "100% local", "100% 本地", "100% ローカル", "100% локально")
                )
            }
            .opacity(modelReveal >= 3 ? 1 : 0)
            .offset(y: modelReveal >= 3 ? 0 : 6)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: modelReveal)
            .padding(.bottom, 20)

            // ── Mic test when ready ───────────────────────────────────
            if modelStatus.isReady {
                Button {
                    showModelTest = true
                } label: {
                    Label(
                        t("Tester le micro", "Test microphone", "Probar micrófono", "测试麦克风", "マイクをテスト", "Проверить микрофон"),
                        systemImage: "mic.circle"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.zText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.zBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // ── Retry on failure ──────────────────────────────────────
            if asrRequiresInstall, case .failed = modelStatus {
                Button {
                    DictationEngine.shared.cancelModelDownload()
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        await DictationEngine.shared.loadModel()
                    }
                } label: {
                    Label(
                        t("Réessayer", "Retry", "Reintentar", "重试", "再試行", "Повторить"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.zRed)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: modelStatus.isReady)
    }

    private var modelTitleText: String {
        if !asrRequiresInstall {
            switch modelStatus {
            case .loading:
                return t("Préparation du moteur local…", "Preparing local engine…", "Preparando motor local…", "正在准备本地引擎…", "ローカルエンジンを準備中…", "Подготовка локального движка…")
            case .ready:
                return t("Moteur Apple prêt !", "Apple engine ready!", "¡Motor Apple listo!", "Apple 引擎已就绪！", "Apple エンジン準備完了！", "Apple-движок готов!")
            case .failed:
                return t("Backend indisponible", "Backend unavailable", "Backend no disponible", "后端不可用", "バックエンド利用不可", "Бэкенд недоступен")
            default:
                return t("Activation du moteur local", "Enabling local engine", "Activando motor local", "启用本地引擎", "ローカルエンジンを有効化", "Включение локального движка")
            }
        }
        switch modelStatus {
        case .notDownloaded:
            return t("Installation du moteur IA", "Installing the AI engine", "Instalando el motor IA", "安装 AI 引擎", "AI エンジンをインストール", "Установка AI-движка")
        case .downloading:
            if AppState.shared.isDownloadPaused {
                return t("En pause", "Paused", "En pausa", "已暂停", "一時停止中", "На паузе")
            }
            if isPreparingModelDownload {
                return t("Préparation du téléchargement…", "Preparing download…", "Preparando descarga…", "正在准备下载…", "ダウンロードを準備中…", "Подготовка загрузки…")
            }
            return t("Téléchargement en cours…", "Downloading…", "Descargando…", "下载中…", "ダウンロード中…", "Загрузка…")
        case .loading:
            return t("Compilation Neural Engine", "Compiling Neural Engine", "Compilando Neural Engine", "编译 Neural Engine", "Neural Engine をコンパイル中", "Компиляция Neural Engine")
        case .ready:
            return t("Moteur prêt !", "Engine ready!", "¡Motor listo!", "引擎就绪！", "エンジン準備完了！", "Движок готов!")
        case .failed:
            return t("Échec du téléchargement", "Download failed", "Descarga fallida", "下载失败", "ダウンロード失敗", "Ошибка загрузки")
        }
    }

    private var modelSubtitleText: String {
        if !asrRequiresInstall {
            return t(
                "Apple Speech Analyzer fonctionne directement en local. Aucun modèle volumineux à télécharger.",
                "Apple Speech Analyzer runs locally right away. No large model download is required.",
                "Apple Speech Analyzer funciona en local de inmediato. No requiere descargar un modelo pesado.",
                "Apple Speech Analyzer 可直接本地运行，无需下载大型模型。",
                "Apple Speech Analyzer はすぐにローカル動作します。大きなモデルのダウンロードは不要です。",
                "Apple Speech Analyzer работает локально сразу, без загрузки тяжелой модели."
            )
        }
        switch modelStatus {
        case .notDownloaded:
            return t(
                "Whisper s'installe une seule fois (~600 Mo). Il s'exécute ensuite 100% en local.",
                "Whisper installs once (~600 MB). It then runs 100% locally.",
                "Whisper se instala una sola vez (~600 MB). Funciona 100% localmente.",
                "Whisper 仅需安装一次（约 600 MB），之后 100% 本地运行。",
                "Whisper は一度だけインストール（約 600 MB）。以後 100% ローカルで動作。",
                "Whisper устанавливается один раз (~600 МБ). Далее работает 100% локально."
            )
        case .downloading:
            if isPreparingModelDownload {
                return t(
                    "Connexion au serveur de modèle… Le démarrage peut prendre quelques secondes selon le réseau.",
                    "Connecting to the model server… Startup can take a few seconds depending on your network.",
                    "Conectando al servidor del modelo… El inicio puede tardar unos segundos según tu red.",
                    "正在连接模型服务器… 根据网络情况，启动可能需要几秒钟。",
                    "モデルサーバーに接続中… ネットワーク状況により開始まで数秒かかることがあります。",
                    "Подключение к серверу модели… Запуск может занять несколько секунд в зависимости от сети."
                )
            }
            return t(
                "Whisper s'installe une seule fois (~600 Mo). Il s'exécute ensuite 100% en local.",
                "Whisper installs once (~600 MB). It then runs 100% locally.",
                "Whisper se instala una sola vez (~600 MB). Funciona 100% localmente.",
                "Whisper 仅需安装一次（约 600 MB），之后 100% 本地运行。",
                "Whisper は一度だけインストール（約 600 MB）。以後 100% ローカルで動作。",
                "Whisper устанавливается один раз (~600 МБ). Далее работает 100% локально."
            )
        case .loading:
            return t(
                "Le modèle est compilé pour ton Apple Silicon. Ça prend quelques secondes.",
                "The model is being compiled for your Apple Silicon. This takes a few seconds.",
                "El modelo se compila para tu Apple Silicon. Esto tarda unos segundos.",
                "模型正在为你的 Apple Silicon 编译，需要几秒钟。",
                "モデルがあなたの Apple Silicon 向けにコンパイルされています。数秒かかります。",
                "Модель компилируется для вашего Apple Silicon. Это займёт несколько секунд."
            )
        case .ready:
            return t(
                "Whisper tourne entièrement sur ton Mac, sans aucun serveur.",
                "Whisper runs entirely on your Mac, with no server involved.",
                "Whisper funciona completamente en tu Mac, sin servidor.",
                "Whisper 完全在你的 Mac 上本地运行，无需服务器。",
                "Whisper はサーバー不要でMac上で完全に動作します。",
                "Whisper работает полностью на вашем Mac без серверов."
            )
        case .failed(let msg):
            let prefix = t("Vérifiez votre connexion et réessayez.",
                           "Check your connection and try again.",
                           "Verifica tu conexión e inténtalo de nuevo.",
                           "请检查网络连接后重试。",
                           "接続を確認して再試行してください。",
                           "Проверьте соединение и повторите попытку.")
            return "\(prefix)\n\(msg)"
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 6: Permissions
    // ═══════════════════════════════════════════════════════════

    private var permissionsSlide: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(t(
                    "Deux accès requis",
                    "Two quick permissions",
                    "Dos accesos requeridos",
                    "需要两个权限",
                    "2 つのアクセス許可",
                    "Два разрешения"
                ))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)

                Text(t(
                    "Zphyr a besoin de ton micro pour capter ta voix, et de l'accessibilité pour insérer le texte dans n'importe quelle app.",
                    "Zphyr needs your mic to capture voice, and accessibility to insert text into any app.",
                    "Zphyr necesita el micrófono para capturar voz y accesibilidad para insertar texto en cualquier app.",
                    "Zphyr 需要麦克风来录音，以及辅助功能在任意应用中插入文字。",
                    "Zphyr は音声収録のためにマイクと、テキスト挿入のためにアクセシビリティが必要です。",
                    "Zphyr нужны микрофон для записи и специальные возможности для вставки текста."
                ))
                .font(.system(size: 14))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 20)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .padding(.horizontal, 44)

            let appState = AppState.shared
            VStack(spacing: 10) {
                // Microphone
                PFPermissionCard(
                    icon: "mic.fill",
                    iconColor: Color.zRed,
                    title: t("Microphone", "Microphone", "Micrófono", "麦克风", "マイク", "Микрофон"),
                    description: t(
                        "Capture audio pour la transcription vocale",
                        "Audio capture for voice transcription",
                        "Captura de audio para transcripción de voz",
                        "用于语音转写的音频采集",
                        "音声文字起こしのための録音",
                        "Захват звука для транскрибации"
                    ),
                    isGranted: appState.micPermission == .granted,
                    isDenied: appState.micPermission == .denied,
                    onAllow: { Task { await AppState.shared.requestMicrophoneAccess() } },
                    onOpenSettings: {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        )
                    }
                )

                // Accessibility
                PFPermissionCard(
                    icon: "accessibility",
                    iconColor: Color.zBlue,
                    title: t("Accessibilité", "Accessibility", "Accesibilidad", "辅助功能", "アクセシビリティ", "Спецвозможности"),
                    description: t(
                        "Insérer le texte dans n'importe quelle application",
                        "Insert text into any application",
                        "Insertar texto en cualquier aplicación",
                        "在任意应用中插入文字",
                        "あらゆるアプリにテキストを挿入",
                        "Вставка текста в любое приложение"
                    ),
                    isGranted: appState.accessibilityGranted,
                    isDenied: false,
                    onAllow: { AppState.shared.requestAccessibilityAccess() },
                    onOpenSettings: { AppState.shared.requestAccessibilityAccess() }
                )
            }
            .padding(.horizontal, 44)

            if !appState.accessibilityGranted {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color.zBlue)
                    Text(t(
                        "Après l'accessibilité, un redémarrage de Zphyr peut être nécessaire.",
                        "After granting accessibility, a Zphyr restart may be needed.",
                        "Tras conceder accesibilidad, puede que necesites reiniciar Zphyr.",
                        "授予辅助功能权限后，可能需要重启 Zphyr。",
                        "アクセシビリティ許可後、Zphyr の再起動が必要な場合があります。",
                        "После разрешения может потребоваться перезапуск Zphyr."
                    ))
                    .font(.system(size: 11))
                    .foregroundColor(Color.zTextSub)
                    .lineSpacing(2)
                }
                .padding(.horizontal, 44)
                .padding(.top, 12)
            }

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 7: Shortcut
    // ═══════════════════════════════════════════════════════════

    private var shortcutSlide: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            VStack(spacing: 6) {
                Text(t(
                    "Ta touche magique.",
                    "Your magic key.",
                    "Tu tecla mágica.",
                    "你的魔法键。",
                    "マジックキー。",
                    "Твоя волшебная клавиша."
                ))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)

                Text(t(
                    "Maintiens-la, parle, relâche. Fonctionne partout sur macOS.",
                    "Hold it, speak, release. Works everywhere on macOS.",
                    "Mantenla, habla, suéltala. Funciona en todas partes.",
                    "按住说话松开，在 macOS 任意位置生效。",
                    "押して話して離す。macOS のどこでも動作。",
                    "Удержи, говори, отпусти. Работает везде на macOS."
                ))
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
            }
            .opacity(shortcutReveal >= 1 ? 1 : 0)
            .offset(y: shortcutReveal >= 1 ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: shortcutReveal)
            .padding(.bottom, 20)

            // ── Main content: hero key + steps ───────────────────────
            HStack(alignment: .top, spacing: 16) {

                // ── Left: Key display + picker ────────────────────────
                VStack(spacing: 18) {
                    // Hero physical key
                    ZStack {
                        // Glow behind
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.zAccent.opacity(0.18))
                            .frame(width: 130, height: 130)
                            .blur(radius: 24)
                            .offset(y: shortcutKeyPressed ? 4 : 0)

                        // Key body — outer shadow (depth)
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 112, height: 112)
                            .shadow(color: Color.black.opacity(shortcutKeyPressed ? 0.06 : 0.14),
                                    radius: shortcutKeyPressed ? 4 : 12, x: 0, y: shortcutKeyPressed ? 2 : 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.zAccent.opacity(0.5), lineWidth: 1.5)
                            )

                        // Key content
                        VStack(spacing: 4) {
                            Text(ShortcutManager.shared.selectedTriggerKey.symbol)
                                .font(.system(size: 44, weight: .thin))
                                .foregroundColor(Color.zAccent)
                            Text(keySubLabel(ShortcutManager.shared.selectedTriggerKey))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.zTextDim)
                                .tracking(1.2)
                        }
                    }
                    .scaleEffect(shortcutKeyPressed ? 0.93 : 1.0)
                    .offset(y: shortcutKeyPressed ? 5 : 0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: shortcutKeyPressed)
                    .onTapGesture {
                        guard !shortcutKeyPressed else { return }
                        withAnimation(.spring(response: 0.14, dampingFraction: 0.65)) { shortcutKeyPressed = true }
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { shortcutKeyPressed = false }
                        }
                    }

                    // Key name label
                    Text(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.zAccent)

                    Divider().padding(.horizontal, 8)

                    // Key picker
                    VStack(spacing: 6) {
                        Text(t("Changer de touche", "Change key", "Cambiar tecla", "更改按键", "キーを変更", "Сменить клавишу"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.zTextDim)
                            .padding(.bottom, 2)

                        ForEach(TriggerKey.allCases) { key in
                            let active = ShortcutManager.shared.selectedTriggerKey == key
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    ShortcutManager.shared.selectedTriggerKey = key
                                    shortcutKeyPressed = true
                                }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(220))
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                        shortcutKeyPressed = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(key.symbol)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(active ? Color.zAccent : Color.zTextSub)
                                        .frame(width: 20)
                                    Text(keySubLabel(key))
                                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                                        .foregroundColor(active ? Color.zText : Color.zTextSub)
                                    Spacer()
                                    if active {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.zAccent)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(active ? Color.zAccent.opacity(0.07) : Color.black.opacity(0.02))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(active ? Color.zAccent.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: active)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 220, maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                )
                .opacity(shortcutReveal >= 2 ? 1 : 0)
                .offset(y: shortcutReveal >= 2 ? 0 : 14)
                .animation(.spring(response: 0.52, dampingFraction: 0.8), value: shortcutReveal)

                // ── Right: How-to + custom ────────────────────────────
                VStack(spacing: 14) {
                    // 3-step flow
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("Comment ça marche", "How it works", "Cómo funciona", "如何使用", "使い方", "Как это работает"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.zText)
                            .padding(.bottom, 14)

                        ShortcutStepRow(
                            number: "1",
                            icon: "hand.point.up.fill",
                            color: Color.zPurple,
                            title: t("Maintiens", "Hold", "Mantén", "按住", "押す", "Удержи"),
                            subtitle: ShortcutManager.shared.selectedTriggerKey.displayName(for: lang)
                        )

                        stepConnector

                        ShortcutStepRow(
                            number: "2",
                            icon: "mic.fill",
                            color: Color.zRed,
                            title: t("Parle", "Speak", "Habla", "说话", "話す", "Говори"),
                            subtitle: t("Dicte ton texte", "Dictate your text", "Dicta tu texto", "口述文本", "テキストを口述", "Произнеси текст")
                        )

                        stepConnector

                        ShortcutStepRow(
                            number: "3",
                            icon: "text.cursor",
                            color: Color.zAccent,
                            title: t("Relâche", "Release", "Suelta", "松开", "離す", "Отпусти"),
                            subtitle: t("Texte inséré instantanément", "Text inserted instantly", "Texto insertado al instante", "文本即时插入", "テキストが即座に挿入", "Текст вставлен мгновенно")
                        )
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                    )

                    // Custom shortcut section
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text(t("Raccourci personnalisé", "Custom shortcut", "Atajo personalizado", "自定义快捷键", "カスタムショートカット", "Свой ярлык"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.zText)
                        } icon: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 13))
                                .foregroundColor(Color.zBlue)
                        }

                        Text(t(
                            "Enregistre n'importe quelle combinaison de touches comme déclencheur.",
                            "Record any key combination as a trigger.",
                            "Graba cualquier combinación de teclas como disparador.",
                            "录制任意按键组合作为触发器。",
                            "任意のキー組み合わせをトリガーとして記録。",
                            "Запиши любое сочетание клавиш как триггер."
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2)

                        PFCustomShortcutRecorder()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(shortcutReveal >= 3 ? 1 : 0)
                .offset(y: shortcutReveal >= 3 ? 0 : 14)
                .animation(.spring(response: 0.52, dampingFraction: 0.8).delay(0.06), value: shortcutReveal)
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var stepConnector: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 20 + 16)  // number circle width + leading padding
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(width: 1, height: 18)
                .padding(.vertical, 2)
            Spacer()
        }
    }

    private func keySubLabel(_ key: TriggerKey) -> String {
        switch key {
        case .rightOption:  return "RIGHT"
        case .leftOption:   return "LEFT"
        case .rightControl: return "RIGHT"
        case .rightShift:   return "RIGHT"
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 8: Ready
    // ═══════════════════════════════════════════════════════════

    private var readySlide: some View {
        VStack(spacing: 0) {
            Spacer()

            // Celebration icon
            ZStack {
                Circle()
                    .fill(Color.zAccent.opacity(0.15))
                    .frame(width: 130, height: 130)
                    .scaleEffect(glowPulse)
                    .blur(radius: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 92, height: 92)
                    .overlay(
                        Circle().stroke(Color.zAccent.opacity(0.55), lineWidth: 1.5)
                    )
                    .shadow(color: Color.zAccent.opacity(0.22), radius: 22, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color.zAccent)
            }
            .scaleEffect(readyScale)
            .opacity(readyOpacity)
            .padding(.bottom, 28)

            Text(t(
                "Tu es prêt !",
                "You're all set!",
                "¡Estás listo!",
                "准备好了！",
                "準備完了！",
                "Всё готово!"
            ))
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "1A1A1A"), Color(hex: "3D3D4A")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .scaleEffect(readyScale)
            .opacity(readyOpacity)
            .padding(.bottom, 12)

            Text(t(
                "Zphyr est configuré et prêt à transformer ta voix en texte, instantanément.",
                "Zphyr is configured and ready to turn your voice into text, instantly.",
                "Zphyr está configurado y listo para convertir tu voz en texto al instante.",
                "Zphyr 已配置好，随时将你的语音即时转换为文字。",
                "Zphyr の設定が完了し、音声をすぐにテキストに変換できます。",
                "Zphyr настроен и готов мгновенно превращать вашу речь в текст."
            ))
            .font(.system(size: 16))
            .foregroundColor(Color.zTextSub)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
            .opacity(readyOpacity)

            // Summary chips
            HStack(spacing: 10) {
                PFReadyChip(
                    icon: "globe",
                    text: AppState.shared.selectedLanguage.name,
                    color: Color.zAccent
                )
                if AppState.shared.micPermission == .granted {
                    PFReadyChip(
                        icon: "mic.fill",
                        text: t("Micro ✓", "Mic ✓", "Mic ✓", "麦克风 ✓", "マイク ✓", "Микрофон ✓"),
                        color: Color.zGreen
                    )
                }
                if AppState.shared.accessibilityGranted {
                    PFReadyChip(
                        icon: "accessibility",
                        text: t("Accès ✓", "Access ✓", "Acceso ✓", "权限 ✓", "権限 ✓", "Доступ ✓"),
                        color: Color.zBlue
                    )
                }
                PFReadyChip(
                    icon: "checkmark.circle.fill",
                    text: t("Modèle ✓", "Model ✓", "Modelo ✓", "模型 ✓", "モデル ✓", "Модель ✓"),
                    color: Color.zGreen
                )
            }
            .opacity(readyOpacity)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 44)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Shared Subcomponents
// ═══════════════════════════════════════════════════════════════

// MARK: Primary Button

private struct PFPrimaryButton: View {
    let label: String
    let icon: String
    var isAccent: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isAccent ? Color(hex: "F8F8F6") : Color(hex: "1A1A1A"))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                isAccent
                    ? Color(hex: "22D3B8")
                    : (isHovered ? Color(hex: "1A1A1A").opacity(0.12) : Color(hex: "1A1A1A").opacity(0.06))
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAccent ? Color.clear : Color(hex: "1A1A1A").opacity(0.14), lineWidth: 1)
            )
            .shadow(
                color: isAccent
                    ? Color(hex: "22D3B8").opacity(isHovered ? 0.30 : 0.15)
                    : Color.black.opacity(isHovered ? 0.10 : 0.05),
                radius: isHovered ? 14 : 6,
                x: 0, y: isHovered ? 6 : 3
            )
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
    }
}

// MARK: - Welcome Animated Background (mouse-reactive)

private struct WelcomeAnimatedBackground: View {

    struct BlobDef {
        let baseX, baseY: Double    // [0,1] relative screen position
        let radius: Double
        let opacity: Double
        let speedX, speedY: Double  // oscillation speed (rad/s)
        let phase: Double
        let r, g, b: Double         // 0–255
        let attraction: Double      // how much it follows the mouse [0.0–0.5]
        let springResponse: Double  // spring stiffness (seconds)
    }

    private let blobs: [BlobDef] = [
        BlobDef(baseX:0.12, baseY:0.18, radius:290, opacity:0.27, speedX:0.072, speedY:0.051, phase:0.0, r:34,  g:211, b:184, attraction:0.17, springResponse:1.9), // teal — heavy
        BlobDef(baseX:0.83, baseY:0.72, radius:255, opacity:0.21, speedX:0.048, speedY:0.068, phase:1.9, r:79,  g:126, b:247, attraction:0.27, springResponse:1.1), // blue — medium
        BlobDef(baseX:0.52, baseY:0.06, radius:225, opacity:0.14, speedX:0.081, speedY:0.058, phase:3.6, r:175, g:82,  b:222, attraction:0.12, springResponse:2.5), // purple — very slow
        BlobDef(baseX:0.18, baseY:0.86, radius:245, opacity:0.17, speedX:0.059, speedY:0.043, phase:5.1, r:34,  g:211, b:184, attraction:0.33, springResponse:0.85),// teal 2 — fast
        BlobDef(baseX:0.90, baseY:0.22, radius:215, opacity:0.12, speedX:0.091, speedY:0.054, phase:2.7, r:79,  g:126, b:247, attraction:0.22, springResponse:1.4), // blue 2
    ]

    // Mouse position and spring offsets (one per blob)
    @State private var mousePos: CGPoint = .zero
    @State private var containerSize: CGSize = CGSize(width: 1060, height: 660)
    @State private var blobOffsets: [CGSize] = Array(repeating: .zero, count: 5)
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color(hex: "F8F8F6").ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    // ── Aurora canvas (blurred) ──────────────────────────
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                        Canvas { ctx, size in
                            let t = tl.date.timeIntervalSinceReferenceDate
                            for (i, blob) in blobs.enumerated() {
                                // Sine-wave natural drift + spring pull toward mouse
                                let cx = blob.baseX * size.width
                                       + sin(t * blob.speedX + blob.phase) * 90
                                       + blobOffsets[i].width
                                let cy = blob.baseY * size.height
                                       + cos(t * blob.speedY + blob.phase) * 72
                                       + blobOffsets[i].height
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: cx - blob.radius, y: cy - blob.radius,
                                                           width: blob.radius * 2, height: blob.radius * 2)),
                                    with: .color(Color(red: blob.r/255, green: blob.g/255,
                                                       blue: blob.b/255, opacity: blob.opacity))
                                )
                            }
                        }
                        .blur(radius: 75)
                    }

                    // ── Cursor lens — crisp radial light that follows exactly ──
                    if isHovering {
                        ZStack {
                            // Outer soft halo
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(hex: "22D3B8").opacity(0.12), .clear],
                                        center: .center, startRadius: 0, endRadius: 130
                                    )
                                )
                                .frame(width: 260, height: 260)

                            // Inner sharp core
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 18, height: 18)
                                .blur(radius: 6)
                        }
                        .position(mousePos)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: isHovering)
                    }
                }
                .onAppear {
                    containerSize = geo.size
                    mousePos = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .onChange(of: geo.size) { _, s in containerSize = s }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        // Track cursor
                        withAnimation(.linear(duration: 0.0)) { mousePos = loc }

                        if !isHovering {
                            withAnimation(.easeIn(duration: 0.2)) { isHovering = true }
                        }

                        // Pull each blob toward cursor (relative to screen center)
                        let dx = loc.x - containerSize.width  / 2
                        let dy = loc.y - containerSize.height / 2
                        for (i, blob) in blobs.enumerated() {
                            withAnimation(.spring(response: blob.springResponse, dampingFraction: 0.76)) {
                                blobOffsets[i] = CGSize(width: dx * blob.attraction,
                                                        height: dy * blob.attraction)
                            }
                        }

                    case .ended:
                        withAnimation(.easeOut(duration: 0.3)) { isHovering = false }
                        // Blobs drift back to natural path
                        for i in blobs.indices {
                            withAnimation(.spring(response: 2.2, dampingFraction: 0.68)) {
                                blobOffsets[i] = .zero
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Welcome Waveform Hero

private struct WelcomeWaveformHero: View {
    private let barCount = 26

    var body: some View {
        ZStack {
            // Glow halo behind bars
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "22D3B8").opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 72
                    )
                )
                .frame(width: 160, height: 80)
                .blur(radius: 18)

            // Equalizer bars
            HStack(alignment: .center, spacing: 4.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    WelcomeWaveBar(index: i, total: barCount)
                }
            }
            .frame(height: 68)
        }
    }
}

private struct WelcomeWaveBar: View {
    let index: Int
    let total: Int

    // Shape: bell curve — center bars taller
    private var maxH: CGFloat {
        let center = Double(total - 1) / 2.0
        let dist = abs(Double(index) - center) / center
        return CGFloat(60 - dist * dist * 42)
    }
    private var duration: Double { 0.55 + Double((index * 7) % 5) * 0.18 }
    private var delay: Double    { Double(index) * 0.038 }

    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(barGradient)
            .frame(width: 4, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
                ) {
                    height = max(6, maxH)
                }
            }
    }

    private var barGradient: LinearGradient {
        let center = Double(total - 1) / 2.0
        let dist = abs(Double(index) - center) / center
        let opacity = 1.0 - dist * 0.35
        return LinearGradient(
            stops: [
                .init(color: Color(hex: "22D3B8").opacity(opacity), location: 0),
                .init(color: Color(hex: "4F7EF7").opacity(opacity * 0.85), location: 0.55),
                .init(color: Color(hex: "AF52DE").opacity(opacity * 0.6), location: 1.0),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: Feature Pill (Welcome slide)

private struct PFFeaturePill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "444440"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Color.white.opacity(0.55)
                color.opacity(0.07)
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(color.opacity(0.18), lineWidth: 0.75))
        .shadow(color: color.opacity(0.10), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

// MARK: Feature Card (Features slide)

private struct PFFeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "666660"))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isHovered ? color.opacity(0.35) : Color(hex: "E5E5E0"), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
    }
}

// MARK: Language Cell

private struct PFLanguageCell: View {
    let language: WhisperLanguage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(language.flag)
                    .font(.system(size: 17))
                Text(language.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.zText : Color.zTextSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.zAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.zAccent.opacity(0.08)
                            : (isHovered ? Color.black.opacity(0.03) : Color.zBg.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.zAccent.opacity(0.4) : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
    }
}

// MARK: UI Language Button

private struct PFUILanguageButton: View {
    let flag: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(flag)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "1A1A1A") : Color(hex: "555550"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "22D3B8"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? Color(hex: "22D3B8").opacity(0.10)
                            : (isHovered ? Color(hex: "1A1A1A").opacity(0.04) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color(hex: "22D3B8").opacity(0.45) : Color(hex: "E5E5E0"),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: Trigger Key Button

private struct PFTriggerKeyButton: View {
    let key: TriggerKey
    let isSelected: Bool
    let lang: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(key.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "22D3B8") : Color(hex: "888880"))
                Text(key.displayName(for: lang))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "1A1A1A") : Color(hex: "555550"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "22D3B8"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? Color(hex: "22D3B8").opacity(0.10)
                            : (isHovered ? Color(hex: "1A1A1A").opacity(0.04) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color(hex: "22D3B8").opacity(0.45) : Color(hex: "E5E5E0"),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: Permission Card

private struct PFPermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let isDenied: Bool
    let onAllow: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.13))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "666660"))
            }

            Spacer()

            permissionBadge
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isGranted ? Color(hex: "34C759").opacity(0.3) : Color(hex: "E5E5E0"),
                            lineWidth: 1
                        )
                )
        )
    }

    @ViewBuilder
    private var permissionBadge: some View {
        if isGranted {
            Label(
                t("Accordé", "Granted", "Concedido", "已授权", "許可済み", "Разрешено"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(hex: "34C759"))
        } else if isDenied {
            Button(action: onOpenSettings) {
                Text(t("Ouvrir Réglages", "Open Settings", "Abrir Ajustes", "打开设置", "設定を開く", "Настройки"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "FF3B30"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onAllow) {
                Text(t("Autoriser", "Allow", "Permitir", "允许", "許可する", "Разрешить"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "22D3B8"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Custom Shortcut Recorder

private struct PFCustomShortcutRecorder: View {
    @State private var isRecording: Bool = false
    private var manager: ShortcutManager { ShortcutManager.shared }

    var body: some View {
        HStack(spacing: 10) {
            if let custom = manager.recordedShortcut {
                // Show current custom shortcut
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(Color.zAccent)
                    Text(custom.displayText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.zText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.zAccent.opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.zAccent.opacity(0.35), lineWidth: 1.2))

                // Clear button
                Button {
                    manager.clearCustomShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.zTextDim)
                }
                .buttonStyle(.plain)
            } else if isRecording {
                // Recording state
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.zRed)
                        .frame(width: 8, height: 8)
                        .opacity(isRecording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                    Text(t("Appuyez sur une touche…",
                           "Press a key…",
                           "Pulsa una tecla…",
                           "按下一个键…",
                           "キーを押してください…",
                           "Нажмите клавишу…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.zText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.zRed.opacity(0.06))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.zRed.opacity(0.3), lineWidth: 1))

                Button(t("Annuler", "Cancel", "Cancelar", "取消", "キャンセル", "Отмена")) {
                    manager.stopRecording()
                    isRecording = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Color.zTextSub)
            } else {
                // Record button
                Button {
                    isRecording = true
                    manager.startRecording { recorded in
                        manager.recordedShortcut = recorded
                        isRecording = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(t("Enregistrer un raccourci",
                               "Record a shortcut",
                               "Grabar atajo",
                               "录制快捷键",
                               "ショートカットを記録",
                               "Записать сочетание"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color.zText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.zSurface2)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.zBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Shortcut Step Row

private struct ShortcutStepRow: View {
    let number: String
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.zText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.zTextSub)
            }

            Spacer()
        }
    }
}

// MARK: - Download Card (Model slide)

private struct DownloadCard: View {
    let progress: Double
    let stats: DownloadStats
    let isPaused: Bool
    let lang: String

    @State private var shimmerX: CGFloat = -1.0
    @State private var dotPulse: Bool = false
    private var isPreparingTransfer: Bool {
        !isPaused && stats.bytesReceived < 256_000 && stats.speedBytesPerSec < 20_000
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Progress bar ────────────────────────────────────────────
            GeometryReader { geo in
                let fillW = geo.size.width * CGFloat(progress)
                let visibleFillW = isPreparingTransfer ? max(fillW, 6) : fillW
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 6)

                    // Fill
                    Capsule()
                        .fill(LinearGradient(
                            colors: isPaused
                                ? [Color(hex: "CCCCCA"), Color(hex: "BBBBBA")]
                                : [Color.zAccent, Color.zBlue],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: visibleFillW, height: 6)
                        .animation(.easeInOut(duration: 0.45), value: progress)
                        // Shimmer overlay (only while downloading)
                        .overlay(
                            Group {
                                if !isPaused {
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [.clear, .white.opacity(0.45), .clear],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                        .frame(width: visibleFillW * 0.4)
                                        .offset(x: visibleFillW * shimmerX)
                                }
                            }
                        )
                        .clipShape(Capsule())
                    if isPreparingTransfer {
                        Circle()
                            .fill(Color.zBlue.opacity(dotPulse ? 0.95 : 0.5))
                            .frame(width: 6, height: 6)
                            .offset(x: 1)
                    }
                }
                .onAppear {
                    guard !isPaused else { return }
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        shimmerX = 1.0
                    }
                    if isPreparingTransfer {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            dotPulse = true
                        }
                    }
                }
                .onChange(of: isPaused) { _, paused in
                    if paused {
                        shimmerX = -1.0
                    } else {
                        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                            shimmerX = 1.0
                        }
                    }
                }
                .onChange(of: isPreparingTransfer) { _, preparing in
                    if preparing {
                        dotPulse = false
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            dotPulse = true
                        }
                    } else {
                        dotPulse = false
                    }
                }
            }
            .frame(height: 6)
            .padding(.bottom, 16)

            // ── Stats row ───────────────────────────────────────────────
            if isPaused {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.zTextDim)
                    Text(L10n.ui(for: lang, fr: "Téléchargement en pause",
                                 en: "Download paused",
                                 es: "Descarga pausada",
                                 zh: "下载已暂停",
                                 ja: "ダウンロードを一時停止",
                                 ru: "Загрузка приостановлена"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Color.zTextDim)
                    if stats.bytesReceived > 0 {
                        Text("· \(stats.formattedReceived)")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundColor(Color.zTextDim.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 14)
            } else {
                if isPreparingTransfer {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.72)
                        Text(L10n.ui(
                            for: lang,
                            fr: "Préparation du téléchargement…",
                            en: "Preparing download…",
                            es: "Preparando descarga…",
                            zh: "正在准备下载…",
                            ja: "ダウンロードを準備中…",
                            ru: "Подготовка загрузки…"
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(Color.zTextDim)
                    }
                    .padding(.bottom, 14)
                } else {
                    HStack(spacing: 0) {
                        if stats.bytesReceived > 0 {
                            DownloadStatItem(icon: "arrow.down", value: stats.formattedReceived)
                        }
                        if stats.bytesReceived > 0 && !stats.formattedSpeed.isEmpty {
                            statDivider
                        }
                        if !stats.formattedSpeed.isEmpty {
                            DownloadStatItem(icon: "gauge.medium", value: stats.formattedSpeed)
                        }
                        if !stats.formattedSpeed.isEmpty && !stats.eta.isEmpty {
                            statDivider
                        }
                        if !stats.eta.isEmpty {
                            DownloadStatItem(icon: "clock", value: stats.eta)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }

            // ── Action buttons ──────────────────────────────────────────
            HStack(spacing: 8) {
                // Pause / Resume
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        if isPaused {
                            DictationEngine.shared.resumeModelDownload()
                        } else {
                            DictationEngine.shared.pauseModelDownload()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(isPaused
                             ? L10n.ui(for: lang, fr: "Reprendre", en: "Resume", es: "Reanudar", zh: "继续", ja: "再開", ru: "Возобновить")
                             : L10n.ui(for: lang, fr: "Pause",     en: "Pause",  es: "Pausar",   zh: "暂停", ja: "一時停止", ru: "Пауза"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.zText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(isPaused ? Color.zAccent.opacity(0.10) : Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Cancel
                Button {
                    DictationEngine.shared.cancelModelDownload()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text(L10n.ui(for: lang, fr: "Annuler", en: "Cancel", es: "Cancelar", zh: "取消", ja: "キャンセル", ru: "Отменить"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.zTextSub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
            isPaused ? Color(hex: "DDDDDA") : Color.zBorder, lineWidth: 1))
        .shadow(color: .black.opacity(isPaused ? 0.03 : 0.06), radius: isPaused ? 6 : 12, y: 2)
        .animation(.easeInOut(duration: 0.3), value: isPaused)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.zBorder)
            .frame(width: 1, height: 26)
    }
}

private struct DownloadStatItem: View {
    let icon: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.zTextDim)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(Color.zText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Stat Chip (Model slide)

private struct PFStatChip: View {
    let icon: String
    let text: String
    var color: Color = Color(hex: "888880")

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: Info Chip (Model slide)

private struct PFInfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(Color(hex: "666660"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "F0F0EE"))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "E5E5E0"), lineWidth: 1))
    }
}

// MARK: Ready Summary Chip

private struct PFReadyChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "444440"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.09))
        .cornerRadius(20)
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ModelTestView (preserved from original)
// ═══════════════════════════════════════════════════════════════

struct ModelTestView: View {
    private var modelStatus: ModelStatus { AppState.shared.modelStatus }

    @State private var testResult: String = ""
    @State private var isTesting = false
    @State private var testDuration: Double = 0
    @State private var recordingForTest = false
    @State private var selectedScenario: TestScenario = .voice

    enum TestScenario: String, CaseIterable, Identifiable {
        case voice
        case code
        case multilang

        var id: String { rawValue }

        func label(for languageCode: String) -> String {
            switch self {
            case .voice:
                return L10n.ui(for: languageCode, fr: "Voix libre", en: "Free voice", es: "Voz libre", zh: "自由语音", ja: "フリーボイス", ru: "Свободная речь")
            case .code:
                return L10n.ui(for: languageCode, fr: "Code", en: "Code", es: "Código", zh: "代码", ja: "コード", ru: "Код")
            case .multilang:
                return L10n.ui(for: languageCode, fr: "Multilingue", en: "Multilingual", es: "Multilingüe", zh: "多语言", ja: "多言語", ru: "Многоязычный")
            }
        }

        var icon: String {
            switch self {
            case .voice:     return "mic.fill"
            case .code:      return "chevron.left.forwardslash.chevron.right"
            case .multilang: return "globe"
            }
        }

        var samplePhrases: [String] {
            switch self {
            case .voice:
                return [
                    "Bonjour, voici un test de transcription vocale.",
                    "The quick brown fox jumps over the lazy dog.",
                    "Aujourd'hui j'ai travaillé sur une nouvelle fonctionnalité.",
                ]
            case .code:
                return [
                    "func authenticate(user: String) async throws -> AuthToken",
                    "let viewModel = UserViewModel(repository: .shared)",
                    "override func viewDidLoad() { super.viewDidLoad() }",
                ]
            case .multilang:
                return [
                    "Bonjour, comment allez-vous aujourd'hui ?",
                    "Hello, how are you doing today?",
                    "Hola, ¿cómo estás hoy?",
                ]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if modelStatus.isReady { readyView } else { notReadyView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notReadyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color(hex: "CCCCCC"))
            Text(t(
                "Le modèle doit être téléchargé avant de pouvoir être testé.",
                "The model must be downloaded before it can be tested.",
                "El modelo debe descargarse antes de poder probarse.",
                "必须先下载模型才能进行测试。",
                "モデルをテストする前にダウンロードが必要です。",
                "Перед тестом необходимо скачать модель."
            ))
            .font(.system(size: 13))
            .foregroundColor(Color(hex: "AAAAAA"))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(TestScenario.allCases) { scenario in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedScenario = scenario
                                testResult = ""
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: scenario.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(scenario.label(for: AppState.shared.selectedLanguage.id))
                                    .font(.system(size: 12, weight: selectedScenario == scenario ? .semibold : .regular))
                            }
                            .foregroundColor(selectedScenario == scenario ? Color(hex: "1A1A1A") : Color(hex: "888880"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedScenario == scenario ? Color.white : Color.clear)
                                    .shadow(color: .black.opacity(selectedScenario == scenario ? 0.07 : 0), radius: 4, x: 0, y: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(5)
                .background(Color(hex: "E5E5E0").opacity(0.6))
                .cornerRadius(12)

                Button {
                    Task { await runMicTest() }
                } label: {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView().scaleEffect(0.75).tint(.white)
                            Text(recordingForTest
                                 ? t("Écoute en cours…", "Listening…", "Escuchando…", "正在监听…", "聞き取り中…", "Слушаю…")
                                 : t("Transcription…", "Transcribing…", "Transcribiendo…", "转写中…", "文字起こし中…", "Транскрибация…"))
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(t("Dicter une phrase (3s)", "Dictate a phrase (3s)", "Dictar una frase (3s)", "听写一句话（3秒）", "フレーズを音声入力（3秒）", "Продиктовать фразу (3с)"))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(isTesting ? Color(hex: "888880") : Color(hex: "1A1A1A"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isTesting)

                if !testResult.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(t("Résultat", "Result", "Resultado", "结果", "結果", "Результат"),
                                  systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "34C759"))
                            Spacer()
                            if testDuration > 0 {
                                Text(String(format: "%.1fs", testDuration))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundColor(Color(hex: "AAAAAA"))
                            }
                        }
                        Text(testResult)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "1A1A1A"))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "F7F7F5"))
                            .cornerRadius(8)
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 16)
        }
    }

    private func runMicTest() async {
        isTesting = true
        recordingForTest = true
        testResult = ""
        let start = Date()
        await DictationEngine.shared.startDictation()
        try? await Task.sleep(for: .seconds(3))
        recordingForTest = false
        await DictationEngine.shared.stopDictation()
        testDuration = Date().timeIntervalSince(start) - 3
        testResult = AppState.shared.lastTranscription.isEmpty
            ? t("(aucun audio détecté)", "(no audio detected)", "(no se detectó audio)", "（未检测到音频）", "（音声が検出されませんでした）", "(аудио не обнаружено)")
            : AppState.shared.lastTranscription
        isTesting = false
    }
}

// MARK: - Flow Layout (horizontal wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, offset) in layout(in: bounds.width, subviews: subviews).offsets.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            offsets.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return (offsets, CGSize(width: maxWidth, height: y + rowH))
    }
}

// MARK: - Speed Slide Support Types

private struct VoiceChunk: Identifiable {
    let id = UUID()
    let words: String
}

private enum SpeedTypeOp {
    case char(Character)
    case backspace
    case pause(Int)
    case markError
    case clearError
}

private struct BlurRevealChunk: View {
    let words: String
    var textFont: Font = .system(size: 13, weight: .regular)
    var textColor: Color = .primary

    @State private var blurAmt: CGFloat = 10
    @State private var opacity: Double = 0

    var body: some View {
        Text(words)
            .font(textFont)
            .foregroundColor(textColor)
            .blur(radius: blurAmt)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.28)) { opacity = 1.0 }
                withAnimation(.easeOut(duration: 0.52).delay(0.07)) { blurAmt = 0 }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Bento Cards (Features slide)
// ─────────────────────────────────────────────────────────────────────────────

private struct BentoCellBg: View {
    let accent: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 5)
    }
}

// ── Card 1: 100% local ───────────────────────────────────────────────────────
private struct BentoLocalCard: View {
    @State private var ringScales: [CGFloat] = [1, 1, 1]
    @State private var ringOpacities: [Double] = [0.55, 0.35, 0.18]
    private let accent = Color.zAccent

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BentoCellBg(accent: accent)

            // Decorative sonar rings
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(accent.opacity(ringOpacities[i]), lineWidth: 1.5)
                        .scaleEffect(ringScales[i])
                }
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 28, height: 28)
            .padding(20)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("100% local · Zéro cloud")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.zText)

                    Text("Whisper tourne directement sur l'Apple Silicon Neural Engine. Aucune requête réseau. Aucune donnée ne quitte jamais ton Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // On-device badge
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accent)
                    Text("On-device · Neural Engine")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accent.opacity(0.09), in: Capsule())
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await pulseSonarLoop() }
    }

    @MainActor
    private func pulseSonarLoop() async {
        while !Task.isCancelled {
            for i in 0..<3 {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 1.6)) {
                    ringScales[i] = 2.8
                    ringOpacities[i] = 0
                }

                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.none) {
                    ringScales[i] = 1
                    ringOpacities[i] = i == 0 ? 0.55 : i == 1 ? 0.35 : 0.18
                }
            }
        }
    }
}

// ── Card 2: Hold-to-talk ─────────────────────────────────────────────────────
private struct BentoHoldCard: View {
    private let accent = Color.zPurple
    @State private var barHeights: [CGFloat] = Array(repeating: 4, count: 9)
    @State private var isActive = false
    @State private var phase: Double = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BentoCellBg(accent: accent)

            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold-to-talk")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.zText)
                    Text("Maintiens ⌥ Option droite. Relâche pour transcrire et insérer automatiquement.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // Live waveform
                HStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent.opacity(0.7 + Double(barHeights[i]) / 80))
                            .frame(width: 3, height: barHeights[i])
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Key cap overlay bottom right
            Text("⌥")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(accent)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 1))
                )
                .padding(14)
        }
        .task { await animateWaveformLoop() }
    }

    @MainActor
    private func animateWaveformLoop() async {
        while !Task.isCancelled {
            // idle pause
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            // "active" burst
            for _ in 0..<18 {
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.14, dampingFraction: 0.5)) {
                    for i in 0..<9 {
                        let base: CGFloat = 5
                        let amp: CGFloat = CGFloat.random(in: 14...30)
                        barHeights[i] = base + amp * abs(sin(Double(i) * 0.8 + phase))
                    }
                    phase += 0.55
                }
            }
            // decay
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                barHeights = Array(repeating: 4, count: 9)
            }
        }
    }
}

// ── Card 3: Smart code context ───────────────────────────────────────────────
private struct BentoCodeCard: View {
    private let accent = Color.zOrange
    private let tokens: [(String, Bool)] = [
        ("func", false), ("transcribe", true), ("(", false),
        ("audioURL", true), (":", false), ("URL", true), (")", false), ("{", false),
        ("let", false), ("result", true), ("=", false), ("await", false),
        ("whisper", true), (".", false), ("run", true), ("(", false), ("audioURL", true), (")", false),
    ]
    @State private var highlighted: Int = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BentoCellBg(accent: accent)

            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Contexte de code")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.zText)
                    Text("Reconnaît tes variables et fonctions en direct.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)

                // Code token display
                FlowLayout(spacing: 2) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { idx, tok in
                        let isHighlighted = tok.1 && highlighted == idx
                        Text(tok.0)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(
                                tok.1
                                    ? (isHighlighted ? .white : accent)
                                    : Color.zTextSub
                            )
                            .padding(.horizontal, isHighlighted ? 5 : 2)
                            .padding(.vertical, isHighlighted ? 2 : 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isHighlighted ? accent : accent.opacity(0))
                            )
                            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHighlighted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await cycleTokensLoop() }
    }

    @MainActor
    private func cycleTokensLoop() async {
        while !Task.isCancelled {
            let identifiers = tokens.enumerated().filter { $0.element.1 }.map { $0.offset }
            for idx in identifiers {
                guard !Task.isCancelled else { return }
                withAnimation { highlighted = idx }
                do {
                    try await Task.sleep(for: .milliseconds(520))
                } catch {
                    return
                }
            }
            withAnimation { highlighted = -1 }
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
        }
    }
}

// ── Card 4: 30 languages ─────────────────────────────────────────────────────
private struct BentoLangCard: View {
    private let accent = Color(hex: "E8433A")
    private let langs: [(String, String)] = [
        ("FR", "Français"), ("EN", "English"), ("ES", "Español"),
        ("DE", "Deutsch"), ("ZH", "中文"), ("JA", "日本語"),
        ("RU", "Русский"), ("PT", "Português"), ("IT", "Italiano"),
        ("AR", "العربية"), ("KO", "한국어"), ("NL", "Nederlands"),
    ]
    @State private var currentIdx: Int = 0
    @State private var slideOffset: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BentoCellBg(accent: accent)

            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "globe")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("30 langues")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.zText)
                    Text("Toutes les langues Whisper, précision maximale.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)

                // Language ticker
                HStack(spacing: 8) {
                    Text(langs[currentIdx].0)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                        .frame(width: 24)
                    Text(langs[currentIdx].1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.zText)
                    Spacer()
                }
                .offset(y: slideOffset)
                .opacity(opacity)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(accent.opacity(0.16), lineWidth: 1))
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Count badge
            Text("30")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(accent.opacity(0.10), in: Capsule())
                .padding(14)
        }
        .task { await cycleLangsLoop() }
    }

    @MainActor
    private func cycleLangsLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(1600))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                slideOffset = -8
                opacity = 0
            }

            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            currentIdx = (currentIdx + 1) % langs.count
            slideOffset = 8
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                slideOffset = 0
                opacity = 1
            }
        }
    }
}

// ── Card 5: Writing style ────────────────────────────────────────────────────
private struct BentoStyleCard: View {
    private let accent = Color.zBlue
    private let styles: [(String, String)] = [
        ("Formel",      "Bonjour, je vous informe que la réunion est confirmée."),
        ("Casual",      "Salut ! La réunion est bien confirmée."),
        ("Très casual", "yep réunion c'est bon 👍"),
    ]
    @State private var styleIdx: Int = 0
    @State private var textOpacity: Double = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BentoCellBg(accent: accent)

            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "textformat.size")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Style d'écriture")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.zText)
                    Text("Formel, Casual ou Très casual — adapté au contexte.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)

                // Style pills row
                HStack(spacing: 5) {
                    ForEach(Array(styles.enumerated()), id: \.offset) { i, s in
                        let active = styleIdx == i
                        Text(s.0)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundColor(active ? .white : Color.zTextSub)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(active ? accent : accent.opacity(0.07), in: Capsule())
                            .animation(.spring(response: 0.3), value: active)
                    }
                }

                // Sample text
                Text(styles[styleIdx].1)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.zTextSub)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(textOpacity)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await cycleStylesLoop() }
    }

    @MainActor
    private func cycleStylesLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(2200))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { textOpacity = 0 }

            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            styleIdx = (styleIdx + 1) % styles.count
            withAnimation(.easeOut(duration: 0.22)) { textOpacity = 1 }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Profile Setup (Demos slide)
// ─────────────────────────────────────────────────────────────────────────────

struct PFOnboardingProfile {
    let icon: String
    let color: Color
    let name: String
    let tagline: String
    let styleWork: WritingTone
    let stylePersonal: WritingTone
    let styleEmail: WritingTone
    // Snippet
    let snippetTrigger: String      // voice trigger shown to user
    let snippetExpansion: String    // what it expands to
    let snippetFieldLabel: String   // label for the editable field
    let snippetDefaultValue: String // default editable value
    let snippetUserDefaultsKey: String

    static let all: [PFOnboardingProfile] = [
        PFOnboardingProfile(
            icon: "chevron.left.forwardslash.chevron.right",
            color: Color.zOrange,
            name: t("Développeur", "Developer", "Desarrollador", "开发者", "デベロッパー", "Разработчик"),
            tagline: t("Code, CLI & docs", "Code, CLI & docs", "Código, CLI y docs", "代码与文档", "コード / CLI / 文書", "Код, CLI, документы"),
            styleWork: .casual,
            stylePersonal: .veryCasual,
            styleEmail: .casual,
            snippetTrigger: t("mon profil github", "my github profile", "mi perfil github", "我的 github", "GitHubプロフィール", "мой github"),
            snippetExpansion: t("Retrouvez mon profil : ", "Find my profile: ", "Mi perfil: ", "我的主页：", "プロフィール：", "Мой профиль: "),
            snippetFieldLabel: t("Ton URL GitHub / LinkedIn", "Your GitHub / LinkedIn URL", "Tu URL GitHub / LinkedIn", "你的 GitHub / LinkedIn", "GitHub / LinkedIn URL", "Ссылка GitHub / LinkedIn"),
            snippetDefaultValue: "https://github.com/",
            snippetUserDefaultsKey: AppState.snippetLinkedInURLKey
        ),
        PFOnboardingProfile(
            icon: "doc.text",
            color: Color.zBlue,
            name: t("Rédacteur", "Writer", "Redactor", "写作者", "ライター", "Редактор"),
            tagline: t("Articles, rapports & emails", "Articles, reports & email", "Artículos, informes y email", "文章与报告", "記事とレポート", "Статьи и письма"),
            styleWork: .formal,
            stylePersonal: .casual,
            styleEmail: .formal,
            snippetTrigger: t("ma signature", "my signature", "mi firma", "我的签名", "署名", "моя подпись"),
            snippetExpansion: t("Cordialement,\n", "Best regards,\n", "Atentamente,\n", "此致，\n", "よろしくお願いいたします。\n", "С уважением,\n"),
            snippetFieldLabel: t("Ton nom complet", "Your full name", "Tu nombre completo", "你的全名", "フルネーム", "Ваше полное имя"),
            snippetDefaultValue: "",
            snippetUserDefaultsKey: AppState.snippetContactEmailKey
        ),
        PFOnboardingProfile(
            icon: "person.2",
            color: Color.zPurple,
            name: t("Manager", "Manager", "Manager", "管理者", "マネージャー", "Менеджер"),
            tagline: t("Réunions, emails & reporting", "Meetings, email & reporting", "Reuniones, email y reporting", "会议与邮件", "会議とメール", "Встречи и отчёты"),
            styleWork: .formal,
            stylePersonal: .casual,
            styleEmail: .formal,
            snippetTrigger: t("mon email pro", "my work email", "mi email del trabajo", "我的工作邮箱", "仕事のメール", "рабочая почта"),
            snippetExpansion: "",
            snippetFieldLabel: t("Ton email professionnel", "Your work email", "Tu email profesional", "你的工作邮箱", "仕事のメールアドレス", "Рабочий email"),
            snippetDefaultValue: "",
            snippetUserDefaultsKey: AppState.snippetContactEmailKey
        ),
        PFOnboardingProfile(
            icon: "book",
            color: Color(hex: "E8433A"),
            name: t("Étudiant", "Student", "Estudiante", "学生", "学生", "Студент"),
            tagline: t("Notes, cours & recherche", "Notes, courses & research", "Notas, cursos e investigación", "笔记与课程", "ノートと授業", "Заметки и учёба"),
            styleWork: .casual,
            stylePersonal: .veryCasual,
            styleEmail: .casual,
            snippetTrigger: t("mon école", "my school", "mi escuela", "我的学校", "学校名", "мой университет"),
            snippetExpansion: "",
            snippetFieldLabel: t("Ton établissement", "Your school / university", "Tu centro educativo", "你的学校", "学校名", "Ваше учебное заведение"),
            snippetDefaultValue: "",
            snippetUserDefaultsKey: AppState.snippetLinkedInURLKey
        ),
    ]
}

// ── Profile card ─────────────────────────────────────────────────────────────
private struct ProfileCard: View {
    let profile: PFOnboardingProfile
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(profile.color.opacity(isSelected ? 0.18 : 0.11))
                        .frame(width: 44, height: 44)
                    Image(systemName: profile.icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(profile.color)
                }
                .padding(.bottom, 12)

                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.zText)
                    .padding(.bottom, 4)

                Text(profile.tagline)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.zTextSub)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Selected checkmark
                HStack {
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(profile.color)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(profile.color.opacity(isSelected ? 0.05 : isHovered ? 0.025 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected ? profile.color.opacity(0.55) : Color.black.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1
                        ))
                    .shadow(color: isSelected ? profile.color.opacity(0.12) : Color.black.opacity(0.04),
                            radius: isSelected ? 16 : 10, x: 0, y: 4)
            )
            .scaleEffect(isHovered && !isSelected ? 1.012 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: isSelected)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
    }
}

// ── Configuration preview panel ───────────────────────────────────────────────
private struct ProfileConfigPanel: View {
    let profile: PFOnboardingProfile
    @Binding var snippetValue: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Writing style summary
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(t("Styles configurés", "Writing styles set", "Estilos configurados", "已配置风格", "スタイル設定済み", "Стили настроены"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(profile.color)
                }

                VStack(spacing: 8) {
                    StyleRow(
                        context: t("Travail", "Work", "Trabajo", "工作", "仕事", "Работа"),
                        tone: profile.styleWork,
                        color: profile.color
                    )
                    StyleRow(
                        context: t("Personnel", "Personal", "Personal", "个人", "個人", "Личное"),
                        tone: profile.stylePersonal,
                        color: profile.color
                    )
                    StyleRow(
                        context: t("Email", "Email", "Email", "邮件", "メール", "Почта"),
                        tone: profile.styleEmail,
                        color: profile.color
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            )

            // Right: First snippet editor
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(t("Ton premier snippet", "Your first snippet", "Tu primer snippet", "首个 Snippet", "最初のスニペット", "Первый сниппет"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)
                } icon: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13))
                        .foregroundColor(profile.color)
                }

                // Trigger phrase (read-only)
                VStack(alignment: .leading, spacing: 5) {
                    Text(t("Phrase vocale", "Voice trigger", "Frase vocal", "语音触发词", "音声トリガー", "Голосовой триггер"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zTextDim)

                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                            .foregroundColor(profile.color)
                        Text("« \(profile.snippetTrigger) »")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.zText)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(profile.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(profile.color.opacity(0.18), lineWidth: 1))
                }

                // Editable expansion value
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.snippetFieldLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zTextDim)

                    TextField(
                        t("Valeur…", "Value…", "Valor…", "值…", "値…", "Значение…"),
                        text: $snippetValue
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Color.zText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .cornerRadius(9)
                    .onChange(of: snippetValue) { _, val in
                        UserDefaults.standard.set(val, forKey: profile.snippetUserDefaultsKey)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            )
        }
    }
}

// ── Style row helper ──────────────────────────────────────────────────────────
private struct StyleRow: View {
    let context: String
    let tone: WritingTone
    let color: Color

    var body: some View {
        HStack {
            Text(context)
                .font(.system(size: 12))
                .foregroundColor(Color.zTextSub)
                .frame(width: 72, alignment: .leading)
            Spacer()
            Text(tone.displayName(for: AppState.shared.uiDisplayLanguage.rawValue))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.09), in: Capsule())
        }
    }
}

// ── Custom profile panel ──────────────────────────────────────────────────────
private struct CustomProfilePanel: View {
    @Binding var styleWork: WritingTone
    @Binding var stylePersonal: WritingTone
    @Binding var styleEmail: WritingTone
    @Binding var snippetTrigger: String
    @Binding var snippetExpansion: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Style pickers
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(t("Choisis tes styles", "Choose your styles", "Elige tus estilos", "选择你的风格", "スタイルを選ぶ", "Выбери стили"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)
                } icon: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 13))
                        .foregroundColor(Color.zBlue)
                }

                TonePicker(
                    label: t("Travail", "Work", "Trabajo", "工作", "仕事", "Работа"),
                    selection: $styleWork
                )
                TonePicker(
                    label: t("Personnel", "Personal", "Personal", "个人", "個人", "Личное"),
                    selection: $stylePersonal
                )
                TonePicker(
                    label: t("Email", "Email", "Email", "邮件", "メール", "Почта"),
                    selection: $styleEmail
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            )
            .onChange(of: styleWork) { _, v in AppState.shared.styleWork = v }
            .onChange(of: stylePersonal) { _, v in AppState.shared.stylePersonal = v }
            .onChange(of: styleEmail) { _, v in AppState.shared.styleEmail = v }

            // Right: Free-form snippet
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(t("Crée ton snippet", "Create your snippet", "Crea tu snippet", "创建你的 Snippet", "スニペットを作る", "Создай сниппет"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)
                } icon: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.zOrange)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(t("Phrase vocale déclencheur", "Voice trigger phrase", "Frase vocal disparadora", "语音触发词", "音声トリガー", "Голосовой триггер"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zTextDim)
                    TextField(
                        t("ex: mon email pro", "e.g.: my work email", "ej: mi correo pro", "例：我的工作邮箱", "例：仕事のメール", "напр.: моя рабочая почта"),
                        text: $snippetTrigger
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                    .cornerRadius(9)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(t("Texte inséré", "Inserted text", "Texto insertado", "插入文本", "挿入テキスト", "Вставляемый текст"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zTextDim)
                    TextField(
                        t("ex: contact@mon.email", "e.g.: contact@my.email", "ej: contact@mi.email", "例：contact@email.com", "例：contact@email.com", "напр.: contact@email.com"),
                        text: $snippetExpansion
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                    .cornerRadius(9)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            )
        }
    }
}

// ── Tone picker row ───────────────────────────────────────────────────────────
private struct TonePicker: View {
    let label: String
    @Binding var selection: WritingTone

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.zTextSub)
                .frame(width: 72, alignment: .leading)
            Spacer()
            HStack(spacing: 5) {
                ForEach(WritingTone.allCases) { tone in
                    let active = selection == tone
                    Button {
                        withAnimation(.spring(response: 0.25)) { selection = tone }
                    } label: {
                        Text(tone.displayName(for: AppState.shared.uiDisplayLanguage.rawValue))
                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                            .foregroundColor(active ? .white : Color.zTextSub)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(active ? Color.zBlue : Color.zBlue.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    PreflightView(onReady: {})
        .frame(width: 860, height: 600)
}
