// Every change the pipeline makes to what the user said, in a form it can show and undo.
public import struct Foundation.UUID

/// One word Uttrflow replaced, with everything an undo needs on the value. See Docs/pipeline-changes.md.
public struct DictationCorrection: Sendable, Equatable {
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// What was written in its place.
    public let wrote: String
    /// Which spoken words this covered, as indices into the transcript's words.
    public let wordRange: Range<Int>
    /// The dictionary entry that won, which `recordUse(of:)` and `recordRevert(of:)` both take.
    public let entryID: UUID
    /// Why, in the proposing engine's own words; a string because the pipeline must not reinterpret it.
    public let reason: String
    /// What the recogniser scored the replaced words, so a sceptic can see the engine only moved on a guess.
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
    /// Splices every correction in by character range at once, dropping any with a bad or overlapping range.
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

    /// Where each whitespace-separated word begins and ends, the split a correction's range indexes into.
    fileprivate func spokenWordRanges() -> [Range<String.Index>] {
        spokenWords.map { $0.startIndex..<$0.endIndex }
    }
}

/// A transcript after the user's own dictionary has had its say.
public struct CorrectedTranscript: Sendable, Equatable {
    /// The words to carry on with.
    public let text: String
    /// Every change made, in spoken order; empty is the expected and commonest answer.
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
    /// Which snippet fired, as an id, since the store may have changed by the time this is read.
    public let snippetID: UUID
    /// The replaced words exactly as they appeared in the transcript, not the stored trigger.
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

/// Everything Uttrflow changed about what the user said, shown, offered for undo, and learnt from together.
public struct AppliedChanges: Sendable, Equatable {
    public let corrections: [DictationCorrection]
    public let snippets: [SnippetUse]
    /// Words the recogniser heard before any rewrite; the space ``DictationCorrection/wordRange`` indexes.
    public let spokenWords: Int?

    public init(
        corrections: [DictationCorrection] = [], snippets: [SnippetUse] = [],
        spokenWords: Int? = nil
    ) {
        self.corrections = corrections
        self.snippets = snippets
        self.spokenWords = spokenWords
    }

    /// A dictation that comes out exactly as said, which is what every caller gets without asking.
    public static let none = AppliedChanges()

    /// Whether there is anything to show, undo or learn from; read to skip the learner entirely.
    public var isEmpty: Bool { corrections.isEmpty && snippets.isEmpty }
}
