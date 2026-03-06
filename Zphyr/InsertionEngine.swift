//
//  InsertionEngine.swift
//  Zphyr
//
//  Deterministic, accessibility-gated text injection via CGEvent keystroke simulation.
//  Falls back to clipboard if Accessibility is not trusted.
//
// TODO: [INSERTION_STREAMING] For live corrections, implement a diffing engine that
// replaces only changed words rather than re-typing full text. Requires cursor tracking.

import Foundation
import AppKit
import os

@MainActor
final class InsertionEngine {

    private let log = Logger(subsystem: "com.zphyr.app", category: "InsertionEngine")
    private nonisolated static let learningLogger = Logger(subsystem: "com.zphyr.app", category: "DictionaryLearning")

    private var correctionMonitorTask: Task<Void, Never>?

    // MARK: - Public API

    /// Activates the target app, waits for it to become frontmost, then inserts text via synthesized key events.
    func insert(_ text: String, into targetApp: NSRunningApplication?) async {
        guard AXIsProcessTrusted() else {
            copyToClipboard(text)
            AppState.shared.error = L10n.ui(
                for: AppState.shared.selectedLanguage.id,
                fr: "Acc\u{00E8}s Accessibilit\u{00E9} manquant. Le texte a \u{00E9}t\u{00E9} copi\u{00E9} dans le presse-papiers.",
                en: "Accessibility access is missing. Text was copied to the clipboard.",
                es: "Falta acceso de Accesibilidad. El texto se copi\u{00F3} al portapapeles.",
                zh: "\u{7F3A}\u{5C11}\u{8F85}\u{52A9}\u{529F}\u{80FD}\u{6743}\u{9650}\u{3002}\u{6587}\u{672C}\u{5DF2}\u{590D}\u{5236}\u{5230}\u{526A}\u{8D34}\u{677F}\u{3002}",
                ja: "\u{30A2}\u{30AF}\u{30BB}\u{30B7}\u{30D3}\u{30EA}\u{30C6}\u{30A3}\u{6A29}\u{9650}\u{304C}\u{3042}\u{308A}\u{307E}\u{305B}\u{3093}\u{3002}\u{30C6}\u{30AD}\u{30B9}\u{30C8}\u{3092}\u{30AF}\u{30EA}\u{30C3}\u{30D7}\u{30DC}\u{30FC}\u{30C9}\u{306B}\u{30B3}\u{30D4}\u{30FC}\u{3057}\u{307E}\u{3057}\u{305F}\u{3002}",
                ru: "\u{041D}\u{0435}\u{0442} \u{0434}\u{043E}\u{0441}\u{0442}\u{0443}\u{043F}\u{0430} \u{043A} \u{0421}\u{043F}\u{0435}\u{0446}\u{0432}\u{043E}\u{0437}\u{043C}\u{043E}\u{0436}\u{043D}\u{043E}\u{0441}\u{0442}\u{044F}\u{043C}. \u{0422}\u{0435}\u{043A}\u{0441}\u{0442} \u{0441}\u{043A}\u{043E}\u{043F}\u{0438}\u{0440}\u{043E}\u{0432}\u{0430}\u{043D} \u{0432} \u{0431}\u{0443}\u{0444}\u{0435}\u{0440} \u{043E}\u{0431}\u{043C}\u{0435}\u{043D}\u{0430}."
            )
            log.error("[Insert] accessibility not trusted; used clipboard fallback")
            return
        }

        log.notice("[Insert] preparing secure text injection; textLength=\(text.count) target=\(targetApp?.bundleIdentifier ?? "nil", privacy: .public)")

        if let app = targetApp, !app.isTerminated {
            let activated = app.activate()
            log.notice("[Insert] activate target app result=\(activated ? "success" : "failed", privacy: .public)")

            var didBecomeFrontmost = false
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    didBecomeFrontmost = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            log.notice("[Insert] target frontmost=\(didBecomeFrontmost ? "yes" : "no", privacy: .public)")
            if !didBecomeFrontmost {
                copyToClipboard(text)
                AppState.shared.error = L10n.ui(
                    for: AppState.shared.selectedLanguage.id,
                    fr: "Impossible de revenir \u{00E0} l'application cible. Le texte a \u{00E9}t\u{00E9} copi\u{00E9} dans le presse-papiers.",
                    en: "Could not focus the target app. The text was copied to the clipboard.",
                    es: "No se pudo enfocar la app de destino. El texto se copi\u{00F3} al portapapeles.",
                    zh: "\u{65E0}\u{6CD5}\u{5207}\u{56DE}\u{76EE}\u{6807}\u{5E94}\u{7528}\u{FF0C}\u{6587}\u{672C}\u{5DF2}\u{590D}\u{5236}\u{5230}\u{526A}\u{8D34}\u{677F}\u{3002}",
                    ja: "\u{5BFE}\u{8C61}\u{30A2}\u{30D7}\u{30EA}\u{306B}\u{623B}\u{308C}\u{306A}\u{304B}\u{3063}\u{305F}\u{305F}\u{3081}\u{3001}\u{30C6}\u{30AD}\u{30B9}\u{30C8}\u{3092}\u{30AF}\u{30EA}\u{30C3}\u{30D7}\u{30DC}\u{30FC}\u{30C9}\u{306B}\u{30B3}\u{30D4}\u{30FC}\u{3057}\u{307E}\u{3057}\u{305F}\u{3002}",
                    ru: "\u{041D}\u{0435} \u{0443}\u{0434}\u{0430}\u{043B}\u{043E}\u{0441}\u{044C} \u{0432}\u{0435}\u{0440}\u{043D}\u{0443}\u{0442}\u{044C} \u{0444}\u{043E}\u{043A}\u{0443}\u{0441} \u{0446}\u{0435}\u{043B}\u{0435}\u{0432}\u{043E}\u{043C}\u{0443} \u{043F}\u{0440}\u{0438}\u{043B}\u{043E}\u{0436}\u{0435}\u{043D}\u{0438}\u{044E}. \u{0422}\u{0435}\u{043A}\u{0441}\u{0442} \u{0441}\u{043A}\u{043E}\u{043F}\u{0438}\u{0440}\u{043E}\u{0432}\u{0430}\u{043D} \u{0432} \u{0431}\u{0443}\u{0444}\u{0435}\u{0440} \u{043E}\u{0431}\u{043C}\u{0435}\u{043D}\u{0430}."
                )
                log.error("[Insert] aborting simulated typing: target app did not become frontmost")
                return
            }
            try? await Task.sleep(for: .milliseconds(140))
        }

        log.notice("[Insert] posting secure typing events")
        simulateTyping(text)
        startCorrectionMonitor(originalText: text)
    }

