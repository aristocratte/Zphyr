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
}

// MARK: - RecordedShortcut (custom key binding)

struct RecordedShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierRawValue: UInt
    var displayText: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }
}

// MARK: - ShortcutManager

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

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
        guard let data = UserDefaults.standard.data(forKey: "zphyr.shortcut.custom"),
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

    private var recordingMonitor: Any?
    private var customKeyDownMonitor: Any?
    private var customKeyUpMonitor: Any?
    var isRecording: Bool = false
    private var recordingCallback: ((RecordedShortcut) -> Void)?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
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
        if let custom = recordedShortcut {
            customKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == custom.keyCode else { return }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard mods.rawValue == custom.modifierRawValue || custom.modifierRawValue == 0 else { return }
                Task { @MainActor in
                    if !self.isHolding {
                        self.isHolding = true
                        await DictationEngine.shared.startDictation()
                    }
                }
            }
            customKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self, event.keyCode == custom.keyCode else { return }
                Task { @MainActor in
                    if self.isHolding {
                        self.isHolding = false
                        await DictationEngine.shared.stopDictation()
                    }
                }
            }
        }
    }

    func stopListening() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m); localFlagsMonitor  = nil }
        if let m = customKeyDownMonitor { NSEvent.removeMonitor(m); customKeyDownMonitor = nil }
        if let m = customKeyUpMonitor  { NSEvent.removeMonitor(m); customKeyUpMonitor  = nil }
        isHolding = false
    }

    // MARK: - Flag change handler

    private func handleFlagsChanged(_ event: NSEvent) {
        guard recordedShortcut == nil else { return } // Custom shortcut handles key events separately
        guard event.keyCode == selectedTriggerKey.keyCode else { return }
        let isDown = event.modifierFlags.contains(selectedTriggerKey.modifierFlag)

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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Build display text
            var parts: [String] = []
            if modifiers.contains(.command)  { parts.append("⌘") }
            if modifiers.contains(.option)   { parts.append("⌥") }
            if modifiers.contains(.control)  { parts.append("⌃") }
            if modifiers.contains(.shift)    { parts.append("⇧") }
            let keyStr = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            if event.type == .keyDown && !keyStr.isEmpty && keyStr != "?" {
                parts.append(keyStr)
            }
            let displayText = parts.joined()
            guard !displayText.isEmpty else { return event }
            let shortcut = RecordedShortcut(
                keyCode: event.keyCode,
                modifierRawValue: modifiers.rawValue,
                displayText: displayText
            )
            Task { @MainActor in
                self.stopRecording()
                onRecorded(shortcut)
            }
            return nil // consume event
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = recordingMonitor { NSEvent.removeMonitor(m); recordingMonitor = nil }
        recordingCallback = nil
    }

    func clearCustomShortcut() {
        stopRecording()
        recordedShortcut = nil
    }
}
