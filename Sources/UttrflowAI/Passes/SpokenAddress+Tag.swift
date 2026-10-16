import UttrflowCore

extension SpokenAddress {
    /// Reads a name or number and the numbers its spoken "colon" gives it at a command line: an image tag or a port pair, "postgres:16" and "8000:8000".
    static func readTagged(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        guard expecting.contains(.paths), position < run.upperBound else { return nil }
        let head: (text: String, used: Int)
        if let (value, used) = portNumber(at: position, within: run, in: live, of: draft) {
            head = (String(value), used)
        } else if let name = part(from: position, within: run, in: live, of: draft),
            name.hasLetter, FunctionWords.isContent(name.labels[0].lowercased()),
            !NumberWords.isNumber(name.labels[0].lowercased())
        {
            head = (name.spelled, name.length)
        } else {
            return nil
        }
        let (reference, used) = readReference(at: position + head.used, within: run, in: live, of: draft)
        guard used > 0 else { return nil }
        let span = position..<(position + head.used + used)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(length: span.count, text: first.prefix + head.text + reference + last.suffix)
    }
}
