/// What stops a snippet being kept: the disk refusing, or the editor told no before anything is written.
public enum SnippetStoreError: UttrflowFailure {
    /// The snippets file could not be written or removed; reading never fails, an unreadable file is empty.
    case couldNotWrite
    /// The trigger has no words in it: punctuation, or nothing at all.
    case triggerHasNoWords
    /// Another snippet already answers to that trigger.
    case triggerAlreadyUsed
    /// There is no text to expand to.
    case expansionIsEmpty

    /// A plain sentence per case.
    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your snippets could not be updated on this Mac."
        case .triggerHasNoWords: "A snippet needs a trigger you can say out loud."
        case .triggerAlreadyUsed: "Another snippet already uses that trigger."
        case .expansionIsEmpty: "A snippet needs some text to expand to."
        }
    }

    /// Nothing offered: the disk is beyond the user, and each refusal is already said beside the wrong field.
    public var recovery: RecoveryAction? { nil }

    /// Degraded for a lost write, informational for a refusal.
    public var severity: FailureSeverity {
        switch self {
        // Dictation still works; what was lost is a shortcut for next time.
        case .couldNotWrite: .degraded
        // Nothing went wrong. The editor asked, and this is the answer.
        case .triggerHasNoWords, .triggerAlreadyUsed, .expansionIsEmpty: .informational
        }
    }
}
