// One keyboard event, and the source that delivers them. See `Docs/shortcuts.md`.

/// What a key did.
public enum KeyPhase: Sendable, Equatable {
    /// A key that types something went down.
    case down
    /// A key that types something came up.
    case up
    /// The modifiers changed, which is the only way a modifier reports itself.
    case modifiersChanged
}

/// One thing the keyboard did, in the only shape the rest of the product reads it in.
public struct KeyStroke: Sendable, Equatable {
    /// Hardware key code, which is positional and so survives a non-QWERTY layout.
    public let keyCode: UInt16
    /// Every modifier down at this instant, Fn included.
    public let modifiers: Set<HotkeyModifier>
    /// Whether Fn is down, which is not a `HotkeyModifier` because no combination may name it.
    public let isFunctionDown: Bool
    public let phase: KeyPhase
    /// Whether the key named here is itself down, which a flags change does not say on its face.
    public let isKeyDown: Bool

    /// Defaults `isKeyDown` to what the phase alone implies, which only a flags change has to state.
    public init(
        keyCode: UInt16, modifiers: Set<HotkeyModifier> = [], isFunctionDown: Bool = false,
        phase: KeyPhase, isKeyDown: Bool? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isFunctionDown = isFunctionDown
        self.phase = phase
        self.isKeyDown = isKeyDown ?? (phase == .down)
    }

    /// Whether nothing is held, which is what a release of the last modifier looks like.
    public var isEmptyHold: Bool { modifiers.isEmpty && !isFunctionDown }
}

/// Delivers every keystroke in every app; the one place that talks to the window server.
public protocol KeyboardEventSource: Sendable {
    /// Starts delivering, or says the system refused, which it does without Accessibility.
    func start(_ deliver: @escaping @Sendable (KeyStroke) -> Void) throws(KeyboardSourceError)
    func stop()
}

/// Why keystrokes cannot be delivered.
public enum KeyboardSourceError: Error, Sendable, Equatable {
    /// The system refused the tap, which it does without the Accessibility grant.
    case refused
}
