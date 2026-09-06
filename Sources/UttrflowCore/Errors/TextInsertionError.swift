/// A failure while placing text into another application.
public enum TextInsertionError: UttrflowFailure {
    /// Nothing on screen accepts text.
    case noFocusedTextField
    /// macOS will not let this process drive other apps.
    case accessibilityDenied
    /// The clipboard itself refused the text.
    case clipboardUnavailable
    /// The focused app refused the text, which is on the clipboard instead.
    case insertionRejected(description: String)

    /// A plain sentence per case, saying where the words are.
    public var userMessage: String {
        switch self {
        case .noFocusedTextField:
            "There's no text field to type into. Click where you want the text, then try again."
        case .accessibilityDenied:
            "Accessibility access is required to insert text into other applications."
        case .clipboardUnavailable:
            "The text couldn't be inserted or copied. It's kept under Recent in the menu bar."
        case .insertionRejected:
            "The text couldn't be inserted here. It's been copied so you can paste it."
        }
    }

    /// Wherever the words are: the clipboard, or Recent when the clipboard is what failed.
    public var recovery: RecoveryAction? {
        switch self {
        case .noFocusedTextField: .retry
        case .accessibilityDenied: .openSystemSettings(.accessibility)
        // The clipboard failed, so "paste" would point at the one place the words are not.
        case .clipboardUnavailable: .showRecentDictations
        case .insertionRejected: .pasteManually
        }
    }

    /// Recoverable when nothing was focused; degraded otherwise, since the words exist and are reachable.
    public var severity: FailureSeverity {
        switch self {
        // Nothing on screen took the text this once; the next attempt, with something focused, does.
        case .noFocusedTextField: .recoverable
        // The words exist and the user can reach them; they only missed where they were aimed.
        case .accessibilityDenied, .clipboardUnavailable, .insertionRejected: .degraded
        }
    }
}
