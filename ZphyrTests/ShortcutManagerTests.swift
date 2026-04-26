import AppKit
import Testing
@testable import Zphyr

struct ShortcutManagerTests {
    @Test func triggerKeyLookupPreservesLeftOption() {
        #expect(TriggerKey.from(keyCode: 58) == .leftOption)
        #expect(TriggerKey.from(keyCode: 61) == .rightOption)
    }

    @Test func recordedShortcutRecognizesModifierOnlyShortcut() {
        let leftOption = RecordedShortcut(
            keyCode: 58,
            modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
            displayText: "⌥ Left Option"
        )
        let commandK = RecordedShortcut(
            keyCode: 40,
            modifierRawValue: NSEvent.ModifierFlags.command.rawValue,
            displayText: "⌘K"
        )

        #expect(leftOption.isModifierOnly)
        #expect(!commandK.isModifierOnly)
    }

    @Test func shortcutNormalizationIgnoresIrrelevantModifierFlags() {
        let normalized = ShortcutManager.normalizedModifierFlags([.option, .capsLock, .function])
        #expect(normalized == [.option])
    }
}
