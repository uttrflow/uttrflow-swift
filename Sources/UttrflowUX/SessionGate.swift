// The rule every way into the app asks first: with no session, nothing opens but sign-in.
public import UttrflowAccount
public import UttrflowCore
public import UttrflowSettings

/// Whether a surface may open, decided from the session alone. See `Docs/entitlements.md`.
public enum SessionGate {
    /// Whether `access` is a session; the one answer that is not is being signed out.
    public static func isSignedIn(_ access: DictationAccess) -> Bool {
        access.permitsDictation
    }

    /// Where a request for `destination` lands: where it asked when signed in, sign-in when not.
    public static func route(_ destination: AppLocation, isSignedIn: Bool) -> AppLocation {
        isSignedIn ? destination : .onboarding
    }

    /// Whether a menu intent may run; signed out, only Quit does and everything else asks for sign-in.
    public static func permits(_ intent: MenuBarIntent, isSignedIn: Bool) -> Bool {
        isSignedIn || intent == .quit
    }

    /// What the menu bar shows while signed out: the mark, a line saying why, Sign In and Quit.
    public static let signedOutMenu: MenuBarPresentation = {
        let line = "Signed out"
        let signIn = MenuBarCommand(title: "Sign In…", intent: .open(.onboarding))
        return MenuBarPresentation(
            icon: .mark,
            statusLine: line,
            emphasis: .normal,
            accessibilityLabel: MenuBarPresenter.spokenForm(of: line),
            header: .status(MenuBarStatus(title: line, action: signIn)),
            buttons: [],
            lastDictation: nil,
            clips: [],
            items: [
                .status(text: line, emphasis: .normal),
                .separator,
                .command(signIn),
                .separator,
                .command(
                    MenuBarCommand(
                        title: "Quit Uttrflow", intent: .quit,
                        shortcut: MenuBarShortcut(key: "q", modifiers: .command))),
            ])
    }()
}

/// What runs in the background for a session and the settings: each is its setting's answer, and none while signed out.
public struct SessionSurfaces: Sendable, Equatable {
    /// Whether the dictation shortcut is listened for.
    public let listensForDictation: Bool
    /// The claimed shortcuts to register, in the registry's order.
    public let claimedShortcuts: [ShortcutAction]
    /// Whether copies are recorded.
    public let watchesTheClipboard: Bool
    /// Whether tab-to-complete runs.
    public let completesWhatIsTyped: Bool
    /// Whether the floating button is on screen.
    public let showsTheFloatingButton: Bool

    /// Decides every surface at once, so no caller can forget the session.
    public init(isSignedIn: Bool, settings: Settings) {
        listensForDictation = isSignedIn && settings.dictationEnabled
        claimedShortcuts = isSignedIn ? ShortcutRegistry.claimed(in: settings).map(\.action) : []
        watchesTheClipboard = isSignedIn && settings.clipboardEnabled
        completesWhatIsTyped = isSignedIn && settings.suggestions.isEnabled
        showsTheFloatingButton = isSignedIn && settings.floatingButtonIsShown
    }
}
