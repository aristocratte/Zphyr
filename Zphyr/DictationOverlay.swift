//
//  DictationOverlay.swift
//  Zphyr
//
//  Compact pill HUD at the bottom-center of the screen while dictating.
//  Inspired by Whisper's minimal floating indicator.
//

import SwiftUI
import Observation

// MARK: - Overlay Window Controller

final class DictationOverlayController: NSObject {
    private var overlayWindow: NSWindow?

    func show() {
        if overlayWindow == nil { createWindow() }
        overlayWindow?.orderFrontRegardless()
    }

    func hide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.overlayWindow?.orderOut(nil)
        }
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }

        // Compact pill size
        let width: CGFloat  = 180
        let height: CGFloat = 44

        // Position just above the Dock (visually between dock and content)
        let dockHeight: CGFloat = 80
        let x = screen.frame.midX - width / 2
        let y = screen.frame.minY + dockHeight

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver   // above everything, including dock
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: DictationOverlayView())
        hostingView.frame = window.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)
        overlayWindow = window
    }
}

// MARK: - Dictionary Suggestion Popup

@MainActor
final class DictionarySuggestionOverlayController: NSObject {
    static let shared = DictionarySuggestionOverlayController()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<DictionarySuggestionOverlayView>?

    func present(_ suggestion: DictionarySuggestion) {
        if overlayWindow == nil { createWindow() }
        guard let overlayWindow else { return }

        let content = DictionarySuggestionOverlayView(
            suggestion: suggestion,
            onAdd: {
                AppState.shared.acceptPendingDictionarySuggestion()
            },
            onIgnore: {
                AppState.shared.dismissPendingDictionarySuggestion()
            }
        )

        if let hostingView {
            hostingView.rootView = content
        } else if let contentView = overlayWindow.contentView {
            let newHostingView = NSHostingView(rootView: content)
            newHostingView.frame = contentView.bounds
            newHostingView.autoresizingMask = [.width, .height]
            contentView.addSubview(newHostingView)
            self.hostingView = newHostingView
        }

        positionWindow(overlayWindow)
        overlayWindow.orderFrontRegardless()
    }

    func dismiss() {
        overlayWindow?.orderOut(nil)
    }

    private func createWindow() {
        let window = DictionarySuggestionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 146),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.animationBehavior = .alertPanel
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        overlayWindow = window
    }

    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen = activeScreen else { return }

        let visible = screen.visibleFrame
        let margin: CGFloat = 18
        let x = visible.maxX - window.frame.width - margin
        let y = visible.minY + margin
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class DictionarySuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DictionarySuggestionOverlayView: View {
    let suggestion: DictionarySuggestion
    let onAdd: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Ajouter au dictionnaire ?", "Add to dictionary?", "¿Añadir al diccionario?", "添加到词典？", "辞書に追加しますか？", "Добавить в словарь?"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            Text(
                t("Tu as remplacé \"\(suggestion.mistakenWord)\" par \"\(suggestion.correctedWord)\".",
                  "You replaced \"\(suggestion.mistakenWord)\" with \"\(suggestion.correctedWord)\".",
                  "Has reemplazado \"\(suggestion.mistakenWord)\" por \"\(suggestion.correctedWord)\".",
                  "你将 \"\(suggestion.mistakenWord)\" 替换为 \"\(suggestion.correctedWord)\"。",
                  "\"\(suggestion.mistakenWord)\" を \"\(suggestion.correctedWord)\" に置き換えました。",
                  "Вы заменили \"\(suggestion.mistakenWord)\" на \"\(suggestion.correctedWord)\".")
            )
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#5A5A57"))
                .lineSpacing(2)

            HStack(spacing: 8) {
                Spacer()

                Button(t("Ignorer", "Ignore", "Ignorar", "忽略", "無視", "Игнорировать"), action: onIgnore)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#666663"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#ECECE8"))
                    .clipShape(Capsule())

                Button(t("Ajouter", "Add", "Añadir", "添加", "追加", "Добавить"), action: onAdd)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#1A1A1A"))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#FAFAF8"))
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(6)
    }
}

// MARK: - Overlay View

struct DictationOverlayView: View {
    var state: DictationState { AppState.shared.dictationState }
    var levels: [CGFloat]     { AppState.shared.audioLevels }

    @State private var appear = false

    var body: some View {
        pillContent
            .frame(height: 44)
            .background(pillBackground)
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 6)
            .scaleEffect(appear ? 1.0 : 0.78)
            .opacity(appear ? 1.0 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                    appear = true
                }
            }
    }

    // MARK: - Pill content

    @ViewBuilder
    private var pillContent: some View {
        switch state {
        case .listening:
            // Animated dots spectrum
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { i in
                    DotBar(level: i < levels.count ? levels[i * 3] : 0.2, index: i)
                }
            }
            .padding(.horizontal, 20)
            .transition(.opacity)

        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(.white)
                Text(t("Transcription…", "Transcribing…", "Transcribiendo…", "转写中…", "文字起こし中…", "Транскрибация…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 20)
            .transition(.opacity)

        case .done(let text):
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text(text.isEmpty ? t("Terminé", "Done", "Hecho", "完成", "完了", "Готово") : text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 20)
            .transition(.opacity)

        default:
            EmptyView()
        }
    }

    // MARK: - Pill background

    private var pillBackground: some View {
        Capsule()
            .fill(Color.black.opacity(0.88))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Dot Bar (minimal waveform dot)

private struct DotBar: View {
    let level: CGFloat
    let index: Int

    @State private var display: CGFloat = 0.2

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.7 + Double(display) * 0.3))
            .frame(width: 3.5, height: max(4, display * 22))
            .animation(.linear(duration: 0.08), value: display)
            .onAppear { display = level }
            .onChange(of: level) { _, v in display = v }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        VStack {
            Spacer()
            DictationOverlayView()
                .frame(width: 180)
                .padding(.bottom, 40)
                .onAppear {
                    AppState.shared.dictationState = .listening
                    Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                        AppState.shared.audioLevels = (0..<28).map { _ in .random(in: 0.1...1.0) }
                    }
                }
        }
    }
    .frame(width: 420, height: 280)
}
