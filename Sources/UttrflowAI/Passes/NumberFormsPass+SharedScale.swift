import UttrflowCore

extension NumberFormsPass {
    /// The scale words one scale said after a range can belong to, with the value each multiplies by.
    private static let rangeScales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    /// A range of two numbers followed by one scale word, where the one scale belongs to both ends.
    static func sharedScaleRange(
        at position: Int, keys: [String], shapes: [WordShape], digits: DigitGrouping
    ) -> Phrase? {
        guard let low = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)),
            (1...99).contains(low.value)
        else { return nil }
        let connective = position + low.count
        let tailStart = connective + 1
        guard tailStart < keys.count, joined(connective, shapes), joined(tailStart, shapes),
            opensRange(at: connective, position: position, keys: keys),
            let high = NumberWords.cardinal(unbroken(from: tailStart, keys: keys, shapes: shapes)),
            high.count >= 2, let scale = rangeScales[keys[connective + high.count]],
            high.value % scale == 0
        else { return nil }
        let mantissa = high.value / scale
        guard low.value < mantissa, mantissa < 100,
            NumberWords.cardinal(keys[tailStart..<(connective + high.count)])?.value == mantissa
        else { return nil }
        let end = connective + high.count + 1
        let isAmount =
            joined(end, shapes) && (currencies.contains(keys[end]) || measures.contains(keys[end]))
        let ends = [low.value * scale, high.value].map {
            NumberWords.render($0, grouping: digits, isAmount: isAmount)
        }
        return Phrase(text: "\(ends[0]) \(keys[connective]) \(ends[1])", count: end - position)
    }

    /// Whether the word at `connective` joins the two ends of a range: "to", "or", or "and" after "between".
    private static func opensRange(at connective: Int, position: Int, keys: [String]) -> Bool {
        switch keys[connective] {
        case "to", "or": return true
        case "and": return position > 0 && keys[position - 1] == "between"
        default: return false
        }
    }
}
