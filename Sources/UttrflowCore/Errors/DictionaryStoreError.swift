/// What the personal dictionary refuses: one disk failure, like `HistoryStoreError`, plus two refusals.
public enum DictionaryStoreError: UttrflowFailure {
    /// The dictionary file could not be written or removed; reading never fails, an unreadable file is empty.
    case couldNotWrite
    /// No word to add; refused before anything is written, since the store, not the page, keeps the file.
    case wordIsEmpty
    /// The word is already known; refused rather than replaced, which would zero its counters and origin.
    case wordAlreadyKnown

    /// A plain sentence per case.
    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your dictionary could not be updated on this Mac."
        case .wordIsEmpty: "Type the word before saving it."
        case .wordAlreadyKnown: "That word is already in your dictionary."
        }
    }

    /// Nothing offered: no recovery a user can take changes whether the disk accepts a write.
    public var recovery: RecoveryAction? { nil }

    /// Degraded for a lost write, as dictation still works; informational for a refusal, as nothing is lost.
    public var severity: FailureSeverity {
        switch self {
        case .couldNotWrite: .degraded
        case .wordIsEmpty, .wordAlreadyKnown: .informational
        }
    }
}
