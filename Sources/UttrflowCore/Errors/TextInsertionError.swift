/// A failure while placing text into another application.
public enum TextInsertionError: UttrflowFailure {
    /// Nothing on screen accepts text.
    case noFocusedTextField
    /// macOS will not let this process drive other apps.
    case accessibilityDenied
    /// The clipboard itself refused the text.
    case clipboardUnavailable
    /// Another process replaced the clipboard during insertion, so its newer contents are preserved.
    case clipboardChanged
    /// The insertion deadline passed before any delivery result was confirmed.
    case insertionTimedOut
    /// The focused app refused the text, which is on the clipboard instead.
    case insertionRejected(description: String)
    /// Cancellation stopped insertion before it completed.
    case insertionCancelled
    /// Accessibility accepted a write but its delayed result could not be distinguished from refusal.
    case insertionUnconfirmed
    /// The application in front changed after the destination was captured.
    case insertionTargetChanged
    /// The window holding the field the context was read from closed before the write.
    case insertionFieldClosed
    /// Clipboard-free insertion refused, so the user may copy the retained transcript explicitly.
    case insertionNeedsCopy(description: String)
    /// Typing stopped partway, so only the first `typed` of `total` characters reached the field.
    case insertionInterrupted(typed: Int, total: Int)

    /// A plain sentence per case, saying where the words are.
    public var userMessage: String {
        switch self {
        case .noFocusedTextField:
            "There's no text field to type into. Your dictation is saved in History."
        case .accessibilityDenied:
            "Accessibility access is required to insert text into other applications."
        case .clipboardUnavailable:
            "The text couldn't be inserted or copied. It's kept in History."
        case .clipboardChanged:
            "Your clipboard changed during insertion. Your dictation is saved in History."
        case .insertionTimedOut:
            "Your dictation didn't arrive in time. It's saved in History."
        case .insertionRejected:
            "The text couldn't be inserted here. It's been copied, so press ⌘V to paste it."
        case .insertionCancelled:
            "Insertion was cancelled. The text is saved in History."
        case .insertionUnconfirmed:
            "The app hasn't confirmed whether the text was inserted. Check the field before trying again."
        case .insertionTargetChanged:
            "The app in front changed. Focus the intended field and try again."
        case .insertionFieldClosed:
            "The field you dictated into closed. Your dictation is saved in History."
        case .insertionNeedsCopy:
            "The text couldn't be inserted. Your clipboard is unchanged."
        case .insertionInterrupted(let typed, let total):
            "Typing stopped after \(typed) of \(total) characters. Your dictation is saved under Recent in the menu bar."
        }
    }

    /// Wherever the words are: the clipboard, or History when the clipboard is what failed.
    public var recovery: RecoveryAction? {
        switch self {
        case .noFocusedTextField: .showHistory
        case .accessibilityDenied: .openSystemSettings(.accessibility)
        // The clipboard failed, so "paste" would point at the one place the words are not.
        case .clipboardUnavailable: .showHistory
        case .clipboardChanged: .showHistory
        case .insertionTimedOut: .showHistory
        case .insertionTargetChanged: .showHistory
        case .insertionFieldClosed: .showHistory
        case .insertionRejected: .pasteManually
        case .insertionCancelled: nil
        case .insertionUnconfirmed: .showHistory
        case .insertionNeedsCopy: .copyTranscript
        case .insertionInterrupted: .showHistory
        }
    }

    /// Recoverable when nothing was focused; degraded otherwise, since the words exist and are reachable.
    public var severity: FailureSeverity {
        switch self {
        // Nothing on screen took the text this once; the next attempt, with something focused, does.
        case .noFocusedTextField: .recoverable
        // The words exist and the user can reach them; they only missed where they were aimed.
        case .accessibilityDenied, .clipboardUnavailable, .clipboardChanged, .insertionTimedOut,
            .insertionRejected,
            .insertionUnconfirmed, .insertionTargetChanged, .insertionFieldClosed, .insertionNeedsCopy,
            .insertionInterrupted:
            .degraded
        case .insertionCancelled: .informational
        }
    }

    /// Whether another route must not attempt the same insertion.
    public var stopsFallback: Bool {
        switch self {
        // Part of the text is already in the field, so another route would type it twice.
        case .insertionUnconfirmed, .insertionTargetChanged, .insertionFieldClosed, .clipboardChanged,
            .insertionInterrupted, .insertionCancelled:
            true
        default: false
        }
    }
}
