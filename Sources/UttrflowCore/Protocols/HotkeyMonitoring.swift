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
    public let modifiers: Set<HotkeyModifier>

    public init(keyCode: UInt16, modifiers: Set<HotkeyModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option + Space, the shortcut the product ships with.
    public static let optionSpace = HotkeyBinding(keyCode: 49, modifiers: [.option])

    /// Opens the clipboard panel. ⇧⌘V — the paste key, with a modifier.
    ///
    /// It is not free, and that is a deliberate trade rather than an oversight. Chrome,
    /// Slack, VS Code and most Electron apps bind ⇧⌘V to "paste without formatting"
    /// (macOS's own system binding for that is ⌥⇧⌘V, which stays untouched). A global
    /// hotkey shadows those.
    ///
    /// MEASURED: `RegisterEventHotKey` accepts this combination. It also accepts plain
    /// ⌘V, which is the useful half of that measurement — a successful registration says
    /// only that no other *Carbon* hot key holds the combination, never that the
    /// combination is free. An app's own menu-key handling is invisible to it. So the
    /// shadowing above is not a risk this can be tested for; it is a decision.
    ///
    /// It is still the right key, because what it shadows is replaced by something
    /// strictly better: the panel it opens can paste any clip as plain text with ⌘↩, not
    /// only the most recent one. Anyone who disagrees can rebind it — every shortcut here
    /// is a stored `HotkeyBinding`, not a constant in the code.
    public static let shiftCommandV = HotkeyBinding(keyCode: 9, modifiers: [.shift, .command])

    /// Hold Fn to dictate, the way several dictation apps do.
    ///
    /// Fn is the one key on a Mac keyboard that types nothing and modifies nothing on its
    /// own, which is what makes holding it a usable trigger where holding ⌘ or ⇧ would
    /// fire constantly. It is a *held* binding rather than a combination: the window
    /// server accepts a modifier registered as a hot key and then never fires it, so this
    /// is watched rather than registered — see ``HeldModifierMonitor``.
    public static let functionHold = HotkeyBinding(keyCode: functionKeyCode, modifiers: [])

    /// Fn's virtual key code.
    public static let functionKeyCode: UInt16 = 63

    /// This binding expressed as a hold, if its key is a modifier rather than a character.
    ///
    /// **Any modifier combination, not only Fn.** It was Fn alone for a long time, on the
    /// argument that ⌘, ⌥, ⌃ and ⇧ are pressed dozens of times a minute in ordinary
    /// typing, so a dictation beginning every time somebody reached for ⌘C would be
    /// unusable. That is true — of a *single* modifier. It was then applied to every
    /// modifier-only binding, which swept up ⌃⌥ and ⌘⌥ and the rest: combinations nobody
    /// presses by accident, that other dictation apps offer, and that people ask for.
    ///
    /// So the rule is now about what can be *delivered* rather than what somebody might
    /// regret. ⌘ on its own is allowed here and will indeed fire on ⌘C — that is the
    /// owner of the Mac's business, and refusing to let them choose it was never this
    /// type's decision to make. What is still refused is only what genuinely cannot work:
    /// see ``isDeliverable``.
    ///
    /// Fn is the one whose key code carries no modifier flag of its own, so it is the one
    /// case where ``modifiers`` is legitimately empty.
    public var heldModifier: HotkeyBinding? {
        Self.modifierKeyCodes.contains(keyCode) ? self : nil
    }

    /// Whether this is Fn held on its own, which the monitor watches by a different flag
    /// from the four named modifiers.
    public var isFunctionHold: Bool {
        keyCode == Self.functionKeyCode && modifiers.isEmpty
    }

    /// A binding with no modifier would fire while the user was typing an ordinary
    /// letter, which is why one is required — unless the binding *is* the key being held,
    /// which is what every modifier-only binding is.
    public var isUsable: Bool { !modifiers.isEmpty || heldModifier != nil }

    /// Whether macOS would actually deliver this shortcut once it was registered.
    ///
    /// Three separate ways a binding can be undeliverable, and the window server
    /// refuses none of them: it accepts a shortcut with no modifier, a key code no
    /// keyboard can send, and a modifier held down on its own — and then never fires
    /// any of the three. ``isUsable`` answers only the first, because the monitor's
    /// translator reports the three apart in order to say which one is wrong; this
    /// answers the whole question for callers that need a yes or a no, chiefly the
    /// settings store deciding whether a stored shortcut can be honoured.
    ///
    /// The rules are stated twice, here and in the translator, because this module
    /// cannot import the platform headers the translator names its key codes from.
    /// The two are held to the same answer by a test that compares them.
    public var isDeliverable: Bool {
        // A held modifier is delivered by watching flag changes rather than by
        // registering a hot key, so the rule that rejects modifier key codes — which is
        // about what `RegisterEventHotKey` will fire — does not apply to it.
        if heldModifier != nil { return true }
        return isUsable && keyCode <= Self.highestKeyCode
            && !Self.modifierKeyCodes.contains(keyCode)
    }

    /// Virtual key codes are 7-bit; anything above this came from somewhere other than
    /// a keyboard.
    static let highestKeyCode: UInt16 = 0x7F

    /// The keys that only ever modify another key, left and right of the keyboard, plus
    /// Caps Lock and Fn. Held as codes rather than a range because the range they happen
    /// to occupy is a coincidence of the layout tables.
    ///
    /// A binding whose key code is one of these is a *hold*, watched through flag changes,
    /// rather than a shortcut registered with the window server — which is why they are
    /// excluded from the registered path below and admitted by ``heldModifier`` above.
    ///
    ///   54 ⌘ right · 55 ⌘ left · 56 ⇧ left · 57 Caps Lock · 58 ⌥ left
    ///   59 ⌃ left · 60 ⇧ right · 61 ⌥ right · 62 ⌃ right · 63 Fn
    public static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

/// Why the shortcut could not be put in place.
///
/// Separate from ``PermissionError`` because only one of these two is about permission:
/// a combination another app already owns is refused no matter what the user has
/// granted, and telling them to open System Settings about it would send them somewhere
/// that cannot help.
public enum HotkeyError: UttrflowFailure {
    /// macOS will not let this process observe keys from other apps.
    case observationNotPermitted
    /// The combination cannot be delivered — most often because another app has it.
    case shortcutUnavailable

    public var userMessage: String {
        switch self {
        case .observationNotPermitted:
            "Accessibility access is required to watch for your shortcut. Turn it on in System Settings."
        case .shortcutUnavailable:
            "That keyboard shortcut isn't available. It's most likely already in use by another app."
        }
    }

    public var recovery: RecoveryAction? {
        switch self {
        case .observationNotPermitted: .openSystemSettings(.accessibility)
        // Retrying is the one thing that helps: quit whatever holds the combination, or
        // choose another shortcut once there is a screen for it, and ask again.
        case .shortcutUnavailable: .retry
        }
    }

    /// Both are blocking, and neither looks it from the outside.
    ///
    /// A shortcut that never fires means no dictation at all — there is no second way
    /// into the product. That is true whether macOS refused to let this process watch
    /// keys or another app owns the combination, so the notice has to be the kind that
    /// waits in the menu bar rather than one that dismisses itself while the user is
    /// still pressing a key that does nothing.
    ///
    /// ``observationNotPermitted`` is the case that makes this worth declaring: it asks
    /// for the same Accessibility pane as several genuinely degraded failures, and
    /// anything reading severity off the recovery action put it with them.
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
    case pressed
    case released
}

/// Watches for the shortcut in every app.
public protocol HotkeyMonitoring: Sendable {
    /// Begins watching, and says so if it could not.
    ///
    /// Main-actor isolated because every implementation has to be: a system-wide
    /// shortcut is delivered on the run loop of the thread that asked for it, and the
    /// main thread is the only one this process runs a run loop on. Registering from
    /// an actor's executor instead succeeds and then never fires, which is a failure
    /// nothing can detect afterwards — so the requirement is stated in the type rather
    /// than left to a comment, and callers hop once, here, before asking.
    ///
    /// Whether it worked is known before this returns. A monitor that answered
    /// asynchronously would have nowhere to put a refusal.
    ///
    /// - Throws: ``HotkeyError/observationNotPermitted`` when macOS will not let this
    ///   process observe keys from other apps, and
    ///   ``HotkeyError/shortcutUnavailable`` when this combination cannot be watched
    ///   for — most often because another app already owns it.
    @MainActor
    func start(binding: HotkeyBinding) throws(HotkeyError)

    /// Stops watching. Safe to call when not started.
    func stop()

    /// Presses and releases, in the order they happened.
    var events: AsyncStream<HotkeyEvent> { get }
}
