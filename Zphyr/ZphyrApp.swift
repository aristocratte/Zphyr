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

    // Called once the window is ready — set initial size based on preflight state
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Listen for preflight completion → resize to main app
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preflightCompleted),
            name: .preflightCompleted,
            object: nil
        )

        // Listen for "return to onboarding" request from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReturnToOnboarding),
            name: .returnToOnboarding,
            object: nil
        )

        configureWindowSize()

        // Start shortcut listener only when everything is already ready
        let hasCompletedPreflight = UserDefaults.standard.bool(forKey: "hasCompletedPreflight")
        if hasCompletedPreflight && AppState.shared.modelStatus.isReady {
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

    @objc func handleReturnToOnboarding() {
        guard let window = NSApp.windows.first else { return }
        // Hide the window BEFORE the view swap — this stops AppKit's display
        // cycle from triggering layout while NavigationSplitView is being
        // torn down (which causes infinite NSSplitViewItemViewWrapper
        // constraint recursion).
        window.orderOut(nil)
        // Now flip the flag; SwiftUI will swap MainView → PreflightView
        // while the window is hidden (no layout cycles).
        UserDefaults.standard.set(false, forKey: "hasCompletedPreflight")
        // Wait for SwiftUI to fully destroy the NavigationSplitView hierarchy,
        // then resize and show the fresh preflight window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.resizeToPreflight(window: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func preflightCompleted() {
        guard let window = NSApp.windows.first else { return }
        // Hide window to prevent NSSplitView constraint recursion during
        // the SwiftUI view swap (PreflightView → MainView with NavigationSplitView).
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.resizeToMainApp(window: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            ShortcutManager.shared.startListening()
        }
    }

    // MARK: - Window sizing

    private func configureWindowSize() {
        guard let window = NSApp.windows.first else { return }
        let hasCompletedPreflight = UserDefaults.standard.bool(forKey: "hasCompletedPreflight")
        if hasCompletedPreflight {
            resizeToMainApp(window: window)
        } else {
            resizeToPreflight(window: window)
        }
    }

    private func resizeToPreflight(window: NSWindow? = nil) {
        guard let window = window ?? NSApp.windows.first else { return }
        let size = NSSize(width: 1060, height: 720)
        // Unlock first so any competing layout constraints don't fight the resize
        window.minSize = NSSize(width: 600, height: 400)
        window.maxSize = NSSize(width: 99999, height: 99999)
        window.setContentSize(size)
        window.center()
        // Lock to fixed size after the frame has settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.minSize = size
            window.maxSize = size
        }
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
    static let returnToOnboarding  = Notification.Name("ZphyrReturnToOnboarding")
}
