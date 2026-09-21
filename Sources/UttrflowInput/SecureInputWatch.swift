// Notices secure keyboard entry, which hides key presses from the shortcut's event tap. See `Docs/shortcuts.md`.
private import Carbon

/// Whether another app's secure keyboard entry is keeping the shortcut from being heard, checked only when asked.
@MainActor
public final class SecureInputWatch {
    /// What the user is told while the shortcut cannot be heard.
    public static let notice =
        "Another app has turned on secure keyboard entry, so the shortcut can't be heard. "
        + "Turn it off in that app, or start dictation from the menu bar."

    /// The system's own answer, which any process holding secure input turns on for everyone.
    public static let system: @Sendable () -> Bool = { IsSecureEventInputEnabled() }

    private let isSecureInputOn: @Sendable () -> Bool

    /// Whether the last check found secure input on.
    public private(set) var isBlocking = false

    public init(isSecureInputOn: @escaping @Sendable () -> Bool = SecureInputWatch.system) {
        self.isSecureInputOn = isSecureInputOn
    }

    /// Checks once, answering whether the answer changed, so an episode is announced once rather than on every check.
    @discardableResult
    public func check() -> Bool {
        let blocking = isSecureInputOn()
        guard blocking != isBlocking else { return false }
        isBlocking = blocking
        return true
    }
}
