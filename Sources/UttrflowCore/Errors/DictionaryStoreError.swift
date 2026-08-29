/// The one thing that can go wrong when keeping the personal dictionary: the file would
/// not take the change.
///
/// Deliberately shaped like `HistoryStoreError`, and for the same reasons. Reading has
/// no error to report — an unreadable dictionary is an empty one, because losing the app
/// to a file somebody mangled is worse than losing the file. Writing is different: the
/// user asked for a word to be kept, or to be gone, and only the store knows the disk
/// refused.
///
/// One case for every way the *disk* can refuse: "adding failed" and "resetting failed"
/// have the same cause, the same remedy and the same sentence for the user. ``wordIsEmpty``
/// is separate because it is not a disk failure at all — nothing was attempted, and
/// telling somebody their Mac would not take the change would send them looking in the
/// wrong place. `SnippetStoreError` splits its refusals from its write failure for the
/// same reason.
///
/// It lives here rather than beside the rest of the product's errors in `UttrflowCore`
/// only because `FailureCatalogue` is there and cannot reach upwards into a module that
/// depends on it. The ``CataloguedFailure`` conformance is written anyway, so that
/// registering it is the one line the catalogue's own documentation promises.
public enum DictionaryStoreError: UttrflowFailure {
    /// The dictionary file could not be written or removed.
    case couldNotWrite
    /// There was no word to add.
    ///
    /// Refused before anything is written. The editor will not offer Save for a blank
    /// field, so this only happens when the page and the store disagree — and the store
    /// is the one that has to be right, because it is the one keeping the file.
    case wordIsEmpty
    /// The dictionary already holds that word.
    ///
    /// Refused rather than saved over the top. ``PersonalDictionaryStore/add(_:)``
    /// replaces an entry spelling the same word, and a replacement arrives with its
    /// counters at zero and its origin reset — so a word Uttrflow had learnt, or one the
    /// user had taught it months ago, would silently lose everything known about it.
    ///
    /// The editor refuses this before the button is live, from the list it last drew. It
    /// is checked again here because that list can now go stale *while the editor is
    /// open*: a dictation finishing in another app can teach the dictionary a word
    /// between the page being drawn and Save being pressed.
    case wordAlreadyKnown

    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your dictionary could not be updated on this Mac."
        case .wordIsEmpty: "Type the word before saving it."
        case .wordAlreadyKnown: "That word is already in your dictionary."
        }
    }

    /// Nothing offered, for the reason `HistoryStoreError` gives: every recovery Uttrflow
    /// knows is something the *user* can do, and none of them changes whether the disk
    /// accepts a write.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking. Dictation still works; what was lost is a word it would
    /// have got right next time.
    ///
    /// ``wordIsEmpty`` is only informational — nothing was lost, because nothing was
    /// offered.
    public var severity: FailureSeverity {
        switch self {
        case .couldNotWrite: .degraded
        case .wordIsEmpty, .wordAlreadyKnown: .informational
        }
    }
}
