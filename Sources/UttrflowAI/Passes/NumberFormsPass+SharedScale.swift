import UttrflowCore

extension NumberFormsPass {
    /// The scale words one scale said after a range can belong to, with the value each multiplies by.
    private static let rangeScales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    /// A range of two numbers where the one scale of the far end belongs to both: "twenty to thirty thousand", or the recogniser's "40 to 50,000".
    static func sharedScaleRange(
        at position: Int, keys: [String], shapes: [WordShape], digits: DigitGrouping
    ) -> Phrase? {
        guard let low = nearEnd(at: position, keys: keys, shapes: shapes), (1...99).contains(low.value) else {
            return nil
        }
        let connective = position + low.count
        let tailStart = connective + 1
        guard tailStart < keys.count, joined(connective, shapes), joined(tailStart, shapes),
            opensRange(at: connective, position: position, keys: keys),
            let high = scaledEnd(at: tailStart, keys: keys, shapes: shapes), low.value < high.mantissa
        else { return nil }
        let end = tailStart + high.count
        let isAmount =
            joined(end, shapes) && (currencies.contains(keys[end]) || measures.contains(keys[end]))
        // Written digit groups keep the recogniser's own grouping on both ends.
        let ends =
            high.written.map { ["\(low.value)\($0)", keys[tailStart]] }
            ?? [low.value * high.scale, high.value].map {
                NumberWords.render($0, grouping: digits, isAmount: isAmount)
            }
        return Phrase(text: "\(ends[0]) \(keys[connective]) \(ends[1])", count: end - position)
    }

    /// The digits the range rule writes from the heard words at `position`, so the integrity audit can tell its rewrite from a lost number.
    static func sharedScaleDigits(at position: Int, heard shapes: [WordShape]) -> String? {
        guard shapes.indices.contains(position) else { return nil }
        return sharedScaleRange(at: position, keys: shapes.map(\.key), shapes: shapes, digits: .thousands)
            .map { $0.text.filter(\.isNumber) }
    }

    /// The near end of a range: a cardinal said in words, or a plain numeral with no grouping.
    private static func nearEnd(
        at index: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, count: Int)? {
        if let said = NumberWords.cardinal(unbroken(from: index, keys: keys, shapes: shapes)) { return said }
        guard keys[index].allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(keys[index]) else {
            return nil
        }
        return (value, 1)
    }

    /// The far end of a range as a mantissa under 100 times one scale: "thirty thousand" said, or "30,000" written in whole groups, with the groups after its lead as written.
    private static func scaledEnd(
        at start: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, mantissa: Int, scale: Int, count: Int, written: String?)? {
        if let said = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            said.count >= 2, let scale = rangeScales[keys[start + said.count - 1]], said.value % scale == 0,
            NumberWords.cardinal(keys[start..<(start + said.count - 1)])?.value == said.value / scale
        {
            return said.value / scale < 100 ? (said.value, said.value / scale, scale, said.count, nil) : nil
        }
        let groups = keys[start].split(separator: ",", omittingEmptySubsequences: false)
        guard (2...4).contains(groups.count), let lead = groups.first, (1...2).contains(lead.count),
            lead.allSatisfy({ $0.isASCII && $0.isNumber }), let mantissa = Int(lead), mantissa > 0,
            groups.dropFirst().allSatisfy({ $0 == "000" })
        else { return nil }
        let scale = groups.dropFirst().reduce(1) { scale, _ in scale * 1_000 }
        return (mantissa * scale, mantissa, scale, 1, String(keys[start].dropFirst(lead.count)))
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
