//
//  ZphyrApp.swift
//  Zphyr
//

import SwiftUI
import AppKit
import Darwin.Mach

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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    private let statusPopover = NSPopover()
    private let popoverStore = MenuBarPopoverStore()
    private var statusRefreshTimer: Timer?
    private var cachedPrimaryModelInstallURL: URL?
    private var cachedPrimaryModelDiskBytes: Int64 = 0
    private var cachedFormatterModelDiskBytes: Int64 = 0
    private var lastProcessCPUSample: ProcessCPUSample?
    private var popoverRefreshTask: Task<Void, Never>?
    // Cached once — physicalMemory and activeProcessorCount never change at runtime
    private let cachedTotalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
    private let cachedMaxCPU = max(100.0, Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0)

    private struct ProcessCPUSample {
        let timestamp: TimeInterval
        let totalCPUTime: TimeInterval
    }

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

        // Eagerly preload the formatter model in the background so the first
        // dictation doesn't pay the cold-load + shader compilation cost.
        if hasCompletedPreflight && AppState.shared.advancedModeInstalled
            && AppState.shared.formattingMode != .trigger {
            Task {
                await AdvancedLLMFormatter.shared.loadIfInstalled()
                await AdvancedLLMFormatter.shared.warmup()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopStatusRefreshTimer()
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
            button.action = #selector(toggleStatusPopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }

        statusPopover.behavior = .transient
        statusPopover.delegate = self
        statusPopover.animates = true
        statusPopover.contentSize = NSSize(width: 352, height: 334)
        statusPopover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                store: popoverStore,
                onToggleMainWindow: { [weak self] in
                    self?.toggleMainWindowFromPopover()
                },
                onLoadPrimaryModel: { [weak self] in
                    self?.loadPrimaryModelFromPopover()
                },
                onOpenPrimaryModelFolder: { [weak self] in
                    self?.openPrimaryModelFolderFromPopover()
                },
                onQuit: { [weak self] in
                    self?.quitFromPopover()
                }
            )
        )

        lastProcessCPUSample = Self.currentProcessCPUSample()
        refreshStatusPopover(recomputeDiskUsage: true)
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

    // MARK: - Status popover

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if statusPopover.isShown {
            statusPopover.performClose(sender)
            stopStatusRefreshTimer()
            return
        }
        refreshStatusPopover(recomputeDiskUsage: true)
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startStatusRefreshTimer()
    }

    func popoverDidClose(_ notification: Notification) {
        stopStatusRefreshTimer()
    }

    private func refreshStatusPopover(recomputeDiskUsage: Bool) {
        if recomputeDiskUsage {
            let explicitModelPath = AppState.shared.modelInstallPath
            popoverRefreshTask?.cancel()
            applyStatusPopoverSnapshot()
            popoverRefreshTask = Task { [weak self] in
                guard let self else { return }
                defer { self.popoverRefreshTask = nil }
                let diskUsage = await Task.detached(priority: .utility) {
                    let installURL = Self.resolveWhisperInstallURL(explicitPath: explicitModelPath)
                    let primaryDiskBytes = installURL.map { Self.directoryAllocatedSize(at: $0) } ?? 0
                    let formatterDiskBytes = Self.resolveFormattingModelDiskUsageBytes()
                    return (installURL, primaryDiskBytes, formatterDiskBytes)
                }.value
                guard !Task.isCancelled else { return }
                self.cachedPrimaryModelInstallURL = diskUsage.0
                self.cachedPrimaryModelDiskBytes = diskUsage.1
                self.cachedFormatterModelDiskBytes = diskUsage.2
                self.applyStatusPopoverSnapshot()
            }
            return
        }

        applyStatusPopoverSnapshot()
    }

    private func applyStatusPopoverSnapshot() {
        let appHasVisibleWindow = NSApp.windows.contains(where: \.isVisible)
        let state = AppState.shared
        let primaryInstalled = cachedPrimaryModelInstallURL != nil || state.modelStatus.isReady
        let primaryFolderAvailable = cachedPrimaryModelInstallURL != nil
        let formatterInstalled = AppState.shared.advancedModeInstalled || cachedFormatterModelDiskBytes > 0
        let processCPU = sampledCurrentProcessCPUPercent()

        popoverStore.isMainWindowVisible = appHasVisibleWindow
        popoverStore.modelStatus = state.modelStatus
        popoverStore.snapshot = MenuBarUsageSnapshot(
            primaryModelDiskBytes: cachedPrimaryModelDiskBytes,
            formatterModelDiskBytes: cachedFormatterModelDiskBytes,
            processRAMBytes: Self.currentProcessMemoryFootprintBytes(),
            totalRAMBytes: cachedTotalRAM,
            processCPUPercent: processCPU,
            maxCPUPercent: cachedMaxCPU,
            primaryModelInstalled: primaryInstalled,
            primaryModelFolderAvailable: primaryFolderAvailable,
            formatterModelInstalled: formatterInstalled
        )
    }

    private func toggleMainWindowFromPopover() {
        toggleMainWindow()
        refreshStatusPopover(recomputeDiskUsage: false)
        statusPopover.performClose(nil)
    }

    private func loadPrimaryModelFromPopover() {
        statusPopover.performClose(nil)
        Task {
            await DictationEngine.shared.loadModel()
            self.refreshStatusPopover(recomputeDiskUsage: true)
        }
    }

    private func openPrimaryModelFolderFromPopover() {
        let explicitModelPath = AppState.shared.modelInstallPath
        guard let modelURL = cachedPrimaryModelInstallURL ?? Self.resolveWhisperInstallURL(explicitPath: explicitModelPath) else { return }
        statusPopover.performClose(nil)
        NSWorkspace.shared.activateFileViewerSelecting([modelURL])
    }

    private func quitFromPopover() {
        statusPopover.performClose(nil)
        NSApp.terminate(nil)
    }

    private func startStatusRefreshTimer() {
        stopStatusRefreshTimer()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refreshStatusPopover(recomputeDiskUsage: false)
            }
        }
    }

    private func stopStatusRefreshTimer() {
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = nil
    }

    private func sampledCurrentProcessCPUPercent() -> Double {
        guard let sample = Self.currentProcessCPUSample() else { return 0 }
        defer { lastProcessCPUSample = sample }
        guard let previous = lastProcessCPUSample else { return 0 }
        let elapsed = sample.timestamp - previous.timestamp
        guard elapsed > 0 else { return 0 }
        if elapsed > 10 { return 0 } // reset stale baseline after long inactivity
        let cpuDelta = sample.totalCPUTime - previous.totalCPUTime
        guard cpuDelta > 0 else { return 0 }
        return max(0, (cpuDelta / elapsed) * 100.0)
    }

    nonisolated private static func resolveWhisperInstallURL(explicitPath: String?) -> URL? {
        let fileManager = FileManager.default

        if let explicitPath, fileManager.fileExists(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }

        return WhisperKitBackend.resolveInstallURL()
    }

    nonisolated private static func resolveFormattingModelDiskUsageBytes() -> Int64 {
        formattingModelInstallDirectories().reduce(0) { $0 + directoryAllocatedSize(at: $1) }
    }

    nonisolated private static func formattingModelInstallDirectories() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        var uniquePaths = Set<String>()
        var results: [URL] = []

        let roots = [
            home.appendingPathComponent(".cache/huggingface/hub"),
            home.appendingPathComponent("Library/Caches/huggingface/hub"),
            home.appendingPathComponent("Library/Application Support/huggingface/hub")
        ]

        for descriptor in FormattingModelCatalog.all {
            let mlxDirect = home
                .appendingPathComponent("Library/Caches/models/\(descriptor.cacheNamespace)/\(descriptor.cacheSlug)")
            if fileManager.fileExists(atPath: mlxDirect.path) {
                let normalizedPath = mlxDirect.standardizedFileURL.path
                if !uniquePaths.contains(normalizedPath) {
                    uniquePaths.insert(normalizedPath)
                    results.append(mlxDirect)
                }
            }

            for root in roots where fileManager.fileExists(atPath: root.path) {
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for entry in entries {
                    let name = entry.lastPathComponent.lowercased()
                    let isFormattingModelFolder = descriptor.cacheMatchHints.contains { hint in
                        name.contains(hint.lowercased())
                    }
                    guard isFormattingModelFolder else { continue }
                    let normalizedPath = entry.standardizedFileURL.path
                    guard !uniquePaths.contains(normalizedPath) else { continue }
                    uniquePaths.insert(normalizedPath)
                    results.append(entry)
                }
            }
        }

        return results
    }

    nonisolated private static func directoryAllocatedSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            totalBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return totalBytes
    }

    private static func currentProcessMemoryFootprintBytes() -> Int64 {
        var vmInfo = task_vm_info_data_t()
        var vmInfoCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmResult: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmInfoCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            return Int64(vmInfo.phys_footprint)
        }

        var info = mach_task_basic_info()
        var infoCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &infoCount)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }

    private static func currentProcessCPUSample() -> ProcessCPUSample? {
        var info = task_thread_times_info_data_t()
        var infoCount = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &infoCount)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let userTime = TimeInterval(info.user_time.seconds) + TimeInterval(info.user_time.microseconds) / 1_000_000
        let systemTime = TimeInterval(info.system_time.seconds) + TimeInterval(info.system_time.microseconds) / 1_000_000
        return ProcessCPUSample(
            timestamp: Date().timeIntervalSinceReferenceDate,
            totalCPUTime: userTime + systemTime
        )
    }
}

// MARK: - Notification names
extension Notification.Name {
    static let onboardingCompleted = Notification.Name("ZphyrOnboardingCompleted")
    static let preflightCompleted  = Notification.Name("ZphyrPreflightCompleted")
    static let returnToOnboarding  = Notification.Name("ZphyrReturnToOnboarding")
}
