//
//  ShortcutManager.swift
//  Zphyr
//
//  Listens globally AND locally for the hold-to-dictate key.
//  Key down → start recording. Key up → stop and transcribe.
//  Uses both global monitors (other apps) and local monitors (Zphyr in foreground).
//

import AppKit
import Carbon
import Observation

// MARK: - TriggerKey

enum TriggerKey: String, CaseIterable, Identifiable {
    case rightOption  = "rightOption"
    case leftOption   = "leftOption"
    case rightControl = "rightControl"
    case rightShift   = "rightShift"

    var id: String { rawValue }

    /// macOS key code used in `NSEvent.keyCode` for `flagsChanged` events.
    var keyCode: UInt16 {
        switch self {
        case .rightOption:  return 61
        case .leftOption:   return 58
        case .rightControl: return 62
        case .rightShift:   return 60
        }
    }

    /// Symbol displayed in UI
    var symbol: String {
        switch self {
        case .rightOption:  return "⌥"
        case .leftOption:   return "⌥"
        case .rightControl: return "⌃"
        case .rightShift:   return "⇧"
        }
    }

    /// Short label for the key
    var shortLabel: String {
        switch self {
        case .rightOption:  return "⌥ right"
        case .leftOption:   return "⌥ left"
        case .rightControl: return "⌃ right"
        case .rightShift:   return "⇧ right"
        }
    }

    func displayName(for lang: String) -> String {
        switch self {
        case .rightOption:
            return L10n.ui(for: lang,
                fr: "⌥ Option droite", en: "⌥ Right Option",
                es: "⌥ Opción derecha", zh: "⌥ 右 Option",
                ja: "⌥ 右 Option", ru: "⌥ правая Option")
        case .leftOption:
            return L10n.ui(for: lang,
                fr: "⌥ Option gauche", en: "⌥ Left Option",
                es: "⌥ Opción izquierda", zh: "⌥ 左 Option",
                ja: "⌥ 左 Option", ru: "⌥ левая Option")
        case .rightControl:
            return L10n.ui(for: lang,
                fr: "⌃ Ctrl droit", en: "⌃ Right Control",
                es: "⌃ Control derecho", zh: "⌃ 右 Control",
                ja: "⌃ 右 Control", ru: "⌃ правый Control")
        case .rightShift:
            return L10n.ui(for: lang,
                fr: "⇧ Shift droit", en: "⇧ Right Shift",
                es: "⇧ Shift derecho", zh: "⇧ 右 Shift",
                ja: "⇧ 右 Shift", ru: "⇧ правый Shift")
        }
    }

    /// The NSEvent modifier flag that corresponds to this key being held
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption, .leftOption: return .option
        case .rightControl:             return .control
        case .rightShift:               return .shift
        }
    }

    static func from(keyCode: UInt16) -> TriggerKey? {
        allCases.first { $0.keyCode == keyCode }
    }
}

// MARK: - RecordedShortcut (custom key binding)

struct RecordedShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierRawValue: UInt
    var displayText: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    var normalizedModifierFlags: NSEvent.ModifierFlags {
        ShortcutManager.normalizedModifierFlags(modifierFlags)
    }

    var isModifierOnly: Bool {
        guard let modifierFlag = ShortcutManager.modifierFlagForKeyCode(keyCode) else { return false }
        return normalizedModifierFlags == modifierFlag
    }
}

// MARK: - ShortcutManager