    func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Correction Learning Monitor

    /// Monitors focused text changes shortly after insertion and proposes dictionary learning
    /// when a single word is replaced by the user.
    func startCorrectionMonitor(originalText: String) {
        guard AXIsProcessTrusted() else { return }
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        correctionMonitorTask?.cancel()
        correctionMonitorTask = Task {
            Self.learningLogger.notice("[DictionaryLearning] monitor started")
            Self.learningLogger.notice("[DictionaryLearning] AX trusted: \(AXIsProcessTrusted() ? "yes" : "no", privacy: .public)")
            let sandboxContainer = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
            Self.learningLogger.notice("[DictionaryLearning] sandbox active: \(sandboxContainer == nil ? "no" : "yes", privacy: .public)")
            if let app = NSWorkspace.shared.frontmostApplication {
                Self.learningLogger.notice("[DictionaryLearning] frontmost app: \(app.bundleIdentifier ?? "unknown", privacy: .public)")
            }

            try? await Task.sleep(for: .milliseconds(800))

            var baseline: String?
            for attempt in 1...6 {
                Self.learningLogger.notice("[DictionaryLearning] baseline attempt \(attempt)")
                let value = await MainActor.run {
                    Self.focusedTextValue(debugLabel: "baseline#\(attempt)", verbose: attempt == 1)
                }
                if let value {
                    baseline = value
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let baseline else {
                Self.learningLogger.notice("[DictionaryLearning] baseline read failed (AX value unavailable)")
                return
            }
            Self.learningLogger.notice("[DictionaryLearning] baseline length: \(baseline.count)")
            var previousValue = baseline
            var consecutiveReadFailures = 0
            let monitorStartedAt = Date()
            var lastTextChangeAt = Date()
            var lastAnalyzedValue: String?
            let stabilizationDelay: TimeInterval = 1.0
            let inactivityTimeout: TimeInterval = 12
            let maxMonitorDuration: TimeInterval = 25
            let monitoredPID = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))

                let now = Date()
                if now.timeIntervalSince(monitorStartedAt) >= maxMonitorDuration {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: max monitor duration reached")
                    return
                }
                if now.timeIntervalSince(lastTextChangeAt) >= inactivityTimeout {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: inactivity timeout")
                    return
                }

                let currentPID = await MainActor.run {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                }
                if let monitoredPID, currentPID != monitoredPID {
                    Self.learningLogger.notice("[DictionaryLearning] stopped: frontmost app changed")
                    return
                }

                let currentValue = await MainActor.run {
                    Self.focusedTextValue(debugLabel: "poll", verbose: false)
                }
                guard let currentValue else {
                    consecutiveReadFailures += 1
                    if consecutiveReadFailures >= 3 {
                        Self.learningLogger.notice("[DictionaryLearning] stopped: repeated AX read failures; collecting verbose diagnostics")
                        _ = await MainActor.run {
                            Self.focusedTextValue(debugLabel: "poll-diagnostics", verbose: true)
                        }
                        return
                    }
                    continue
                }
                consecutiveReadFailures = 0
                if currentValue != previousValue {
                    previousValue = currentValue
                    lastTextChangeAt = Date()
                    lastAnalyzedValue = nil
                    Self.learningLogger.notice("[DictionaryLearning] text changed; waiting for stabilization")
                    continue
                }

                guard now.timeIntervalSince(lastTextChangeAt) >= stabilizationDelay else { continue }
                guard lastAnalyzedValue != currentValue else { continue }
                lastAnalyzedValue = currentValue
                Self.learningLogger.notice("[DictionaryLearning] text stabilized; running replacement detection")

                if let suggestion = Self.detectWordReplacement(from: baseline, to: currentValue) {
                    if Self.containsLearningToken(suggestion.mistakenWord, in: originalText) {
                        Self.learningLogger.notice("[DictionaryLearning] suggestion detected: \(suggestion.mistakenWord, privacy: .private(mask: .hash)) -> \(suggestion.correctedWord, privacy: .private(mask: .hash))")
                        await MainActor.run {
                            AppState.shared.proposeDictionarySuggestion(
                                mistakenWord: suggestion.mistakenWord,
                                correctedWord: suggestion.correctedWord
                            )
                        }
                        return
                    } else {
                        Self.learningLogger.notice("[DictionaryLearning] ignored suggestion: mistaken word not found in original transcription")
                    }
                }
            }
            Self.learningLogger.notice("[DictionaryLearning] stopped: task cancelled")
        }
    }

    // MARK: - Simulated Typing

    private func simulateTyping(_ text: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for scalar in text.unicodeScalars {
            let codeUnit = UniChar(scalar.value)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            var mutable = codeUnit
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &mutable)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - AX Helpers (static)

    static func focusedTextValue(debugLabel: String, verbose: Bool) -> String? {
        guard let focusedElement = focusedElement(verbose: verbose) else {
            if verbose {
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) failed: no focused element")
            }
            return nil
        }

        if verbose {
            let role = stringAttribute(from: focusedElement, attribute: kAXRoleAttribute as CFString) ?? "unknown-role"
            let subrole = stringAttribute(from: focusedElement, attribute: kAXSubroleAttribute as CFString) ?? "unknown-subrole"
            let attributes = attributeNames(of: focusedElement).joined(separator: ",")
            let paramAttributes = parameterizedAttributeNames(of: focusedElement).joined(separator: ",")
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) focused role=\(role, privacy: .public) subrole=\(subrole, privacy: .public)")
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) attrs=[\(attributes, privacy: .public)]")
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) paramAttrs=[\(paramAttributes, privacy: .public)]")
        }

        if let direct = readableText(from: focusedElement, verbose: verbose, debugLabel: "\(debugLabel)-self") {
            return direct
        }

        var current: AXUIElement = focusedElement
        for depth in 1...8 {
            guard let parent = parentElement(of: current) else { break }
            if verbose {
                let role = stringAttribute(from: parent, attribute: kAXRoleAttribute as CFString) ?? "unknown-role"
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) trying parent depth=\(depth) role=\(role, privacy: .public)")
            }
            if let text = readableText(from: parent, verbose: verbose, debugLabel: "\(debugLabel)-parent\(depth)") {
                return text
            }
            current = parent
        }

        if verbose {
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no readable AX text found")
        }
        return nil
    }

    private static func focusedElement(verbose: Bool) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, 1.5)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        if focusResult == .success, let element = focusedElement {
            return axElement(from: element)
        }

        if verbose {
            learningLogger.notice("[DictionaryLearning] AX focus read failed: \(focusResult.rawValue)")
            if focusResult == .cannotComplete {
                learningLogger.notice("[DictionaryLearning] AX cannot complete. In Debug, disable App Sandbox or add accessibility entitlement and re-authorize Zphyr in System Settings > Privacy & Security > Accessibility.")
            }
        }

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 1.5)
            var appFocused: AnyObject?
            let appFocusResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocused
            )
            if appFocusResult == .success, let appFocused {
                if verbose {
                    learningLogger.notice("[DictionaryLearning] AX focus fallback via app succeeded")
                }
                return axElement(from: appFocused)
            }

            if verbose {
                learningLogger.notice("[DictionaryLearning] AX app fallback failed: \(appFocusResult.rawValue)")
            }
        }

        return nil
    }

    private static func stringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }

        if let text = value as? String {
            return text
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return axElement(from: value)
    }

    private static func readableText(from element: AXUIElement, verbose: Bool, debugLabel: String) -> String? {
        if let value = stringAttribute(from: element, attribute: kAXValueAttribute as CFString), !value.isEmpty {
            learningLogger.notice("[DictionaryLearning] AX text source: kAXValueAttribute")
            return value
        } else if verbose {
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXValueAttribute")
        }
        if let selected = stringAttribute(from: element, attribute: kAXSelectedTextAttribute as CFString), !selected.isEmpty {
            learningLogger.notice("[DictionaryLearning] AX text source: kAXSelectedTextAttribute")
            return selected
        } else if verbose {
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXSelectedTextAttribute")
        }
        if let ranged = textFromRangeAPI(element, verbose: verbose, debugLabel: debugLabel), !ranged.isEmpty {
            learningLogger.notice("[DictionaryLearning] AX text source: kAXStringForRangeParameterizedAttribute")
            return ranged
        } else if verbose {
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) no text from kAXStringForRangeParameterizedAttribute")
        }
        return nil
    }

    private static func textFromRangeAPI(_ element: AXUIElement, verbose: Bool, debugLabel: String) -> String? {
        var charCountObject: AnyObject?
        let countResult = AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &charCountObject
        )
        guard countResult == .success else {
            if verbose {
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXNumberOfCharactersAttribute failed: \(countResult.rawValue)")
            }
            return nil
        }

        let charCount: Int
        if let number = charCountObject as? NSNumber {
            charCount = number.intValue
        } else {
            if verbose {
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXNumberOfCharactersAttribute returned non-number")
            }
            return nil
        }
        guard charCount > 0 else {
            if verbose {
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) character count is 0")
            }
            return nil
        }

        var range = CFRange(location: 0, length: min(charCount, 12_000))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var outValue: AnyObject?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &outValue
        )
        guard result == .success else {
            if verbose {
                learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) kAXStringForRangeParameterizedAttribute failed: \(result.rawValue)")
            }
            return nil
        }

        if let text = outValue as? String {
            return text
        }
        if let attributed = outValue as? NSAttributedString {
            return attributed.string
        }
        if verbose {
            learningLogger.notice("[DictionaryLearning] \(debugLabel, privacy: .public) range API returned unsupported value type")
        }
        return nil
    }

    private static func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success, let array = names as? [String] else { return [] }
        return array
    }

    private static func parameterizedAttributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(element, &names)
        guard result == .success, let array = names as? [String] else { return [] }
        return array
    }

    private static func axElement(from value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    // MARK: - Word Replacement Detection

    private nonisolated static func detectWordReplacement(from oldText: String, to newText: String) -> DictionarySuggestion? {
        let oldChars = Array(oldText)
        let newChars = Array(newText)

        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldChars.count - prefix,
              suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        let oldStart = prefix
        let oldEnd = oldChars.count - suffix
        let newStart = prefix
        let newEnd = newChars.count - suffix

        guard oldStart < oldEnd, newStart < newEnd else { return nil }

        let oldSegment = String(oldChars[oldStart..<oldEnd])
        let newSegment = String(newChars[newStart..<newEnd])

        var oldToken = canonicalLearningToken(from: oldSegment)
        var newToken = canonicalLearningToken(from: newSegment)

        if oldToken.isEmpty || newToken.isEmpty {
            if let oldRange = expandedWordRange(in: oldChars, start: oldStart, end: oldEnd),
               let newRange = expandedWordRange(in: newChars, start: newStart, end: newEnd) {
                oldToken = canonicalLearningToken(from: String(oldChars[oldRange]))
                newToken = canonicalLearningToken(from: String(newChars[newRange]))
            }
        }

        guard !oldToken.isEmpty, !newToken.isEmpty else { return nil }
        guard oldToken.caseInsensitiveCompare(newToken) != .orderedSame else { return nil }

        return DictionarySuggestion(mistakenWord: oldToken, correctedWord: newToken)
    }

    private nonisolated static func canonicalLearningToken(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        let tokens = cleaned.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1 else { return "" }
        let token = String(tokens[0]).trimmingCharacters(in: CharacterSet.punctuationCharacters)
        guard token.count >= 2 else { return "" }
        return token
    }

    private nonisolated static func expandedWordRange(
        in chars: [Character],
        start: Int,
        end: Int
    ) -> Range<Int>? {
        guard !chars.isEmpty else { return nil }

        var left = max(0, min(start, chars.count - 1))
        var right = max(0, min(end, chars.count))

        while left > 0 && isWordCharacter(chars[left - 1]) {
            left -= 1
        }
        while right < chars.count && isWordCharacter(chars[right]) {
            right += 1
        }

        guard left < right else { return nil }
        return left..<right
    }

    private nonisolated static func isWordCharacter(_ char: Character) -> Bool {
        if char.isLetter || char.isNumber {
            return true
        }
        return char == "'" || char == "\u{2019}" || char == "-" || char == "_"
    }

    private nonisolated static func containsLearningToken(_ token: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "(^|[^\\p{L}\\p{N}_'\u{2019}-])\(escaped)(?=$|[^\\p{L}\\p{N}_'\u{2019}-])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
