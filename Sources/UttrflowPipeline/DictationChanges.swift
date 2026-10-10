// Every change the pipeline makes to what the user said, in a form it can show and undo.
public import struct Foundation.UUID
public import UttrflowCore

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
    /// Why the proposing engine made the change, carried through unchanged.
    public let reason: CorrectionReason
    /// What the recogniser scored the replaced words, so a sceptic can see the engine only moved on a guess.
    public let heardConfidence: Double
    /// How strongly the gate chose the replacement; `nil` when the user's own spelling settled it.
    public let evidence: OverrideEvidence?
    /// Where the written words begin among the inserted text's words, or `nil` when tidying changed them.
    public let writtenWordIndex: Int?

    public init(
        heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID, reason: CorrectionReason,
        heardConfidence: Double, evidence: OverrideEvidence? = nil, writtenWordIndex: Int? = nil
    ) {
        self.heard = heard
        self.wrote = wrote
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
        self.evidence = evidence
        self.writtenWordIndex = writtenWordIndex
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

            // The recogniser hangs punctuation on the word, so only the word inside the token is replaced.
            let opening = SpokenToken(text[words[wanted.lowerBound]]).leading
            let closing = SpokenToken(text[words[wanted.upperBound - 1]]).trailing
            let written = String(opening) + correction.wrote + closing

            result += text[copiedUpTo..<span.lowerBound]
            result += written
            // An undo looks for what was written, punctuation and all, not for what was proposed.
            applied.append(correction.written(as: written))
            copiedUpTo = span.upperBound
        }
        result += text[copiedUpTo...]
        return CorrectedTranscript(text: result, corrections: applied)
    }

    /// A copy naming exactly what was written in the transcript, which is what an undo has to match.
    private func written(as text: String) -> Self {
        Self(
            heard: heard, wrote: text, wordRange: wordRange, entryID: entryID, reason: reason,
            heardConfidence: heardConfidence, evidence: evidence)
    }

    /// Each correction with where its words landed in `finished`, aligned from `corrected`. See `Docs/core-history-undo.md`.
    public static func locating(
        _ corrections: [DictationCorrection], from corrected: String, in finished: String
    ) -> [DictationCorrection] {
        // Where each corrected word landed in the finished text, or `nil` when tidying changed it.
        let landed = WordErrorRate.measure(
            reference: corrected.spokenWords.map(Self.alignmentKey),
            hypothesis: finished.spokenWords.map(Self.alignmentKey)
        ).matchedColumns

        var shift = 0
        var located: [DictationCorrection] = []
        for correction in corrections.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let count = correction.wrote.spokenWords.count
            let start = correction.wordRange.lowerBound + shift
            shift += count - correction.wordRange.count
            located.append(correction.landing(at: Self.run(of: count, from: start, in: landed)))
        }
        return located
    }

    /// Where `count` corrected words from `start` landed side by side, or `nil` when any of them moved apart.
    private static func run(of count: Int, from start: Int, in landed: [Int?]) -> Int? {
        guard count > 0, start >= 0, start + count <= landed.count, let first = landed[start]
        else { return nil }
        for offset in 1..<count where landed[start + offset] != first + offset { return nil }
        return first
    }

    /// A word as the alignment compares it: tidying capitalises and punctuates without changing the word.
    private static func alignmentKey(_ word: Substring) -> String {
        SpokenToken(word).scoreKey
    }

    /// A copy that knows where its words sit in the inserted text.
    private func landing(at index: Int?) -> Self {
        Self(
            heard: heard, wrote: wrote, wordRange: wordRange, entryID: entryID, reason: reason,
            heardConfidence: heardConfidence, evidence: evidence, writtenWordIndex: index)
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

/// One spoken token with the punctuation the recogniser attached to it held apart from the word itself.
struct SpokenToken {
    /// The punctuation before the word: an opening quote or bracket. A word with none is the usual case.
    let leading: Substring
    /// The word itself, empty when the token is punctuation through and through and so names no word.
    let core: Substring
    /// The punctuation after the word: a comma, a full stop, a question mark.
    let trailing: Substring

    init(_ token: Substring) {
        var start = token.startIndex
        var end = token.endIndex
        while start < end, token[start].isPunctuation { token.formIndex(after: &start) }
        while end > start, token[token.index(before: end)].isPunctuation {
            token.formIndex(before: &end)
        }
        leading = token[..<start]
        core = token[start..<end]
        trailing = token[end...]
    }

    init(_ token: String) { self.init(token[...]) }

    /// How both sides of a score lookup name this word: the word alone, lower-cased, empty for punctuation.
    var scoreKey: String { core.lowercased() }
}

/// A transcript after the user's own dictionary has had its say.
public struct CorrectedTranscript: Sendable, Equatable {
    /// The words to carry on with.
    public let text: String
    /// Every change made, in spoken order; empty is the expected and commonest answer.
    public let corrections: [DictationCorrection]
    /// Heard-word ranges the corrector weighed a reading for and kept, so no later layer reopens them.
    public let held: [Range<Int>]

    public init(text: String, corrections: [DictationCorrection] = [], held: [Range<Int>] = []) {
        self.text = text
        self.corrections = corrections
        self.held = held
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> Self { Self(text: text) }

    /// The same transcript with these runs held as heard, bar any a correction changed.
    func holding(_ ranges: [Range<Int>]) -> Self {
        let kept = ranges.filter { range in !corrections.contains { $0.wordRange.overlaps(range) } }
        return Self(text: text, corrections: corrections, held: held + kept)
    }
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
    /// UTF-16 units of ``text`` before where a snippet asked the caret to end, or `nil` to leave it at the end.
    public let caret: Int?

    public init(text: String, snippets: [SnippetUse] = [], caret: Int? = nil) {
        self.text = text
        self.snippets = snippets
        self.caret = caret.flatMap { (0...text.utf16.count).contains($0) ? $0 : nil }
    }

    /// A transcript nothing was done to.
    public static func unchanged(_ text: String) -> Self { Self(text: text) }

    /// How far the caret moves back from the end of the inserted text, in UTF-16 units; 0 leaves it there.
    public var caretBackFromEnd: Int { caret.map { text.utf16.count - $0 } ?? 0 }

    /// How far back from the end of `written` a snippet's caret goes, matching the words after it up to case and padding.
    public func caretBack(inWritten written: String) -> Int? {
        guard let caret, let tailText = String(text.utf16.dropFirst(caret)) else { return nil }
        let tail = Array(tailText)
        let core = tail[..<(tail.lastIndex { !$0.isWhitespace }.map { $0 + 1 } ?? 0)]
        let chars = Array(written)
        let writtenEnd = chars.lastIndex { !$0.isWhitespace }.map { $0 + 1 } ?? 0
        guard writtenEnd >= core.count else { return nil }
        let start = writtenEnd - core.count
        guard chars[start..<writtenEnd].elementsEqual(core, by: { $0.lowercased() == $1.lowercased() })
        else { return nil }
        return String(chars[start...]).utf16.count
    }

    /// The same transcript with every line break a space, as a single-line field wants, firings included.
    public var onOneLine: Self {
        Self(
            text: Self.joiningLines(text),
            snippets: snippets.map {
                SnippetUse(
                    snippetID: $0.snippetID, matched: $0.matched,
                    expansion: Self.joiningLines($0.expansion))
            },
            caret: caret.map { caret in
                // The lines before the caret are joined the way the whole text is, so it keeps its word.
                guard text.contains(where: \.isNewline) else { return caret }
                return Self.joinedLines(Self.prefix(of: text, units: caret)).utf16.count
            })
    }

    /// The first `units` UTF-16 units of `text`, rounded down to a whole character.
    static func prefix(of text: String, units: Int) -> String {
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: units)
        return String(text[..<index])
    }

    /// The lines of `text` joined by one space, each trimmed, a blank line dropped.
    static func joiningLines(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        return joinedLines(text)
    }

    /// Every line of `text` trimmed, blank ones dropped, the rest joined by one space.
    private static func joinedLines(_ text: String) -> String {
        WordTokens.words(text, .line)
            .map { line in
                String(line.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// The dictionary corrections and snippet firings shown, offered for undo, and learnt from together.
public struct AppliedChanges: Sendable, Equatable {
    public let corrections: [DictationCorrection]
    public let snippets: [SnippetUse]
    /// Dictionary entries whose spelling the tidier wrote for a doubtful run: counted used like a correction's, not yet undoable.
    public let entriesTaken: [UUID]
    /// Words the recogniser heard before any rewrite; the space ``DictationCorrection/wordRange`` indexes.
    public let spokenWords: Int?
    /// Where the rules passes changed the written words; nil when unlocated, as on the model path.
    public let changeLedger: [ChangeLedgerEntry]?
    /// Words script enforcement wrote in Latin letters: romanised from Devanagari or transliterated from another script.
    public let scriptConversions: ScriptConversions
    /// The recogniser's words before any correction or tidying; nil when not carried.
    public let heard: String?

    public init(
        corrections: [DictationCorrection] = [], snippets: [SnippetUse] = [],
        entriesTaken: [UUID] = [], spokenWords: Int? = nil, changeLedger: [ChangeLedgerEntry]? = nil,
        scriptConversions: ScriptConversions = .none, heard: String? = nil
    ) {
        self.corrections = corrections
        self.snippets = snippets
        self.entriesTaken = entriesTaken
        self.spokenWords = spokenWords
        self.changeLedger = changeLedger
        self.scriptConversions = scriptConversions
        self.heard = heard
    }

    /// A dictation that comes out exactly as said, which is what every caller gets without asking.
    public static let none = AppliedChanges()

    /// Whether there is anything to show, undo or learn from; read to skip the learner entirely.
    public var isEmpty: Bool { corrections.isEmpty && snippets.isEmpty && entriesTaken.isEmpty }
}

/// How many written words each script conversion produced, summed over every enforcement a dictation passed; no text.
public struct ScriptConversions: Sendable, Equatable {
    public let wordsRomanised: Int
    public let wordsTransliterated: Int

    public init(wordsRomanised: Int = 0, wordsTransliterated: Int = 0) {
        self.wordsRomanised = wordsRomanised
        self.wordsTransliterated = wordsTransliterated
    }

    /// The counts one enforcement reported.
    public init(_ enforcement: ScriptEnforcement) {
        self.init(
            wordsRomanised: enforcement.wordsRomanised, wordsTransliterated: enforcement.wordsTransliterated)
    }

    public static let none = ScriptConversions()

    /// Every word written by a conversion rather than heard.
    public var words: Int { wordsRomanised + wordsTransliterated }

    /// Both enforcements' counts together.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            wordsRomanised: lhs.wordsRomanised + rhs.wordsRomanised,
            wordsTransliterated: lhs.wordsTransliterated + rhs.wordsTransliterated)
    }
}
