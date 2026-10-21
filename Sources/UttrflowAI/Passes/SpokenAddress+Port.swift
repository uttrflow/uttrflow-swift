import UttrflowCore

extension SpokenAddress {
    /// A "colon" joined to the word before it and the spoken number after it, and how many words both used.
    static func colonNumber(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (value: Int, used: Int)? {
        guard place > 0, place + 1 < run.upperBound, draft.shape(at: live[place - 1]).suffix.isEmpty,
            draft.shape(at: live[place]).key == "colon"
        else { return nil }
        guard let (value, used) = portNumber(at: place + 1, within: run, in: live, of: draft) else {
            return nil
        }
        return (value, 1 + used)
    }

    /// A number said as a cardinal, as digits one by one, or as two two-digit halves, which are a port or a code: "eight zero eight zero" and "eighty eighty" are 8080.
    static func portNumber(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (value: Int, used: Int)? {
        if let digits = spokenDigits(from: place, within: run, in: live, of: draft), digits.used >= 2,
            digits.text.first != "0", let value = Int(digits.text)
        {
            return (value, digits.used)
        }
        guard let first = number(at: place, within: run, in: live, of: draft) else { return nil }
        return halves(first, at: place, within: run, in: live, of: draft) ?? first
    }

    /// The four digits two spoken numbers from ten to ninety-nine make side by side: "fifty four thirty two" is 5432.
    private static func halves(
        _ first: (value: Int, used: Int), at place: Int, within run: Range<Int>, in live: [Int],
        of draft: Draft
    ) -> (value: Int, used: Int)? {
        let next = place + first.used
        guard (10...99).contains(first.value), next < run.upperBound,
            draft.shape(at: live[next - 1]).suffix.isEmpty, draft.shape(at: live[next]).prefix.isEmpty,
            let second = number(at: next, within: run, in: live, of: draft), (10...99).contains(second.value)
        else { return nil }
        return (first.value * 100 + second.value, first.used + second.used)
    }
}
