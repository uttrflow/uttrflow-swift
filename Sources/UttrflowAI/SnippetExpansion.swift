internal import UttrflowCore
public import struct Foundation.UUID

// One snippet firing, and the result of expanding a whole transcript.
/// One snippet firing once, carrying the words said rather than the stored trigger, so undo shows them.
public struct AppliedSnippet: Sendable, Equatable {
    /// Which snippet fired; an ID rather than a copy, since the store may be edited by the time this is read.
    public let snippetID: UUID
    /// The words in the transcript that were replaced, exactly as they appeared there.
    public let matched: String
    /// What replaced them.
    public let expansion: String

    /// Makes the record of one firing.
    public init(snippetID: UUID, matched: String, expansion: String) {
        self.snippetID = snippetID
        self.matched = matched
        self.expansion = expansion
    }
}

/// What expansion did to a transcript; ``original`` is the undo and ``applied`` is what the interface shows.
public struct SnippetExpansion: Sendable, Equatable {
    /// The transcript as it arrived.
    public let original: String
    /// The transcript as it leaves. Identical to ``original`` when nothing fired.
    public let text: String
    /// Every firing in the order it appears in ``text``; a snippet that fires twice appears twice.
    public let applied: [AppliedSnippet]

    /// Makes a result from its parts.
    public init(original: String, text: String, applied: [AppliedSnippet]) {
        self.original = original
        self.text = text
        self.applied = applied
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> SnippetExpansion {
        SnippetExpansion(original: text, text: text, applied: [])
    }

    /// The snippets that fired, once per firing, for the store to count.
    public var usedSnippetIDs: [UUID] { applied.map(\.snippetID) }
}
