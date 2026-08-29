public import struct Foundation.UUID

/// Why one word was swapped for another, in terms the person who spoke can check.
///
/// A value rather than a sentence assembled in the view. The Corrections page promises
/// that "nothing here happened without a reason", and a reason written at the point of
/// display is decoration — it can say anything, including something the engine never
/// established. Raw-valued and `Codable` so it survives into the dictation record and
/// still means the same thing a week later.
///
/// The order of the cases is their priority. When several hold at once the first is
/// shown, because it is the one the user can most easily verify with their own eyes.
public enum CorrectionReason: String, Sendable, Equatable, CaseIterable, Codable {
    /// The replacement is written on the screen being dictated into.
    case seenOnScreen
    /// The same word appears elsewhere in this dictation, where it was heard clearly.
    case saidClearlyElsewhere
    /// What was heard was loose letters and the replacement is a word.
    ///
    /// Named from the losing side, because that is the half the user needs to recognise:
    /// the test is that the replacement reads as whole words and what was heard did not.
    case heardAsStrayLetters
    /// What was heard was a run of words and the replacement is one written word — the
    /// "payment sheet" that was meant as `PaymentSheet`. Named from the losing side for
    /// the same reason as the case above.
    case heardAsSeveralWords

    /// The label the Corrections page shows beside the change.
    public var summary: String {
        switch self {
        case .seenOnScreen: "Seen on screen"
        case .saidClearlyElsewhere: "You said it clearly elsewhere"
        case .heardAsStrayLetters: "Heard as stray letters"
        case .heardAsSeveralWords: "Heard as several words"
        }
    }
}

/// One change the engine is willing to argue for, on one run of spoken words.
///
/// Proposed, never applied. The engine has no idea what the user is doing with the
/// dictation and cannot know whether a swap is welcome; the caller does, so the caller
/// decides. Handing back a rewritten string would take that decision away and leave
/// nothing to show on the Corrections page.
///
/// Everything needed to undo the change is on the value itself — the words that were
/// there, where they were, and which entry to blame. An undo that had to reconstruct any
/// of that from the finished text would be guessing, and would guess wrong the moment the
/// same word appears twice.
public struct WordCorrection: Sendable, Equatable {
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// The dictionary spelling proposed in its place.
    public let replacement: String
    /// Which spoken words this covers, as indices into ``Utterance/words``.
    public let wordRange: Range<Int>
    /// The entry that won. `PersonalDictionaryStore.recordRevert(of:)` takes exactly
    /// this, so an undo can be counted against the word that caused it and a word the
    /// user keeps rejecting can retire itself.
    public let entryID: UUID
    public let reason: CorrectionReason
    /// What the recogniser scored the words being replaced, lowest first. Shown so that
    /// a sceptical user can see the engine only ever moved on a guess.
    public let heardConfidence: Double

    public init(
        heard: String, replacement: String, wordRange: Range<Int>, entryID: UUID,
        reason: CorrectionReason, heardConfidence: Double
    ) {
        self.heard = heard
        self.replacement = replacement
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
    }
}

extension WordCorrection {
    /// The words with every correction applied.
    ///
    /// Takes the whole set at once rather than one at a time because a replacement can
    /// be a different number of words from what it replaces — "s q l" becomes "SQL" —
    /// and applying them one by one would invalidate the ranges of the ones not yet done.
    public static func applying(_ corrections: [WordCorrection], to words: [String]) -> [String] {
        spliced(words, corrections.map { (range: $0.wordRange, text: $0.replacement) })
    }

    /// The corrected words with every correction undone, giving back what was heard.
    ///
    /// The inverse of ``applying(_:to:)`` over the same set, which is what makes every
    /// proposal revertable by construction rather than by a separate record of the
    /// original. Ranges are walked in order and shifted by the length each earlier
    /// replacement changed, so the undo lands where the replacement actually went.
    public static func reverting(_ corrections: [WordCorrection], from words: [String]) -> [String] {
        var edits: [(range: Range<Int>, text: String)] = []
        var shift = 0
        for correction in corrections.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let length = tokens(correction.replacement).count
            let start = correction.wordRange.lowerBound + shift
            edits.append((range: start..<(start + length), text: correction.heard))
            shift += length - correction.wordRange.count
        }
        return spliced(words, edits)
    }

    /// Replaces each range with its text, left to right.
    ///
    /// The ranges are required not to overlap — the engine guarantees that — so one
    /// forward pass with a cursor is enough and no index arithmetic is needed.
    private static func spliced(
        _ words: [String], _ edits: [(range: Range<Int>, text: String)]
    ) -> [String] {
        var result: [String] = []
        var cursor = 0
        for edit in edits.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            result.append(contentsOf: words[cursor..<edit.range.lowerBound])
            result.append(contentsOf: tokens(edit.text))
            cursor = edit.range.upperBound
        }
        result.append(contentsOf: words[cursor...])
        return result
    }

    /// Whitespace-separated words, which is the unit both sides of a splice count in.
    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
