private import Carbon
internal import CoreGraphics
internal import Foundation

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

    /// Plans `text` one grapheme cluster per keypress, so no event ends inside a ZWJ sequence, flag or combining mark.
    static func keypresses(for text: String, stroke: (UniChar) -> Stroke?) -> [Keypress] {
        text.map { character in
            let units = Array(character.utf16)
            if units.count == 1, let found = stroke(units[0]) { return .key(units[0], found) }
            return .text(units)
        }
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
