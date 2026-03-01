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

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isHolding = false

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
    }

    func stopListening() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m); localFlagsMonitor  = nil }
        isHolding = false
    }

    // MARK: - Flag change handler

    private func handleFlagsChanged(_ event: NSEvent) {
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
}
