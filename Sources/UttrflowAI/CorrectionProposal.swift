// A proposed word correction, its reason, and how a set of them is applied and reverted.
public import struct Foundation.UUID
public import UttrflowCore

/// One proposed, never applied, change to a run of spoken words, carrying everything an undo needs.
public struct WordCorrection: Sendable, Equatable {
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// The dictionary spelling proposed in its place.
    public let replacement: String
    /// Which spoken words this covers, as indices into ``Utterance/words``.
    public let wordRange: Range<Int>
    /// The entry that won, so `PersonalDictionaryStore.recordRevert(of:)` can count an undo against it.
    public let entryID: UUID
    /// Why the replacement won.
    public let reason: CorrectionReason
    /// The lowest recogniser score among the replaced words, shown so the change is visibly a guess.
    public let heardConfidence: Double
    /// How strongly the gate chose the replacement; `nil` when the user's own spelling settled it.
    public let evidence: OverrideEvidence?

    /// Makes a proposal from its parts.
    public init(
        heard: String, replacement: String, wordRange: Range<Int>, entryID: UUID,
        reason: CorrectionReason, heardConfidence: Double, evidence: OverrideEvidence? = nil
    ) {
        self.heard = heard
        self.replacement = replacement
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
        self.evidence = evidence
    }
}

extension WordCorrection {
    /// The words with every correction applied at once, since a replacement can change the word count.
    public static func applying(_ corrections: [WordCorrection], to words: [String]) -> [String] {
        spliced(words, corrections.map { (range: $0.wordRange, text: $0.replacement) })
    }

    /// The inverse of ``applying(_:to:)``: undoes every correction, shifting each range by earlier changes.
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

    /// Replaces each range with its text in one forward pass; the ranges must not overlap.
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
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
