// The one error the clipboard store can report.

public import UttrflowCore

/// The one thing that can go wrong keeping the clipboard: the file would not take the change.
public enum ClipboardStoreError: UttrflowFailure {
    /// The clipboard file could not be written or removed.
    case couldNotWrite

    public var userMessage: String {
        "Your clipboard history could not be updated on this Mac."
    }

    /// Nothing offered: no recovery the user can perform changes whether the disk accepts a write.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking: the clipboard still works and the panel still opens on what it had.
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
