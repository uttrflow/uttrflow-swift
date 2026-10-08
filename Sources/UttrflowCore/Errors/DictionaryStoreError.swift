/// What the personal dictionary refuses: storage failures and invalid words.
public enum DictionaryStoreError: UttrflowFailure {
    /// The dictionary file could not be written or removed.
    case couldNotWrite
    /// The seed marker is present but cannot be read; seeding must not undo a deleted shipped word.
    case couldNotReadSeedRecord
    /// No word to add; refused before anything is written, since the store, not the page, keeps the file.
    case wordIsEmpty
    /// The word is already known; refused rather than replaced, which would zero its counters and origin.
    case wordAlreadyKnown
    /// The spelling or pronunciation exceeds the lookup's bounded spoken span.
    case entryHasTooManyWords(maximum: Int)
    /// The spelling is longer than the recogniser prompt can ever hold, so it would be listed but never offered.
    case entryIsTooLong(maximum: Int)

    /// A plain sentence per case.
    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your dictionary could not be updated on this Mac."
        case .couldNotReadSeedRecord: "Your dictionary's setup record could not be read on this Mac."
        case .wordIsEmpty: "Type the word before saving it."
        case .wordAlreadyKnown: "That word is already in your dictionary."
        case .entryHasTooManyWords(let maximum):
            "The spelling and pronunciation can each have at most \(maximum) words."
        case .entryIsTooLong(let maximum):
            "The spelling can have at most \(maximum) characters."
        }
    }

    /// Nothing offered: no recovery a user can take changes whether the disk accepts a write.
    public var recovery: RecoveryAction? { nil }

    /// Degraded for a lost write, as dictation still works; informational for a refusal, as nothing is lost.
    public var severity: FailureSeverity {
        switch self {
        case .couldNotWrite, .couldNotReadSeedRecord: .degraded
        case .wordIsEmpty, .wordAlreadyKnown, .entryHasTooManyWords, .entryIsTooLong: .informational
        }
    }
}
