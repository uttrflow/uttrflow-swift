/// A failure while placing text into another application.
public enum TextInsertionError: UttrflowFailure {
    case noFocusedTextField
    case accessibilityDenied
    case clipboardUnavailable
    case insertionRejected(description: String)

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

    public var recovery: RecoveryAction? {
        switch self {
        case .noFocusedTextField: .retry
        case .accessibilityDenied: .openSystemSettings(.accessibility)
        // The clipboard is the thing that failed, so telling the user to paste would
        // send them to the one place the words are not. The menu bar kept them.
        case .clipboardUnavailable: .showRecentDictations
        case .insertionRejected: .pasteManually
        }
    }

    public var severity: FailureSeverity {
        switch self {
        // Nothing on screen would take the text this once; the next attempt, with
        // something focused, will.
        case .noFocusedTextField: .recoverable
        // §19's floor held in every one of these: the words exist and the user can
        // reach them, they just did not land where they were aimed.
        case .accessibilityDenied, .clipboardUnavailable, .insertionRejected: .degraded
        }
    }
}
