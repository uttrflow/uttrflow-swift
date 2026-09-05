internal import UttrflowCore
public import struct Foundation.UUID

/// One snippet firing once.
///
/// Carries the words that were actually said as well as the snippet's own trigger,
/// because they are not the same string and the difference is the whole point: the
/// stored trigger is "my address" and what the user said was "My address.". Telling
/// them the tidy version would be telling them about a phrase they never uttered.
public struct AppliedSnippet: Sendable, Equatable {
    /// Which snippet fired. Not the snippet itself: by the time this is read the store
    /// may have been edited, and a stale copy of the text would be worse than a lookup.
    public let snippetID: UUID
    /// The words in the transcript that were replaced, exactly as they appeared there.
    public let matched: String
    /// What replaced them.
    public let expansion: String

    public init(snippetID: UUID, matched: String, expansion: String) {
        self.snippetID = snippetID
        self.matched = matched
        self.expansion = expansion
    }
}

/// What snippet expansion did to a transcript, and what it did it with.
///
/// A result type rather than a bare `String`, for the reason the corrections layer
/// gives about its own: an app that quietly rewrites what somebody said owes them a way
/// to see it and a way to take it back. ``original`` is that way back — undo is
/// restoring it, with nothing to recompute and nothing to get wrong — and ``applied``
/// is the sentence the interface puts on screen.
public struct SnippetExpansion: Sendable, Equatable {
    /// The transcript as it arrived.
    public let original: String
    /// The transcript as it leaves. Identical to ``original`` when nothing fired.
    public let text: String
    /// Every firing, in the order they appear in ``text``. A snippet that fires twice
    /// appears twice.
    public let applied: [AppliedSnippet]

    public init(original: String, text: String, applied: [AppliedSnippet]) {
        self.original = original
        self.text = text
        self.applied = applied
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> SnippetExpansion {
        SnippetExpansion(original: text, text: text, applied: [])
    }

    /// The snippets that fired, for the store to count. Duplicated per firing, because
    /// a snippet that expanded twice was used twice.
    public var usedSnippetIDs: [UUID] { applied.map(\.snippetID) }
}
