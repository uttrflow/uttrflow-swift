public import UttrflowCore

/// The one thing that can go wrong when keeping the clipboard: the file would not take
/// the change.
///
/// Shaped exactly like `HistoryStoreError`, and for the same reasons. Reading has no
/// error to report, deliberately — an unreadable clipboard file is an empty one,
/// because losing the app to a file somebody mangled is worse than losing the file.
/// Writing is different: the user pinned something, or cleared everything, and only the
/// store knows the disk refused.
///
/// One case rather than one per operation. "Saving failed" and "clearing failed" have
/// the same cause, the same remedy and the same sentence for the user.
///
/// > Note: This belongs in `UttrflowCore/Errors` beside every other product error, so
/// > that ``FailureCatalogue`` can see it — the catalogue lives in Core and cannot
/// > reach upwards into a module that depends on it, so an error left here is an error
/// > nothing proves has a sentence for the user. It is written here only because
/// > `UttrflowCore` was outside this change's remit; the move is one file and one line.
public enum ClipboardStoreError: UttrflowFailure {
    /// The clipboard file could not be written or removed.
    case couldNotWrite

    public var userMessage: String {
        "Your clipboard history could not be updated on this Mac."
    }

    /// Nothing offered. Every recovery Uttrflow knows is something the *user* can do, and
    /// none of them changes whether the disk accepts a write; a Retry button here would
    /// be a button that mostly does not work.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking: the clipboard still works and the panel still opens on
    /// what it already had. What was lost is the note of this one change.
    public var severity: FailureSeverity { .degraded }
}

extension ClipboardStoreError: CataloguedFailure {
    public static var firstCase: Self { .couldNotWrite }

    public var caseAfter: Self? {
        switch self {
        case .couldNotWrite: nil
        }
    }
}
