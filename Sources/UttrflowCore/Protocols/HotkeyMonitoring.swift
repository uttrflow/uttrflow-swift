// The shortcut model: bindings, activation styles, hotkey errors and the monitor protocol.

/// A modifier key that can take part in a shortcut.
public enum HotkeyModifier: String, Sendable, Equatable, CaseIterable, Codable {
    case command
    case option
    case control
    case shift
}

/// A key combination the user can press from any app.
public struct HotkeyBinding: Sendable, Equatable, Codable {
    /// Hardware key code, which is positional and so survives a non-QWERTY layout.
    public let keyCode: UInt16
    /// The modifiers held with the key; empty only for a held Fn.
    public let modifiers: Set<HotkeyModifier>

    /// A binding of `keyCode` with `modifiers`.
    public init(keyCode: UInt16, modifiers: Set<HotkeyModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option + Space, the shortcut the product ships with.
    public static let optionSpace = HotkeyBinding(keyCode: 49, modifiers: [.option])

    /// ⇧⌘V, the clipboard panel's default; it shadows "paste without formatting". See `Docs/core-hotkeys.md`.
    public static let shiftCommandV = HotkeyBinding(keyCode: 9, modifiers: [.shift, .command])

    /// ⌃⌘V, which puts the last dictation at the caret without going near the clipboard.
    public static let controlCommandV = HotkeyBinding(keyCode: 9, modifiers: [.control, .command])

    /// ⌃⌘C, the one shortcut whose whole job is to write the clipboard.
    public static let controlCommandC = HotkeyBinding(keyCode: 8, modifiers: [.control, .command])

    /// Hold Fn to dictate; a held binding, watched through flag changes rather than registered as a hot key.
    public static let functionHold = HotkeyBinding(keyCode: functionKeyCode, modifiers: [])

    /// Fn's virtual key code.
    public static let functionKeyCode: UInt16 = 63

    /// This binding as a hold when its key is any modifier, ⌘ alone included; ``isDeliverable`` refuses.
    public var heldModifier: HotkeyBinding? {
        Self.modifierKeyCodes.contains(keyCode) ? self : nil
    }

    /// Whether this is Fn held on its own, which the monitor watches by a flag of its own.
    public var isFunctionHold: Bool {
        keyCode == Self.functionKeyCode && modifiers.isEmpty
    }

    /// Whether the binding has a modifier or is itself a held key; a bare letter would fire while typing.
    public var isUsable: Bool { !modifiers.isEmpty || heldModifier != nil }

    /// Whether the key code and the modifiers agree, since a pair that disagrees fires on the wrong key.
    public var isCoherent: Bool {
        guard Self.modifierKeyCodes.contains(keyCode) else { return true }
        // Fn is named by no modifier, so a combination may not claim it alongside one.
        if keyCode == Self.functionKeyCode { return modifiers.isEmpty }
        // Caps Lock names no modifier, so nothing can ever see it held; it is not bindable.
        guard let named = Self.modifier(ofKeyCode: keyCode) else { return false }
        // Empty means the key alone; a set that omits the key's own modifier came from a key going up.
        return modifiers.isEmpty || modifiers.contains(named)
    }

    /// Whether macOS delivers this shortcut once registered; the monitor's translator keeps the same rules.
    public var isDeliverable: Bool {
        guard isCoherent else { return false }
        // A held modifier is watched, not registered, so the modifier-key-code rule does not apply to it.
        if heldModifier != nil { return true }
        return isUsable && keyCode <= Self.highestKeyCode
            && !Self.modifierKeyCodes.contains(keyCode)
    }

    /// The largest 7-bit virtual key code; anything above it is not from a keyboard.
    static let highestKeyCode: UInt16 = 0x7F

    /// The modifier a key code names, or nil when the key is not a modifier at all.
    public static func modifier(ofKeyCode keyCode: UInt16) -> HotkeyModifier? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        default: nil
        }
    }

    /// The key codes that only modify another key, Caps Lock and Fn included; a binding on one is a hold.
    public static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

/// Why the shortcut cannot be put in place; not a ``PermissionError``, as only one case is about permission.
public enum HotkeyError: UttrflowFailure {
    /// macOS will not let this process observe keys from other apps.
    case observationNotPermitted
    /// The combination cannot be delivered — most often because another app has it.
    case shortcutUnavailable

    /// A plain sentence naming what stands in the way.
    public var userMessage: String {
        switch self {
        case .observationNotPermitted:
            "Accessibility access is required to watch for your shortcut. Turn it on in System Settings."
        case .shortcutUnavailable:
            "That keyboard shortcut isn't available. It's most likely already in use by another app."
        }
    }

    /// The Accessibility pane for a refusal to observe; a retry once whatever holds the combination lets go.
    public var recovery: RecoveryAction? {
        switch self {
        case .observationNotPermitted: .openSystemSettings(.accessibility)
        // Retrying is what helps: quit whatever holds the combination, or choose another, and ask again.
        case .shortcutUnavailable: .retry
        }
    }

    /// Blocking for both: a shortcut that never fires is no dictation at all, so the notice waits to be seen.
    public var severity: FailureSeverity { .blocking }
}

/// How pressing the shortcut starts and stops a dictation.
public enum HotkeyActivation: String, Sendable, Equatable, CaseIterable, Codable {
    /// Hold to speak: down starts, up finishes. What the product ships with.
    case holdToTalk
    /// Press once to start, again to finish. For anyone who dictates long passages.
    case pressToToggle
}

/// What the user did with the shortcut.
public enum HotkeyEvent: Sendable, Equatable {
    /// The shortcut went down.
    case pressed
    /// The shortcut came up.
    case released
}

/// Watches for the shortcut in every app.
public protocol HotkeyMonitoring: Sendable {
    /// Begins watching on the main actor, the only thread with a run loop, and throws if it cannot.
    @MainActor
    func start(binding: HotkeyBinding) throws(HotkeyError)

    /// Stops watching. Safe to call when not started.
    func stop()

    /// Presses and releases, in the order they happened.
    var events: AsyncStream<HotkeyEvent> { get }
}
