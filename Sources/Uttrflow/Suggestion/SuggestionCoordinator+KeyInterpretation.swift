import AppKit
import Foundation
import UttrflowCore

extension SuggestionCoordinator {
    /// Whether a key-down may move keyboard focus to another field: Tab, Escape, or any ⌘ shortcut.
    nonisolated static func mayMoveFocus(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let key = Key(keyCode: keyCode)
        return key == .tab || key == .escape || modifiers.contains(.command)
    }

    /// Whether a key with `modifiers` held is the layout's ⌘V, whatever letter the key types without ⌘.
    nonisolated static func isPaste(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, pasteKeyCode: UInt16
    ) -> Bool {
        modifiers.contains(.command) && keyCode == pasteKeyCode
    }

    /// The text a key puts on the line, or nothing for a shortcut, an arrow or any other key that types no text.
    nonisolated static func typedText(characters: String?, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let characters, !characters.isEmpty,
            modifiers.intersection([.command, .control, .option, .function]).isEmpty,
            characters.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            })
        else { return nil }
        return characters
    }

    /// Whether a key ends the line: a Return does, unless an input method was composing, when it confirms a conversion.
    nonisolated static func endsLine(_ key: Key, composing: Bool) -> Bool {
        key == .return && !composing
    }

    /// Advances prose fluency only for a text-producing key-down that is not autorepeat.
    nonisolated static func fluencyTimestamp(
        previous: Date, typing text: String?, isARepeat: Bool, at moment: Date
    ) -> Date {
        guard text != nil, !isARepeat else { return previous }
        return moment
    }
}