@Observable
@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()
    nonisolated static let relevantModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private static let userDefaultsKey = "zphyr.shortcut.triggerKey"

    var selectedTriggerKey: TriggerKey = .rightOption {
        didSet {
            UserDefaults.standard.set(selectedTriggerKey.rawValue, forKey: Self.userDefaultsKey)
            // Restart listeners so new key code is used
            if globalFlagsMonitor != nil {
                stopListening()
                startListening()
            }
        }
    }

    var triggerKeyCode: UInt16 { selectedTriggerKey.keyCode }

    private static let customShortcutKey = "zphyr.shortcut.custom"

    var recordedShortcut: RecordedShortcut? = {
        guard let data = UserDefaults.standard.data(forKey: ShortcutManager.customShortcutKey),
              let shortcut = try? JSONDecoder().decode(RecordedShortcut.self, from: data)
        else { return nil }
        return shortcut
    }() {
        didSet {
            if let shortcut = recordedShortcut,
               let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: Self.customShortcutKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.customShortcutKey)
            }
            if globalFlagsMonitor != nil {
                stopListening()
                startListening()
            }
        }
    }

    var activeShortcutDisplayText: String {
        recordedShortcut?.displayText ?? selectedTriggerKey.shortLabel
    }

    func activeShortcutDisplayName(for languageCode: String) -> String {
        if let recordedShortcut {
            if let triggerKey = TriggerKey.from(keyCode: recordedShortcut.keyCode),
               recordedShortcut.isModifierOnly {
                return triggerKey.displayName(for: languageCode)
            }
            return recordedShortcut.displayText
        }
        return selectedTriggerKey.displayName(for: languageCode)
    }

    @ObservationIgnored
    private var recordingMonitor: Any?
    @ObservationIgnored
    private var customKeyDownMonitor: Any?
    @ObservationIgnored
    private var customKeyUpMonitor: Any?
    @ObservationIgnored
    private var customLocalKeyDownMonitor: Any?
    @ObservationIgnored
    private var customLocalKeyUpMonitor: Any?
    @ObservationIgnored
    private var pendingModifierShortcut: RecordedShortcut?
    @ObservationIgnored
    var isRecording: Bool = false
    @ObservationIgnored
    private var recordingCallback: ((RecordedShortcut) -> Void)?

    @ObservationIgnored
    private var globalFlagsMonitor: Any?
    @ObservationIgnored
    private var localFlagsMonitor: Any?
    @ObservationIgnored
    private(set) var isHolding = false

    private init() {
        // Load persisted trigger key
        if let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let key = TriggerKey(rawValue: saved) {
            selectedTriggerKey = key
        }
    }

    // MARK: - Start / Stop listening

    func startListening() {
        guard globalFlagsMonitor == nil else { return }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handleFlagsChanged(event) }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Custom shortcut key down/up monitoring
        if let custom = recordedShortcut, !custom.isModifierOnly {
            customKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleCustomKeyDown(event, shortcut: custom)
                }
            }
            customKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleCustomKeyUp(event, shortcut: custom)
                }
            }
            customLocalKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleCustomKeyDown(event, shortcut: custom) ? nil : event
            }
            customLocalKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else { return event }
                return self.handleCustomKeyUp(event, shortcut: custom) ? nil : event
            }
        }
    }

    func stopListening() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m); localFlagsMonitor  = nil }
        if let m = customKeyDownMonitor { NSEvent.removeMonitor(m); customKeyDownMonitor = nil }
        if let m = customKeyUpMonitor  { NSEvent.removeMonitor(m); customKeyUpMonitor  = nil }
        if let m = customLocalKeyDownMonitor { NSEvent.removeMonitor(m); customLocalKeyDownMonitor = nil }
        if let m = customLocalKeyUpMonitor  { NSEvent.removeMonitor(m); customLocalKeyUpMonitor  = nil }
        isHolding = false
    }

    // MARK: - Flag change handler

    private func handleFlagsChanged(_ event: NSEvent) {
        if let custom = recordedShortcut {
            if custom.isModifierOnly {
                handleCustomModifierFlagsChanged(event, shortcut: custom)
            }
            return
        }

        guard event.keyCode == selectedTriggerKey.keyCode else { return }
        let isDown = Self.normalizedModifierFlags(event.modifierFlags).contains(selectedTriggerKey.modifierFlag)

        if isDown && !isHolding {
            isHolding = true
            Task { await DictationEngine.shared.startDictation() }
        } else if !isDown && isHolding {
            isHolding = false
            Task { await DictationEngine.shared.stopDictation() }
        }
    }

    // MARK: - Custom Shortcut Recording

    func startRecording(onRecorded: @escaping (RecordedShortcut) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        recordingCallback = onRecorded
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let modifiers = Self.normalizedModifierFlags(event.modifierFlags)

            if event.type == .keyDown,
               let shortcut = Self.makeShortcutFromKeyDown(event, modifiers: modifiers) {
                Task { @MainActor in
                    self.stopRecording()
                    onRecorded(shortcut)
                }
                return nil
            }

            if event.type == .flagsChanged,
               let modifierFlag = Self.modifierFlagForKeyCode(event.keyCode),
               let displayText = Self.modifierDisplayTextForKeyCode(event.keyCode) {
                let isDown = modifiers.contains(modifierFlag)
                if isDown {
                    self.pendingModifierShortcut = RecordedShortcut(
                        keyCode: event.keyCode,
                        modifierRawValue: modifierFlag.rawValue,
                        displayText: displayText
                    )
                } else if let pendingModifierShortcut,
                          pendingModifierShortcut.keyCode == event.keyCode {
                    let shortcut = pendingModifierShortcut
                    Task { @MainActor in
                        self.stopRecording()
                        onRecorded(shortcut)
                    }
                }
                return nil
            }

            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = recordingMonitor { NSEvent.removeMonitor(m); recordingMonitor = nil }
        recordingCallback = nil
        pendingModifierShortcut = nil
    }

    func clearCustomShortcut() {
        stopRecording()
        recordedShortcut = nil
    }

    // MARK: - Internal helpers

    nonisolated static func modifierFlagForKeyCode(_ keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 58, 61: return .option
        case 59, 62: return .control
        case 56, 60: return .shift
        case 54, 55: return .command
        default: return nil
        }
    }

    nonisolated static func modifierDisplayTextForKeyCode(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 58: return "⌥ Left Option"
        case 61: return "⌥ Right Option"
        case 59: return "⌃ Left Control"
        case 62: return "⌃ Right Control"
        case 56: return "⇧ Left Shift"
        case 60: return "⇧ Right Shift"
        case 55: return "⌘ Left Command"
        case 54: return "⌘ Right Command"
        default: return nil
        }
    }

    nonisolated static func normalizedModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(relevantModifierFlags)
    }

    nonisolated static func isModifierOnlyShortcut(_ shortcut: RecordedShortcut) -> Bool {
        guard let modifierFlag = modifierFlagForKeyCode(shortcut.keyCode) else { return false }
        let normalized = normalizedModifierFlags(NSEvent.ModifierFlags(rawValue: shortcut.modifierRawValue))
        return normalized == modifierFlag
    }

    // MARK: - Custom shortcut runtime handling

    private func handleCustomModifierFlagsChanged(_ event: NSEvent, shortcut: RecordedShortcut) {
        guard event.keyCode == shortcut.keyCode else { return }

        let isDown = Self.normalizedModifierFlags(event.modifierFlags) == shortcut.normalizedModifierFlags
        if isDown && !isHolding {
            isHolding = true
            Task { await DictationEngine.shared.startDictation() }
        } else if !isDown && isHolding {
            isHolding = false
            Task { await DictationEngine.shared.stopDictation() }
        }
    }

    @discardableResult
    private func handleCustomKeyDown(_ event: NSEvent, shortcut: RecordedShortcut) -> Bool {
        guard event.keyCode == shortcut.keyCode else { return false }
        let modifiers = Self.normalizedModifierFlags(event.modifierFlags)
        guard modifiers == shortcut.normalizedModifierFlags else { return false }
        guard !isHolding else { return true }
        isHolding = true
        Task { await DictationEngine.shared.startDictation() }
        return true
    }

    @discardableResult
    private func handleCustomKeyUp(_ event: NSEvent, shortcut: RecordedShortcut) -> Bool {
        guard event.keyCode == shortcut.keyCode else { return false }
        guard isHolding else { return true }
        isHolding = false
        Task { await DictationEngine.shared.stopDictation() }
        return true
    }

    private static func makeShortcutFromKeyDown(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> RecordedShortcut? {
        let keyStr = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        guard !keyStr.isEmpty, keyStr != "?" else { return nil }

        var parts: [String] = []
        if modifiers.contains(.command)  { parts.append("⌘") }
        if modifiers.contains(.option)   { parts.append("⌥") }
        if modifiers.contains(.control)  { parts.append("⌃") }
        if modifiers.contains(.shift)    { parts.append("⇧") }
        parts.append(keyStr)

        return RecordedShortcut(
            keyCode: event.keyCode,
            modifierRawValue: modifiers.rawValue,
            displayText: parts.joined()
        )
    }
}
