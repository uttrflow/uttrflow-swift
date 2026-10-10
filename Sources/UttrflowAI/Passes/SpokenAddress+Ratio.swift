import UttrflowCore

extension SpokenAddress {
    /// The words that say the numbers joined by "colon" beside them are a ratio.
    static let ratioCues: Set<String> = ["ratio", "ratios"]

    /// How many words before its first number a ratio word may stand, as in "a ratio of two colon one".
    static let ratioCueReach = 3

    /// Reads a ratio, two or more spoken or written numbers joined by "colon" beside a ratio word, as digits: "2:1".
    static func readRatio(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard let (first, used) = number(at: position, within: run, in: live, of: draft) else { return nil }
        var terms = [String(first)]
        var end = position + used
        while let (value, step) = colonNumber(at: end, within: run, in: live, of: draft) {
            terms.append(String(value))
            end += step
        }
        let span = position..<end
        guard terms.count > 1, onlyEndsAreMarked(span, in: live, of: draft),
            isRatioCued(before: position, after: end, within: run, in: live, of: draft)
        else { return nil }
        let firstShape = draft.shape(at: live[span.lowerBound])
        let lastShape = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(
            length: span.count, text: firstShape.prefix + terms.joined(separator: ":") + lastShape.suffix)
    }

    /// Whether a ratio word stands within reach before the terms in their sentence, or right after the last.
    private static func isRatioCued(
        before position: Int, after end: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> Bool {
        let lastShape = draft.shape(at: live[end - 1])
        if !lastShape.endsClause, end < run.upperBound, ratioCues.contains(draft.shape(at: live[end]).key) {
            return true
        }
        var place = position
        while place > max(0, position - ratioCueReach) {
            place -= 1
            let shape = draft.shape(at: live[place])
            if shape.endsSentence { return false }
            if ratioCues.contains(shape.key) { return true }
        }
        return false
    }
}
