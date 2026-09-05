public import struct Foundation.UUID

/// One word Uttrflow replaced, and everything needed to justify it or put it back.
///
/// Restates `UttrflowAI.WordCorrection` field for field rather than reusing it, because
/// this module may see nothing but `UttrflowCore`. That is not an accident of the build
/// graph: the pipeline is the whole product expressed once, and it earns the right to
/// be tested without a model, a microphone or a dictionary by depending on none of
/// them. The restatement is what that costs.
///
/// Everything an undo needs is on the value — the words that were there, where they
/// were, and which entry to blame. An undo that had to find any of that again in the
/// finished text would be guessing, and would guess wrong the first time a word
/// appeared twice.
public struct DictationCorrection: Sendable, Equatable {
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// What was written in its place.
    public let wrote: String
    /// Which spoken words this covered, as indices into the transcript's words.
    public let wordRange: Range<Int>
    /// The dictionary entry that won.
    ///
    /// `PersonalDictionaryStore.recordUse(of:)` and `recordRevert(of:)` both take
    /// exactly this, which is what lets an entry the user keeps rejecting retire itself.
    public let entryID: UUID
    /// Why, in the proposing engine's own words, carried through untouched.
    ///
    /// A string rather than an enumeration because the pipeline did not decide it and
    /// must not reinterpret it. `UttrflowAI.CorrectionReason` is the authority and is
    /// raw-valued for exactly this journey; a copy of its cases here would be a third
    /// list of reasons to keep in step with the other two.
    public let reason: String
    /// What the recogniser scored the words being replaced. Kept so a sceptical user
    /// can be shown that the engine only ever moved on a guess.
    public let heardConfidence: Double

    public init(
        heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID, reason: String,
        heardConfidence: Double
    ) {
        self.heard = heard
        self.wrote = wrote
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
    }
}

extension DictationCorrection {
    /// The transcript with every correction written into it, and the ones that landed.
    ///
    /// Spliced by character range rather than by rebuilding the sentence out of its
    /// words, and that is the whole reason this exists rather than the engine's own
    /// `WordCorrection.applying(_:to:)`. That one takes words and gives words back, and
    /// rejoining words with single spaces is exactly the whitespace collapse that once
    /// flattened a dictated code block onto one line. Everything between the words —
    /// newlines, indentation, the space before a full stop that is not there — is
    /// copied across untouched here.
    ///
    /// The whole set at once, because a replacement can be a different number of words
    /// from what it replaces — "s q l" becomes "SQL" — so applying them one at a time
    /// would invalidate the ranges of the ones not yet done.
    ///
    /// A correction naming words this transcript does not have, or overlapping one
    /// already taken, is dropped rather than trusted, and is left out of what comes
    /// back. The engine cannot produce either, but it reaches this through a protocol,
    /// and a bad range must cost a correction rather than a dictation. Reporting only
    /// what landed is the other half of "nothing is applied silently": a change offered
    /// for undo that was never made would be as dishonest as one made and never shown.
    public static func applying(
        _ corrections: [DictationCorrection], to text: String
    ) -> CorrectedTranscript {
        let words = text.spokenWordRanges()
        var result = ""
        var applied: [DictationCorrection] = []
        var copiedUpTo = text.startIndex

        for correction in corrections.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let wanted = correction.wordRange
            guard wanted.lowerBound >= 0, wanted.upperBound <= words.count, !wanted.isEmpty
            else { continue }
            let span = words[wanted.lowerBound].lowerBound..<words[wanted.upperBound - 1].upperBound
            guard span.lowerBound >= copiedUpTo else { continue }

            result += text[copiedUpTo..<span.lowerBound]
            result += correction.wrote
            applied.append(correction)
            copiedUpTo = span.upperBound
        }
        result += text[copiedUpTo...]
        return CorrectedTranscript(text: result, corrections: applied)
    }
}

extension String {
    /// The whitespace-separated words, which every ``DictationCorrection/wordRange`` indexes into.
    var spokenWords: [Substring] { split(whereSeparator: \.isWhitespace) }

    /// Where each whitespace-separated word of this text begins and ends.
    ///
    /// Whitespace and not runs of letters, because that is how an utterance is counted
    /// into words and a correction's range is an index into those. Splitting the other
    /// way would put "don't" at two indices and silently shift every correction after
    /// it onto the wrong word.
    fileprivate func spokenWordRanges() -> [Range<String.Index>] {
        spokenWords.map { $0.startIndex..<$0.endIndex }
    }
}

/// A transcript after the user's own dictionary has had its say.
public struct CorrectedTranscript: Sendable, Equatable {
    /// The words to carry on with.
    public let text: String
    /// Every change that was made, in the order the words were spoken. Empty is the
    /// expected answer and by far the commonest one.
    public let corrections: [DictationCorrection]

    public init(text: String, corrections: [DictationCorrection] = []) {
        self.text = text
        self.corrections = corrections
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> Self { Self(text: text) }
}

/// One snippet firing once.
public struct SnippetUse: Sendable, Equatable {
    /// Which snippet fired. Not the snippet itself: by the time this is read the store
    /// may have been edited, and a stale copy of the text would be worse than a lookup.
    public let snippetID: UUID
    /// The words in the transcript that were replaced, exactly as they appeared there —
    /// "My address." and not the stored trigger "my address", because the user never
    /// said the stored one.
    public let matched: String
    /// What replaced them.
    public let expansion: String

    public init(snippetID: UUID, matched: String, expansion: String) {
        self.snippetID = snippetID
        self.matched = matched
        self.expansion = expansion
    }
}

/// A transcript after the user's snippets have had theirs.
public struct ExpandedTranscript: Sendable, Equatable {
    /// The text to insert.
    public let text: String
    /// Every firing, in the order they appear. A snippet that fired twice appears twice.
    public let snippets: [SnippetUse]

    public init(text: String, snippets: [SnippetUse] = []) {
        self.text = text
        self.snippets = snippets
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> Self { Self(text: text) }
}

/// Everything Uttrflow changed about what the user actually said.
///
/// One value rather than two lists threaded separately, because everything downstream
/// wants both together: the outcome carries them so the interface can show them and
/// offer the undo, and the same value is what the learner is handed so the words that
/// worked earn their place.
public struct AppliedChanges: Sendable, Equatable {
    public let corrections: [DictationCorrection]
    public let snippets: [SnippetUse]
    /// How many words the recogniser heard, before any of this was done to them.
    ///
    /// Kept rather than counted later, because it cannot be recovered from the finished
    /// text: the dictionary, the snippet expander and the tidier each rewrite the word
    /// count between the two. Substituting the finished count for this one is exactly how
    /// the accuracy figure came to subtract heard words from written ones and report 0%.
    ///
    /// It is also the space ``DictationCorrection/wordRange`` indexes into, which is why
    /// the two travel together.
    public let spokenWords: Int?

    public init(
        corrections: [DictationCorrection] = [], snippets: [SnippetUse] = [],
        spokenWords: Int? = nil
    ) {
        self.corrections = corrections
        self.snippets = snippets
        self.spokenWords = spokenWords
    }

    /// A dictation that came out exactly as it was said. The common case, and the one
    /// every existing caller of the pipeline gets without asking.
    public static let none = AppliedChanges()

    /// Whether there is anything to show, to undo, or to learn from.
    ///
    /// Read on the dictation path to skip the learner entirely, so a user with no
    /// dictionary and no snippets pays nothing at all for having neither.
    public var isEmpty: Bool { corrections.isEmpty && snippets.isEmpty }
}
