/// The one way keeping the history fails: a refused write; reading never fails, an unreadable file is empty.
public enum HistoryStoreError: UttrflowFailure {
    /// The history file could not be written or removed.
    case couldNotWrite

    /// The one sentence, since saving and clearing fail for the same reason.
    public var userMessage: String {
        "Your dictation history could not be updated on this Mac."
    }

    /// Nothing offered: no recovery a user can take changes whether the disk accepts a write.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking: the words went where they were meant to; only the note of it is lost.
    public var severity: FailureSeverity { .degraded }
}
