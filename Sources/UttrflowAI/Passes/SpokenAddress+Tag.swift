import UttrflowCore

extension SpokenAddress {
    /// The words that say the numbers joined by "colon" after them are ports.
    static let portCues: Set<String> = ["port", "ports"]

    /// How many words before its first number a port word may stand, as in "forward port three thousand colon three thousand".
    static let portCueReach = 3

    /// Reads an image tag or port pair said with "colon", "postgres:16"; outside a command line only a cued port pair.
    static func readTagged(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        guard position < run.upperBound else { return nil }
        guard expecting.contains(.paths) else {
            return readPortPair(at: position, within: run, in: live, of: draft)
        }
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
        return joined(
            head.text + reference, spanning: position..<(position + head.used + used), in: live, of: draft)
    }

    /// Reads two port numbers joined by "colon" after a port word or straight after an option: "8080:80".
    private static func readPortPair(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        let ports = 1...65_535
        guard let (first, used) = portNumber(at: position, within: run, in: live, of: draft),
            ports.contains(first),
            let (second, step) = colonNumber(at: position + used, within: run, in: live, of: draft),
            ports.contains(second), isPortCued(before: position, in: live, of: draft)
        else { return nil }
        return joined(
            "\(first):\(second)", spanning: position..<(position + used + step), in: live, of: draft)
    }

    /// Whether an option stands straight before `position`, or a port word within reach before it in its sentence.
    private static func isPortCued(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        if position > 0, draft.shape(at: live[position - 1]).isOption { return true }
        var place = position
        while place > max(0, position - portCueReach) {
            place -= 1
            let shape = draft.shape(at: live[place])
            if shape.endsSentence { return false }
            if portCues.contains(shape.key) { return true }
        }
        return false
    }

    /// The words of `span` written as `text`, with the marks its first and last word stood with, where only its ends are marked.
    private static func joined(
        _ text: String, spanning span: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[span.lowerBound])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(length: span.count, text: first.prefix + text + last.suffix)
    }
}
