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
    case welcome     = 0
    case speed       = 1
    case features    = 2
    case demos       = 3
    case language    = 4
    case model       = 5
    case permissions = 6
    case shortcut    = 7
    case ready       = 8

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
    @State private var waveOffset: CGFloat = 0
    @State private var readyScale: CGFloat = 0.6
    @State private var readyOpacity: Double = 0

    // Speed slide states
    @State private var typingWPM: Int = 0
    @State private var dictatingWPM: Int = 0
    @State private var showFasterBadge: Bool = false
    @State private var typewriterText: String = ""
    @State private var showDictatedText: Bool = false
    @State private var typewriterPhase: Int = 0 // 0=idle, 1=typing, 2=done typing, 3=dictated

    // Demos slide states
    @State private var selectedDemo: Int = 0
    @State private var snippetExpanded: Bool = false
    @State private var dictShowCorrected: Bool = false
    @State private var styleIndex: Int = 0

    @State private var permissionPollTask: Task<Void, Never>? = nil
    @State private var demoToggleTask: Task<Void, Never>? = nil
    @State private var styleCycleTask: Task<Void, Never>? = nil

    private var modelStatus: ModelStatus    { AppState.shared.modelStatus }
    private var downloadStats: DownloadStats { AppState.shared.downloadStats }
    private var lang: String                 { AppState.shared.selectedLanguage.id }

    var body: some View {
        ZStack {
            // Background
            Color.zBg.ignoresSafeArea()
            ambientBackground

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
            startBackgroundAnimations()
            startModelInBackground()
        }
        .onChange(of: modelStatus) { _, newStatus in
            if newStatus.isReady && currentSlide == .model {
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    advance()
                }
            }
        }
        .colorScheme(.light)
        .onChange(of: currentSlide) { _, newSlide in
            permissionPollTask?.cancel()
            demoToggleTask?.cancel()
            styleCycleTask?.cancel()

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
                Task { await startLoadModelIfNeeded() }
            }
            if newSlide == .model && modelStatus.isReady {
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    advance()
                }
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
            if newSlide == .demos {
                startDemoAnimations()
            }
        }
        .onDisappear {
            permissionPollTask?.cancel()
            demoToggleTask?.cancel()
            styleCycleTask?.cancel()
        }
    }

    // MARK: - Ambient Background

    private var ambientBackground: some View {
        ZStack {
            RadialGradient(
                colors: [Color.zAccent.opacity(0.07), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 480
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.zBlue.opacity(0.04), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 360
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
            // Back button
            if currentSlide.rawValue > 0 && currentSlide != .model && currentSlide != .ready {
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
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
            glowPulse = 1.35
        }
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            waveOffset = 1.0
        }
    }

    private func startSpeedAnimations() {
        typingWPM = 0
        dictatingWPM = 0
        showFasterBadge = false
        typewriterText = ""
        showDictatedText = false
        typewriterPhase = 0

        // Animate typing WPM counter to 45 over ~2s
        Task { @MainActor in
            let steps = 45
            let stepDelay: UInt64 = 2_000_000_000 / UInt64(steps)
            for i in 1...steps {
                guard currentSlide == .speed else { return }
                withAnimation(.easeOut(duration: 0.04)) { typingWPM = i }
                try? await Task.sleep(nanoseconds: stepDelay)
            }

            // Then animate dictating WPM counter to 130 over ~1.5s
            let dSteps = 130
            let dStepDelay: UInt64 = 1_500_000_000 / UInt64(dSteps)
            for i in 1...dSteps {
                guard currentSlide == .speed else { return }
                withAnimation(.easeOut(duration: 0.04)) { dictatingWPM = i }
                try? await Task.sleep(nanoseconds: dStepDelay)
            }

            // Show 3x faster badge
            try? await Task.sleep(for: .milliseconds(300))
            guard currentSlide == .speed else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showFasterBadge = true
            }

            // Start typewriter animation
            try? await Task.sleep(for: .milliseconds(600))
            guard currentSlide == .speed else { return }
            typewriterPhase = 1
            let sampleSentence = t(
                "Bonjour, je voulais vous informer de la mise à jour.",
                "Hello, I wanted to inform you about the update.",
                "Hola, quería informarle sobre la actualización.",
                "你好，我想告诉你关于更新的事。",
                "こんにちは、アップデートについてお知らせしたいです。",
                "Привет, хотел сообщить об обновлении."
            )
            for char in sampleSentence {
                guard currentSlide == .speed, typewriterPhase == 1 else { return }
                typewriterText += String(char)
                try? await Task.sleep(for: .milliseconds(50))
            }
            typewriterPhase = 2

            // Brief pause then show dictated version
            try? await Task.sleep(for: .milliseconds(800))
            guard currentSlide == .speed else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                typewriterPhase = 3
                showDictatedText = true
            }
        }
    }

    private func startDemoAnimations() {
        snippetExpanded = false
        dictShowCorrected = false
        styleIndex = 0

        // Auto-trigger snippet expansion after delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard currentSlide == .demos else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                snippetExpanded = true
            }
        }

        // Dictionary auto-toggle
        demoToggleTask = Task { @MainActor in
            while !Task.isCancelled, currentSlide == .demos {
                try? await Task.sleep(for: .seconds(2))
                guard currentSlide == .demos else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    dictShowCorrected.toggle()
                }
            }
        }

        // Style auto-cycle
        styleCycleTask = Task { @MainActor in
            while !Task.isCancelled, currentSlide == .demos {
                try? await Task.sleep(for: .seconds(2))
                guard currentSlide == .demos else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    styleIndex = (styleIndex + 1) % 3
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 0: Welcome
    // ═══════════════════════════════════════════════════════════

    private var welcomeSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon with ambient glow
            ZStack {
                Circle()
                    .fill(Color.zAccent.opacity(0.14))
                    .frame(width: 130, height: 130)
                    .scaleEffect(glowPulse)
                    .blur(radius: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 92, height: 92)
                    .overlay(Circle().stroke(Color.zBorder, lineWidth: 1))
                    .shadow(color: Color.zAccent.opacity(0.22), radius: 22, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(Color.zAccent)
                    .symbolEffect(.pulse.byLayer, isActive: true)
            }
            .padding(.bottom, 30)

            // App name
            Text("Zphyr")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "1A1A1A"), Color(hex: "3D3D4A")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.bottom, 10)

            // Tagline
            Text(t(
                "Ta voix. Ton Mac. Zéro cloud.",
                "Your voice. Your Mac. No cloud.",
                "Tu voz. Tu Mac. Sin nube.",
                "你的声音。你的 Mac。零云端。",
                "あなたの声。あなたの Mac。クラウドなし。",
                "Твой голос. Твой Mac. Без облака."
            ))
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(Color.zTextSub)
            .padding(.bottom, 36)

            // Feature pills
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

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 44)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 1: Speed
    // ═══════════════════════════════════════════════════════════

    private var speedSlide: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Heading
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

                    Text(t(
                        "La dictée vocale est le moyen le plus rapide de produire du texte.",
                        "Voice dictation is the fastest way to produce text.",
                        "El dictado por voz es la forma más rápida de producir texto.",
                        "语音听写是生成文本最快的方式。",
                        "音声入力はテキスト生成の最速手段です。",
                        "Голосовой ввод — самый быстрый способ создания текста."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(Color.zTextSub)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
                .padding(.bottom, 24)

                // Typing vs Dictating comparison
                HStack(spacing: 0) {
                    // Left column — Typing
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Color.zTextSub)

                        Text(t("Taper", "Typing", "Escribir", "打字", "タイピング", "Набор"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.zTextSub)

                        Text("\(typingWPM)")
                            .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.zTextSub)
                            .contentTransition(.numericText())

                        Text("WPM")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.zTextDim)
                            .tracking(1.5)

                        Text(t("~6 secondes pour une phrase",
                               "~6 seconds per sentence",
                               "~6 segundos por frase",
                               "每句约 6 秒",
                               "1文あたり約6秒",
                               "~6 секунд на фразу"))
                            .font(.system(size: 11))
                            .foregroundColor(Color.zTextDim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    // Center divider
                    VStack {
                        Text("VS")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(Color.zTextDim)
                    }
                    .frame(width: 44)

                    // Right column — Dictating
                    VStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Color.zAccent)

                        Text(t("Dicter", "Dictating", "Dictar", "听写", "ディクテーション", "Диктовка"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.zAccent)

                        Text("\(dictatingWPM)")
                            .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.zAccent)
                            .contentTransition(.numericText())

                        Text("WPM")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.zAccent.opacity(0.6))
                            .tracking(1.5)

                        Text(t("~2 secondes pour une phrase",
                               "~2 seconds per sentence",
                               "~2 segundos por frase",
                               "每句约 2 秒",
                               "1文あたり約2秒",
                               "~2 секунд на фразу"))
                            .font(.system(size: 11))
                            .foregroundColor(Color.zAccent.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.zSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.zBorder, lineWidth: 1))
                )
                .padding(.bottom, 16)

                // 3x faster badge
                if showFasterBadge {
                    Text(t("3× plus rapide", "3× faster", "3× más rápido", "快 3 倍", "3 倍速い", "В 3 раза быстрее"))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.zAccent)
                        .clipShape(Capsule())
                        .scaleEffect(showFasterBadge ? 1.0 : 0.5)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 16)
                }

                // Typewriter demo
                VStack(spacing: 10) {
                    if typewriterPhase >= 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.zTextDim)
                                Text(t("Clavier", "Keyboard", "Teclado", "键盘", "キーボード", "Клавиатура"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.zTextDim)
                            }
                            Text(typewriterText)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color.zTextSub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 20)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.zSurface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.zBorder, lineWidth: 1))
                        )
                    }

                    if showDictatedText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.zAccent)
                                Text(t("Voix", "Voice", "Voz", "语音", "音声", "Голос"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.zAccent)
                                Spacer()
                                Text(t("Instantané", "Instant", "Instantáneo", "即时", "即座", "Мгновенно"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.zAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.zAccent.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text(typewriterText)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color.zAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.zAccent.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.zAccent.opacity(0.3), lineWidth: 1))
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 14)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 2: Features
    // ═══════════════════════════════════════════════════════════

    private var featuresSlide: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // Heading
                VStack(spacing: 6) {
                    Text(t(
                        "Ce que fait Zphyr",
                        "What Zphyr does",
                        "Qué hace Zphyr",
                        "Zphyr 的功能",
                        "Zphyr でできること",
                        "Возможности Zphyr"
                    ))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color.zText)

                    Text(t(
                        "Cinq fonctions clés, conçues pour les développeurs Mac.",
                        "Five key features, built for Mac developers.",
                        "Cinco funciones clave, diseñadas para desarrolladores Mac.",
                        "五大核心功能，专为 Mac 开发者设计。",
                        "Mac 開発者向けに設計された 5 つの主要機能。",
                        "Пять ключевых функций для Mac-разработчиков."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(Color.zTextSub)
                    .multilineTextAlignment(.center)
                }
                .padding(.bottom, 10)

                // Feature cards
                PFFeatureCard(
                    icon: "lock.shield.fill",
                    color: Color.zAccent,
                    title: t("100% local, zéro cloud",
                             "100% local, zero cloud",
                             "100% local, cero nube",
                             "100% 本地，零云端",
                             "100% ローカル・クラウド不要",
                             "100% локально, без облака"),
                    description: t(
                        "Whisper s'exécute sur Apple Silicon Neural Engine. Aucune donnée ne quitte jamais ton Mac.",
                        "Whisper runs on Apple Silicon Neural Engine. No data ever leaves your Mac.",
                        "Whisper se ejecuta en Apple Silicon Neural Engine. Ningún dato abandona tu Mac.",
                        "Whisper 在 Apple Silicon Neural Engine 本地运行，数据不会离开你的 Mac。",
                        "Whisper は Apple Silicon Neural Engine で動作。データは Mac から出ません。",
                        "Whisper работает на Apple Silicon Neural Engine. Данные не покидают Mac."
                    )
                )

                PFFeatureCard(
                    icon: "option",
                    color: Color.zPurple,
                    title: "Hold-to-talk · ⌥ droite",
                    description: t(
                        "Maintiens la touche ⌥ Option droite pour dicter, relâche pour transcrire et insérer automatiquement.",
                        "Hold right Option ⌥ to dictate, release to transcribe and auto-insert.",
                        "Mantén ⌥ Option derecha para dictar, suelta para transcribir e insertar.",
                        "按住右侧 ⌥ Option 听写，松开即自动转写插入。",
                        "右 ⌥ Option を押して話し、離すと自動転写・挿入。",
                        "Удержи правую ⌥ Option — диктуй, отпусти — текст вставится сам."
                    )
                )

                PFFeatureCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: Color.zOrange,
                    title: t("Contexte code intelligent",
                             "Smart code context",
                             "Contexto de código inteligente",
                             "智能代码上下文",
                             "スマートコードコンテキスト",
                             "Умный контекст кода"),
                    description: t(
                        "Zphyr lit les tokens de ton fichier ouvert pour reconnaître précisément les noms de variables et fonctions.",
                        "Zphyr reads tokens from your open file to accurately recognize variable and function names.",
                        "Zphyr lee los tokens del archivo abierto para reconocer nombres de variables y funciones.",
                        "Zphyr 读取编辑器中打开文件的 token，精准识别变量和函数名。",
                        "Zphyr が開いているファイルのトークンを読み取り、変数・関数名を正確に認識。",
                        "Zphyr читает токены из открытого файла для точного распознавания переменных."
                    )
                )

                PFFeatureCard(
                    icon: "globe",
                    color: Color(hex: "FF3B30"),
                    title: t("99 langues", "99 languages", "99 idiomas", "99 种语言", "99言語", "99 языков"),
                    description: t(
                        "Précision maximale pour FR, EN, ES, DE, ZH, JA, RU. Toutes les langues Whisper supportées.",
                        "Best accuracy for FR, EN, ES, DE, ZH, JA, RU. All Whisper languages supported.",
                        "Mejor precisión para FR, EN, ES, DE, ZH, JA, RU. Todos los idiomas de Whisper soportados.",
                        "FR/EN/ES/DE/ZH/JA/RU 精度最佳，所有 Whisper 语言均支持。",
                        "FR/EN/ES/DE/ZH/JA/RU で高精度。全 Whisper 言語に対応。",
                        "Лучшая точность для FR, EN, ES, DE, ZH, JA, RU. Все языки Whisper поддерживаются."
                    )
                )

                PFFeatureCard(
                    icon: "textformat.size",
                    color: Color(hex: "FF6B35"),
                    title: t("Style d'écriture", "Writing style", "Estilo de escritura", "写作风格", "文体スタイル", "Стиль письма"),
                    description: t(
                        "Formel, Casual ou Très casual : Zphyr adapte automatiquement la ponctuation et les majuscules selon le contexte.",
                        "Formal, Casual, or Very casual: Zphyr auto-adapts punctuation and capitalization per context.",
                        "Formal, Casual o Muy casual: Zphyr adapta puntuación y mayúsculas por contexto.",
                        "正式、日常或非常随意：Zphyr 自动按场景调整标点和大小写。",
                        "フォーマル/カジュアル/とてもカジュアル：文脈に応じて自動調整。",
                        "Формальный/Повседневный/Очень неформальный: автоматическая адаптация."
                    )
                )
            }
            .padding(.horizontal, 44)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 3: Demos
    // ═══════════════════════════════════════════════════════════

    private var demosSlide: some View {
        VStack(spacing: 0) {
            // Heading
            VStack(spacing: 6) {
                Text(t(
                    "Fonctions en action",
                    "Features in action",
                    "Funciones en acción",
                    "功能演示",
                    "機能デモ",
                    "Функции в действии"
                ))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)
            }
            .padding(.top, 4)
            .padding(.bottom, 16)

            // Segmented control
            HStack(spacing: 0) {
                let segments = [
                    t("Snippets", "Snippets", "Snippets", "片段", "スニペット", "Сниппеты"),
                    t("Dictionnaire", "Dictionary", "Diccionario", "词典", "辞書", "Словарь"),
                    t("Styles", "Styles", "Estilos", "风格", "スタイル", "Стили")
                ]
                ForEach(0..<3, id: \.self) { idx in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedDemo = idx
                        }
                    } label: {
                        Text(segments[idx])
                            .font(.system(size: 12, weight: selectedDemo == idx ? .semibold : .regular))
                            .foregroundColor(selectedDemo == idx ? .white : Color.zTextSub)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedDemo == idx
                                    ? Color.zAccent
                                    : Color.clear
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.zSurface2)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.zBorder, lineWidth: 1))
            .padding(.horizontal, 44)
            .padding(.bottom, 18)

            // Demo content
            Group {
                switch selectedDemo {
                case 0: snippetsDemoContent
                case 1: dictionaryDemoContent
                default: stylesDemoContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
        }
    }

    private var snippetsDemoContent: some View {
        VStack(spacing: 14) {
            // Trigger phrase bubble
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.zAccent)
                Text(t(
                    "\"ajoute-nous sur linkedin\"",
                    "\"add us on linkedin\"",
                    "\"agréganos en linkedin\"",
                    "\"在 linkedin 上添加我们\"",
                    "\"linkedin に追加して\"",
                    "\"добавь нас в linkedin\""
                ))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.zText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.zSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.zBorder, lineWidth: 1))
            )

            // Arrow
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.zAccent)

            // Expanded snippet
            if snippetExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundColor(Color.zBlue)
                    Text("Retrouvez-nous sur https://www.linkedin.com/company/zphyr")
                        .font(.system(size: 13))
                        .foregroundColor(Color.zText)
                        .lineLimit(2)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.zBlue.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.zBlue.opacity(0.3), lineWidth: 1))
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 8)

            // Caption
            Text(t(
                "Insérez des blocs de texte prédéfinis avec une phrase vocale",
                "Insert predefined text blocks with a voice phrase",
                "Inserta bloques de texto predefinidos con una frase de voz",
                "用语音短语插入预定义文本块",
                "音声フレーズで事前定義のテキストを挿入",
                "Вставляйте заготовленные текстовые блоки голосовой фразой"
            ))
            .font(.system(size: 12))
            .foregroundColor(Color.zTextSub)
            .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private var dictionaryDemoContent: some View {
        VStack(spacing: 14) {
            // Wrong/Correct toggle
            if !dictShowCorrected {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.zRed)
                    Text(t("« zifère »", "\"zifare\"", "\"zifere\"", "\"zifère\"", "\"zifère\"", "\"зифер\""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.zText)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.zRed.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.zRed.opacity(0.3), lineWidth: 1))
                )
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.zGreen)
                    Text("Zphyr")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.zText)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.zGreen.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.zGreen.opacity(0.3), lineWidth: 1))
                )
                .transition(.scale.combined(with: .opacity))
            }

            // Arrow
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.zTextDim)

            Spacer(minLength: 8)

            // Caption
            Text(t(
                "Zphyr apprend tes corrections et les mémorise",
                "Zphyr learns your corrections and remembers them",
                "Zphyr aprende tus correcciones y las memoriza",
                "Zphyr 学习你的修正并记住",
                "Zphyr は修正を学習して記憶します",
                "Zphyr запоминает ваши исправления"
            ))
            .font(.system(size: 12))
            .foregroundColor(Color.zTextSub)
            .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private var stylesDemoContent: some View {
        VStack(spacing: 14) {
            // Source sentence
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.zAccent)
                    Text(t("Phrase dictée", "Dictated", "Dictada", "听写原文", "音声入力", "Продиктовано"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.zTextDim)
                }
                Text(t(
                    "bonjour je voulais vous informer de la mise à jour",
                    "hello i wanted to inform you about the update",
                    "hola quería informarle de la actualización",
                    "你好我想告诉你关于更新的事",
                    "こんにちはアップデートについてお知らせしたいです",
                    "привет хотел сообщить об обновлении"
                ))
                .font(.system(size: 13))
                .foregroundColor(Color.zTextSub)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.zSurface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.zBorder, lineWidth: 1))
            )

            // Style cards
            let styleNames = [
                t("Formel", "Formal", "Formal", "正式", "フォーマル", "Формальный"),
                t("Casual", "Casual", "Casual", "日常", "カジュアル", "Повседневный"),
                t("Très casual", "Very casual", "Muy casual", "非常随意", "とてもカジュアル", "Очень неформальный")
            ]
            let styleTexts = [
                t("Bonjour, je souhaitais vous informer de la mise à jour.",
                  "Hello, I would like to inform you about the update.",
                  "Buenos días, le informo sobre la actualización.",
                  "您好，我想通知您有关更新的信息。",
                  "お世話になっております。アップデートについてご連絡いたします。",
                  "Здравствуйте, хотел бы сообщить вам об обновлении."),
                t("Salut, je voulais te dire que y'a une mise à jour.",
                  "Hey, wanted to let you know there's an update.",
                  "Oye, quería decirte que hay una actualización.",
                  "嗨，想告诉你有个更新。",
                  "やあ、アップデートがあるって伝えたくて。",
                  "Привет, хотел сказать, что есть обновление."),
                t("salut je voulais te dire que y a une maj",
                  "hey just wanted to say theres an update",
                  "oye quería decirte que hay update",
                  "嗨 想说下有个更新",
                  "ねえ アプデあるよ",
                  "прив хотел сказать есть апдейт")
            ]
            let styleColors: [Color] = [.zBlue, .zOrange, .zPurple]

            ForEach(0..<3, id: \.self) { idx in
                HStack(spacing: 10) {
                    Circle()
                        .fill(styleColors[idx].opacity(idx == styleIndex ? 1.0 : 0.3))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(styleNames[idx])
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(idx == styleIndex ? styleColors[idx] : Color.zTextDim)
                        Text(styleTexts[idx])
                            .font(.system(size: 12))
                            .foregroundColor(idx == styleIndex ? Color.zText : Color.zTextDim)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(idx == styleIndex ? styleColors[idx].opacity(0.08) : Color.zSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(idx == styleIndex ? styleColors[idx].opacity(0.3) : Color.zBorder, lineWidth: 1)
                        )
                )
                .scaleEffect(idx == styleIndex ? 1.02 : 1.0)
                .opacity(idx == styleIndex ? 1.0 : 0.6)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: styleIndex)
            }

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 4: Language
    // ═══════════════════════════════════════════════════════════

    private var languageSlide: some View {
        VStack(spacing: 0) {
            // UI Language picker section
            VStack(spacing: 10) {
                Text(t(
                    "Langue de l'interface",
                    "Interface language",
                    "Idioma de la interfaz",
                    "界面语言",
                    "インターフェース言語",
                    "Язык интерфейса"
                ))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.zText)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    PFUILanguageButton(
                        flag: "\u{1F1EB}\u{1F1F7}", label: "Français",
                        isSelected: AppState.shared.uiDisplayLanguage == .fr
                    ) { AppState.shared.uiDisplayLanguage = .fr }

                    PFUILanguageButton(
                        flag: "\u{1F1FA}\u{1F1F8}", label: "English",
                        isSelected: AppState.shared.uiDisplayLanguage == .en
                    ) { AppState.shared.uiDisplayLanguage = .en }

                    PFUILanguageButton(
                        flag: "\u{1F1EA}\u{1F1F8}", label: "Español",
                        isSelected: AppState.shared.uiDisplayLanguage == .es
                    ) { AppState.shared.uiDisplayLanguage = .es }

                    PFUILanguageButton(
                        flag: "\u{1F1E8}\u{1F1F3}", label: "中文",
                        isSelected: AppState.shared.uiDisplayLanguage == .zh
                    ) { AppState.shared.uiDisplayLanguage = .zh }

                    PFUILanguageButton(
                        flag: "\u{1F1EF}\u{1F1F5}", label: "日本語",
                        isSelected: AppState.shared.uiDisplayLanguage == .ja
                    ) { AppState.shared.uiDisplayLanguage = .ja }

                    PFUILanguageButton(
                        flag: "\u{1F1F7}\u{1F1FA}", label: "Русский",
                        isSelected: AppState.shared.uiDisplayLanguage == .ru
                    ) { AppState.shared.uiDisplayLanguage = .ru }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 4)
            .padding(.bottom, 16)

            // Divider
            Rectangle()
                .fill(Color.zBorder)
                .frame(height: 1)
                .padding(.horizontal, 44)
                .padding(.bottom, 12)

            // Dictation language section
            VStack(spacing: 6) {
                Text(t(
                    "Langue de dictée",
                    "Dictation language",
                    "Idioma de dictado",
                    "听写语言",
                    "音声入力言語",
                    "Язык диктовки"
                ))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.zText)

                Text(t(
                    "Whisper reconnaîtra ta langue principale de dictée.",
                    "Whisper will recognize your primary dictation language.",
                    "Whisper reconocerá tu idioma de dictado principal.",
                    "Whisper 将识别你的主要听写语言。",
                    "Whisper が音声入力の主要言語を認識します。",
                    "Whisper определит основной язык для диктовки."
                ))
                .font(.system(size: 14))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(WhisperLanguage.all, id: \.id) { language in
                        PFLanguageCell(
                            language: language,
                            isSelected: AppState.shared.selectedLanguage.id == language.id
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                AppState.shared.selectedLanguage = language
                            }
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 14)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - SLIDE 5: Model Download
    // ═══════════════════════════════════════════════════════════

    private var modelSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            // Circular progress ring
            ZStack {
                // Glow
                Circle()
                    .fill(Color.zAccent.opacity(0.1))
                    .frame(width: 172, height: 172)
                    .blur(radius: 18)

                // Track
                Circle()
                    .stroke(Color(hex: "E5E5E0"), lineWidth: 9)
                    .frame(width: 144, height: 144)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(modelStatus.progress))
                    .stroke(
                        LinearGradient(
                            colors: [Color.zAccent, Color.zBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: 144, height: 144)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: modelStatus.progress)

                // Center content
                Group {
                    if modelStatus.isReady {
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.zAccent)
                            .transition(.scale.combined(with: .opacity))
                    } else if case .failed = modelStatus {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.zRed)
                    } else if case .loading = modelStatus {
                        VStack(spacing: 2) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color.zAccent)
                                .symbolEffect(.pulse, isActive: true)
                            Text("ANE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.zTextDim)
                                .tracking(1)
                        }
                    } else {
                        Text("\(Int(modelStatus.progress * 100))%")
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.zText)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.28), value: modelStatus.progress)
                    }
                }
            }
            .padding(.bottom, 26)

            // Status title
            Text(modelTitleText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color.zText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Status subtitle
            Text(modelSubtitleText)
                .font(.system(size: 14))
                .foregroundColor(Color.zTextSub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 60)
                .padding(.bottom, 20)

            // Download stats
            if !modelStatus.isReady, modelStatus.progress > 0 {
                HStack(spacing: 12) {
                    if downloadStats.bytesReceived > 0 {
                        PFStatChip(icon: "externaldrive", text: downloadStats.formattedReceived)
                    }
                    if !downloadStats.formattedSpeed.isEmpty {
                        PFStatChip(icon: "arrow.down", text: downloadStats.formattedSpeed, color: Color.zAccent)
                    }
                    if !downloadStats.eta.isEmpty {
                        PFStatChip(icon: "clock", text: downloadStats.eta)
                    }
                }
                .padding(.bottom, 18)
            }

            // Model info chips
            HStack(spacing: 8) {
                PFInfoChip(icon: "cpu", text: "Whisper large-v3-turbo")
                PFInfoChip(icon: "memorychip", text: "CoreML · ANE")
                PFInfoChip(
                    icon: "arrow.clockwise",
                    text: t("1 seul téléchargement", "One-time", "Una vez", "仅一次", "一度だけ", "Один раз")
                )
            }

            // Retry on failure
            if case .failed = modelStatus {
                Button {
                    Task { await DictationEngine.shared.loadModel() }
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
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var modelTitleText: String {
        switch modelStatus {
        case .notDownloaded:
            return t("Téléchargement du moteur IA", "Downloading AI engine", "Descargando motor IA", "下载 AI 引擎", "AI エンジンをダウンロード", "Загрузка AI-движка")
        case .downloading:
            return t("Téléchargement en cours…", "Downloading…", "Descargando…", "下载中…", "ダウンロード中…", "Загрузка…")
        case .loading:
            return t("Chargement dans Neural Engine", "Loading into Neural Engine", "Cargando en Neural Engine", "加载到 Neural Engine", "Neural Engine へ読み込み中", "Загрузка в Neural Engine")
        case .ready:
            return t("Moteur prêt !", "Engine ready!", "¡Motor listo!", "引擎就绪！", "エンジン準備完了！", "Движок готов!")
        case .failed:
            return t("Échec du téléchargement", "Download failed", "Descarga fallida", "下载失败", "ダウンロード失敗", "Ошибка загрузки")
        }
    }

    private var modelSubtitleText: String {
        switch modelStatus {
        case .notDownloaded, .downloading:
            return t(
                "Whisper s'installe une seule fois (632 MB). Il s'exécute ensuite 100% en local.",
                "Whisper installs once (632 MB). It then runs 100% locally.",
                "Whisper se instala una sola vez (632 MB). Funciona 100% localmente.",
                "Whisper 仅需安装一次（632 MB），之后 100% 本地运行。",
                "Whisper は一度だけインストール（632 MB）。以後 100% ローカルで動作。",
                "Whisper устанавливается один раз (632 МБ). Далее работает 100% локально."
            )
        case .loading:
            return t(
                "Chargement en mémoire Apple Silicon Neural Engine…",
                "Loading into Apple Silicon Neural Engine memory…",
                "Cargando en memoria del Apple Silicon Neural Engine…",
                "正在加载到 Apple Silicon Neural Engine 内存…",
                "Apple Silicon Neural Engine のメモリへ読み込み中…",
                "Загрузка в память Apple Silicon Neural Engine…"
            )
        case .ready:
            return t(
                "Tout est prêt. Passage à la suite dans un instant…",
                "All ready. Moving on in a moment…",
                "Todo listo. Continuando en un momento…",
                "一切就绪，即将继续…",
                "準備完了。まもなく次へ進みます…",
                "Всё готово. Продолжаем…"
            )
        case .failed(let msg):
            return msg
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
    // MARK: - SLIDE 7: Shortcut
    // ═══════════════════════════════════════════════════════════

    private var shortcutSlide: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 10)

                VStack(spacing: 6) {
                    Text(t(
                        "Ta touche magique",
                        "Your magic key",
                        "Tu tecla mágica",
                        "你的魔法键",
                        "マジックキー",
                        "Твоя волшебная клавиша"
                    ))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color.zText)

                    Text(t(
                        "Un seul geste pour dicter n'importe où sur ton Mac.",
                        "One gesture to dictate anywhere on your Mac.",
                        "Un solo gesto para dictar en cualquier parte de tu Mac.",
                        "一个手势，在 Mac 任意位置听写。",
                        "Mac 上のどこでも一操作で音声入力。",
                        "Один жест — диктуй где угодно на Mac."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(Color.zTextSub)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 28)

                // Key + flow diagram
                HStack(spacing: 28) {
                    // The selected trigger key
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.zSurface2)
                                .frame(width: 88, height: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.zAccent.opacity(0.55), lineWidth: 1.5)
                                )
                                .shadow(color: Color.zAccent.opacity(0.22), radius: 16, x: 0, y: 6)

                            VStack(spacing: 2) {
                                Text(ShortcutManager.shared.selectedTriggerKey.symbol)
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(Color.zAccent)
                                Text(ShortcutManager.shared.selectedTriggerKey.shortLabel.replacingOccurrences(of: ShortcutManager.shared.selectedTriggerKey.symbol + " ", with: ""))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.zTextDim)
                                    .tracking(1.5)
                            }
                        }

                        Text(ShortcutManager.shared.selectedTriggerKey.displayName(for: lang))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.zTextSub)
                    }

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.zTextDim)

                    // 3-step flow
                    VStack(alignment: .leading, spacing: 16) {
                        PFShortcutStep(
                            icon: "hand.point.up.fill",
                            color: Color.zPurple,
                            text: t("Maintiens", "Hold", "Mantén", "按住", "押す", "Удержи") + " " + ShortcutManager.shared.selectedTriggerKey.symbol
                        )
                        PFShortcutStep(
                            icon: "mic.fill",
                            color: Color.zRed,
                            text: t("Parle", "Speak", "Habla", "说话", "話す", "Говори")
                        )
                        PFShortcutStep(
                            icon: "checkmark.circle.fill",
                            color: Color.zAccent,
                            text: t(
                                "Relâche → texte inséré",
                                "Release → text inserted",
                                "Suelta → texto insertado",
                                "松开 → 文字插入",
                                "離す → テキスト挿入",
                                "Отпусти → текст вставится"
                            )
                        )
                    }
                }
                .padding(.bottom, 20)

                // Trigger key picker
                VStack(spacing: 10) {
                    Text(t("Changer de touche", "Change key", "Cambiar tecla", "更改按键", "キーを変更", "Сменить клавишу"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(TriggerKey.allCases) { key in
                            PFTriggerKeyButton(
                                key: key,
                                isSelected: ShortcutManager.shared.selectedTriggerKey == key,
                                lang: lang
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    ShortcutManager.shared.selectedTriggerKey = key
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.zSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.zBorder, lineWidth: 1))
                )
                .padding(.horizontal, 44)
                .padding(.bottom, 16)

                // Info card
                HStack(spacing: 14) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.zOrange)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(t(
                            "Fonctionne globalement",
                            "Works globally",
                            "Funciona globalmente",
                            "全局可用",
                            "グローバルに機能",
                            "Работает глобально"
                        ))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.zText)

                        Text(t(
                            "Xcode, VS Code, Messages, Safari — partout sur macOS.",
                            "Xcode, VS Code, Messages, Safari — everywhere on macOS.",
                            "Xcode, VS Code, Messages, Safari — en cualquier lugar de macOS.",
                            "Xcode、VS Code、Messages、Safari 等 macOS 任意应用。",
                            "Xcode、VS Code、Messages、Safari など macOS のどこでも。",
                            "Xcode, VS Code, Messages, Safari — везде на macOS."
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(Color.zTextSub)
                        .lineSpacing(2)
                    }
                }
                .padding(16)
                .background(Color.zSurface2)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.zBorder, lineWidth: 1))
                .padding(.horizontal, 44)
                .padding(.bottom, 14)
            }
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
                    : (isHovered ? Color(hex: "1A1A1A").opacity(0.1) : Color(hex: "1A1A1A").opacity(0.06))
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAccent ? Color.clear : Color(hex: "1A1A1A").opacity(0.14), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
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
        .background(color.opacity(0.10))
        .cornerRadius(20)
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
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
                    .font(.system(size: 18))
                Text(language.name)
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

// MARK: Shortcut Step

private struct PFShortcutStep: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "1A1A1A"))
        }
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

#Preview {
    PreflightView(onReady: {})
        .frame(width: 860, height: 600)
}
