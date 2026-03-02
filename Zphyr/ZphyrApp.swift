//
//  ZphyrApp.swift
//  Zphyr
//

import SwiftUI
import AppKit

@main
struct ZphyrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(t("Ouvrir Zphyr", "Open Zphyr", "Abrir Zphyr", "打开 Zphyr", "Zphyr を開く", "Открыть Zphyr")) {
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    // Called once the window is ready — set initial size based on onboarding state
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Listen for onboarding completion → resize to preflight size
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingCompleted),
            name: .onboardingCompleted,
            object: nil
        )

        // Listen for preflight completion → resize to main app
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preflightCompleted),
            name: .preflightCompleted,
            object: nil
        )

        configureWindowSize()

        // Start shortcut listener only when everything is already ready
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hasCompletedPreflight = UserDefaults.standard.bool(forKey: "hasCompletedPreflight")
        if hasCompleted && hasCompletedPreflight && AppState.shared.modelStatus.isReady {
            ShortcutManager.shared.startListening()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { window.orderOut(nil) }
    }

    @objc func onboardingCompleted() {
        // After onboarding → go to preflight size (not main app yet)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.resizeToPreflight()
        }
    }

    @objc func preflightCompleted() {
        // Whisper is loaded → open main app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.resizeToMainApp()
            ShortcutManager.shared.startListening()
        }
    }

    // MARK: - Window sizing

    private func configureWindowSize() {
        guard let window = NSApp.windows.first else { return }
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hasCompletedPreflight = UserDefaults.standard.bool(forKey: "hasCompletedPreflight")
        if !hasCompleted {
            // First launch: show onboarding
            resizeToOnboarding(window: window)
        } else if hasCompletedPreflight {
            // User already completed preflight previously.
            resizeToMainApp(window: window)
        } else {
            // Onboarding done → always start at preflight size.
            // ContentView controls the actual transition to MainView
            // once the user explicitly dismisses preflight.
            resizeToPreflight(window: window)
        }
    }

    private func resizeToOnboarding(window: NSWindow? = nil) {
        guard let window = window ?? NSApp.windows.first else { return }
        let size = NSSize(width: 780, height: 580)
        window.minSize = size
        window.maxSize = size
        window.setContentSize(size)
        window.center()
    }

    private func resizeToPreflight(window: NSWindow? = nil) {
        guard let window = window ?? NSApp.windows.first else { return }
        let size = NSSize(width: 1060, height: 720)
        window.minSize = size
        window.maxSize = size
        window.setContentSize(size)
        window.center()
    }

    func resizeToMainApp(window: NSWindow? = nil) {
        guard let window = window ?? NSApp.windows.first else { return }
        // Unlock size constraints before expanding
        window.minSize = NSSize(width: 1100, height: 720)
        window.maxSize = NSSize(width: 99999, height: 99999)
        let newSize = NSSize(width: 1400, height: 880)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setContentSize(newSize)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar

    func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "Zphyr")
            button.image?.isTemplate = true
            button.action = #selector(toggleMainWindow)
            button.target = self
        }
    }

    @objc func toggleMainWindow() {
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Notification names
extension Notification.Name {
    static let onboardingCompleted = Notification.Name("ZphyrOnboardingCompleted")
    static let preflightCompleted  = Notification.Name("ZphyrPreflightCompleted")
}
