// Shortcuts as keycaps, and the recorder that takes a new one without ever accepting a dead one.
public import UttrflowCore

/// How a shortcut is drawn on keycaps.
public enum SettingsShortcut {
    /// One cap per key, modifiers first in the order macOS draws them, since a `Set` has no order.
    public static func keycaps(for binding: HotkeyBinding) -> [String] {
        modifierCaps(for: binding) + [name(of: binding.keyCode)]
    }

    /// The modifier caps alone, in the order macOS draws them.
    static func modifierCaps(for binding: HotkeyBinding) -> [String] {
        modifierOrder.filter(binding.modifiers.contains).map(symbol(for:))
    }

    /// Modifiers as one run of glyphs, for places too narrow for separate caps.
    public static func compact(_ binding: HotkeyBinding) -> String {
        keycaps(for: binding).joined()
    }

    /// Apple's order: control, option, shift, command, reading left to right.
    private static let modifierOrder: [HotkeyModifier] = [.control, .option, .shift, .command]

    /// The glyph for a modifier.
    private static func symbol(for modifier: HotkeyModifier) -> String {
        switch modifier {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    /// The key's name by ANSI position, or its code; on a non-QWERTY layout the letter is QWERTY's.
    static func name(of keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    /// Escape on its own, which cancels recording rather than becoming a shortcut.
    static let escapeKeyCode: UInt16 = 53

    /// Names by ANSI key position.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 25: "9", 26: "7", 28: "8",
        29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        // The modifiers a held binding may be; unnamed, each drew as its raw code, "Key 58" for ⌥.
        54: "⌘", 55: "⌘", 56: "⇧", 57: "Caps Lock", 58: "⌥", 59: "⌃", 60: "⇧", 61: "⌥", 62: "⌃",
        // Held rather than combined: the one key that types nothing and modifies nothing on its own.
        63: "fn",
        64: "F17", 65: "Decimal", 67: "Multiply", 69: "Plus", 71: "Clear", 75: "Divide",
        76: "Enter", 78: "Minus", 79: "F18", 80: "F19", 81: "Equals",
        82: "Numpad 0", 83: "Numpad 1", 84: "Numpad 2", 85: "Numpad 3", 86: "Numpad 4",
        87: "Numpad 5", 88: "Numpad 6", 89: "Numpad 7", 90: "F20", 91: "Numpad 8",
        92: "Numpad 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// What a keystroke did to the recorder.
public enum SettingsShortcutOutcome: Sendable, Equatable {
    /// The field was not listening, so the keystroke belonged to somebody else.
    case ignored
    /// Accepted. The change is the one to hand to ``SettingsEditor``.
    case recorded(SettingsChange)
    /// Refused, with the sentence to show. The shortcut in force is unchanged.
    case refused(SettingsRejection)
    /// The user pressed Escape. Recording stopped, nothing changed.
    case cancelled
}

/// The shortcut field while the user changes it; ``binding`` never becomes one macOS would not deliver.
public struct SettingsShortcutRecorder: Sendable, Equatable {
    /// The shortcut in force. Only ever a deliverable one.
    public private(set) var binding: HotkeyBinding
    /// Whether the field is listening for a keystroke.
    public private(set) var isRecording = false
    /// Why the last attempt was refused, until the next one replaces it.
    public private(set) var rejection: String?

    /// Starts from the shortcut in force; an undeliverable one is replaced by the default.
    public init(binding: HotkeyBinding) {
        self.binding = binding.isDeliverable ? binding : .optionSpace
    }

    /// What the field reads while it waits.
    public var prompt: String {
        isRecording ? "Press the new shortcut" : SettingsShortcut.compact(binding)
    }

    /// Starts listening for a keystroke.
    public mutating func beginRecording() {
        isRecording = true
        rejection = nil
    }

    /// Stops listening, changing nothing.
    public mutating func cancel() {
        isRecording = false
        rejection = nil
    }

    /// Takes a keystroke by positional key code and modifiers, and says what became of it.
    public mutating func record(
        keyCode: UInt16,
        modifiers: Set<HotkeyModifier>
    ) -> SettingsShortcutOutcome {
        guard isRecording else { return .ignored }

        // Escape alone means "leave it", the platform convention; checked before validation.
        if keyCode == SettingsShortcut.escapeKeyCode, modifiers.isEmpty {
            cancel()
            return .cancelled
        }

        let candidate = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
        if let rejection = SettingsEditor.rejection(forShortcut: candidate) {
            self.rejection = rejection.reason
            return .refused(rejection)
        }

        binding = candidate
        isRecording = false
        rejection = nil
        return .recorded(.shortcut(candidate))
    }
}
