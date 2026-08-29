/// What can stop a snippet being kept.
///
/// Shaped like `DictionaryStoreError`, with one deliberate addition: that store only
/// ever fails because the disk refused, whereas this one also has to be able to say no
/// to the editor. A snippet with no trigger, or no text, or a trigger another snippet
/// already owns, is a snippet that could never fire — and saving it happily would put a
/// row on screen that does nothing and never says why. This product's rule is that
/// nothing it does is invisible, and refusing out loud is the version of that rule that
/// applies before anything has been written.
///
/// Reading still has no error, for the reason the other stores give: a file somebody
/// mangled must cost them their snippets and not their app.
///
/// It lives in `UttrflowAI` beside the store rather than in `UttrflowCore` with the
/// product's other errors, because the store is here. The ``CataloguedFailure``
/// conformance is written anyway, so that adding it to `FailureCatalogue` is the single
/// line that file's own documentation promises.
public enum SnippetStoreError: UttrflowFailure {
    /// The snippets file could not be written or removed.
    case couldNotWrite
    /// The trigger had no words in it — punctuation, or nothing at all.
    case triggerHasNoWords
    /// Another snippet already answers to that trigger.
    case triggerAlreadyUsed
    /// There was no text to expand to.
    case expansionIsEmpty

    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your snippets could not be updated on this Mac."
        case .triggerHasNoWords: "A snippet needs a trigger you can say out loud."
        case .triggerAlreadyUsed: "Another snippet already uses that trigger."
        case .expansionIsEmpty: "A snippet needs some text to expand to."
        }
    }

    /// Nothing offered. The disk refusing is not something the user can act on, and the
    /// other three are already being said next to the field that is wrong, which is a
    /// better place to fix them than a button.
    public var recovery: RecoveryAction? { nil }

    public var severity: FailureSeverity {
        switch self {
        // Dictation still works; what was lost is a shortcut for next time.
        case .couldNotWrite: .degraded
        // Nothing went wrong. The editor asked, and this is the answer.
        case .triggerHasNoWords, .triggerAlreadyUsed, .expansionIsEmpty: .informational
        }
    }
}
