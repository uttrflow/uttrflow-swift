private import Carbon
internal import CoreGraphics
internal import Foundation
internal import UttrflowCore

/// Finds which key types a character under a keyboard layout. See `Docs/input-synthetic-keystrokes.md`.
enum LayoutKeyCode {
    /// The Carbon modifier state for ⌘ held, which selects a layout's ⌘ table where it has one.
    static let commandHeld = UInt32((cmdKey >> 8) & 0xFF)
    static let shiftHeld = UInt32((shiftKey >> 8) & 0xFF)
    static let optionHeld = UInt32((optionKey >> 8) & 0xFF)

    struct Stroke: Equatable {
        let code: CGKeyCode
        let flags: CGEventFlags
    }

    /// One posted key event: a layout key for its character, or a bare Unicode string the layout has no key for.
    enum Keypress: Equatable {
        case key(UniChar, Stroke)
        case text([UniChar])
    }

    /// What typing does with a control character, which a layout maps to a key such as Return or Tab, never to text.
    enum ControlPolicy: Equatable {
        /// Sent as U+2028 text, which breaks the line without the Return key's send, submit or run.
        case lineBreak
        /// Sent as a space, which keeps the words apart without Tab's move to the next field.
        case space
        /// Refuses the whole text before any key is posted, because the character has no text meaning.
        case refuse
    }

    /// The line separator a line break is typed as; no key binding reads it as a command.
    static let lineSeparator: UniChar = 0x2028

    /// The refusal when the text holds a control character that is neither a line break nor a gap.
    static let controlCharacterRefusal =
        "the text holds a control character that would type as a key, not as text"

    /// The policy for every scalar in U+0000 to U+001F and U+007F; nil for any other scalar.
    static func controlPolicy(for scalar: Unicode.Scalar) -> ControlPolicy? {
        switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D: .lineBreak
        case 0x09: .space
        case 0x00...0x1F, 0x7F: .refuse
        default: nil
        }
    }

    /// Plans `text` one grapheme cluster per keypress, so no event ends inside a ZWJ sequence, flag or combining mark.
    static func keypresses(
        for text: String, stroke: (UniChar) -> Stroke?
    ) throws(TextInsertionError) -> [Keypress] {
        var plan: [Keypress] = []
        plan.reserveCapacity(text.count)
        for character in text {
            // Unicode puts every control in a cluster of its own, CR LF excepted, so the first scalar decides.
            if let first = character.unicodeScalars.first, let policy = controlPolicy(for: first) {
                switch policy {
                case .lineBreak: plan.append(.text([lineSeparator]))
                case .space: plan.append(.text([UniChar(0x20)]))
                case .refuse: throw .insertionRejected(description: controlCharacterRefusal)
                }
                continue
            }
            let units = Array(character.utf16)
            if units.count == 1, let found = stroke(units[0]) {
                plan.append(.key(units[0], found))
            } else {
                plan.append(.text(units))
            }
        }
        return plan
    }

    /// Finds a physical key and modifiers that produce exactly one UTF-16 unit.
    static func stroke(for character: UniChar, in layoutData: Data) -> Stroke? {
        let combinations: [(UInt32, CGEventFlags)] = [
            (0, []),
            (shiftHeld, .maskShift),
            (optionHeld, .maskAlternate),
            (shiftHeld | optionHeld, [.maskShift, .maskAlternate]),
        ]
        for (modifiers, flags) in combinations {
            if let code = code(for: character, in: layoutData, modifiers: modifiers) {
                return Stroke(code: code, flags: flags)
            }
        }
        return nil
    }

    /// The key code that types `character` under `layoutData` with `modifiers` held, or nil if no key on the board does.
    static func code(for character: UniChar, in layoutData: Data, modifiers: UInt32 = 0) -> CGKeyCode? {
        layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in CGKeyCode(0)...CGKeyCode(127) {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == character { return code }
            }
            return nil
        }
    }
}

extension CGEventKeystrokeSender {
    /// The key code the selected layout gives ⌘V, which is how a person's own paste is recognised.
    public static var pasteKeyCode: UInt16 { PasteKeyLayout.vKeyCode() }
}
