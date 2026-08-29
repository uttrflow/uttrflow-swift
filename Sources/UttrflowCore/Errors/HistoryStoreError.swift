/// The one thing that can go wrong when keeping the dictation history: the file
/// would not take the change.
///
/// Here rather than beside the store it comes from, because every other error the
/// product can show lives here — and because ``FailureCatalogue`` is here and cannot
/// reach upwards into a module that depends on it. An error the catalogue cannot see
/// is an error nothing proves has a sentence for the user.
///
/// Reading has no error to report, deliberately. An unreadable history is an empty
/// one, because losing the app to a file somebody mangled is worse than losing the
/// file. Writing is different: the user asked for something to be kept, or to be gone,
/// and only the store knows the disk refused.
///
/// One case rather than one per operation. "Saving failed" and "clearing failed" have
/// the same cause, the same remedy and the same sentence for the user, and splitting
/// them would only invite a second sentence saying the same thing.
public enum HistoryStoreError: UttrflowFailure {
    /// The history file could not be written or removed.
    case couldNotWrite

    public var userMessage: String {
        "Your dictation history could not be updated on this Mac."
    }

    /// Nothing offered. Every recovery Uttrflow knows is something the *user* can do,
    /// and none of them changes whether the disk accepts a write; a Retry button here
    /// would be a button that mostly does not work.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking: the dictation happened and the words went where they
    /// were meant to go. What was lost is the note of it.
    public var severity: FailureSeverity { .degraded }
}
