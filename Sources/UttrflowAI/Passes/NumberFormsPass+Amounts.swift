import UttrflowCore

/// Amounts: a currency word becomes its symbol, a hundred with a tail is one number, and a magnitude word stays.
extension NumberFormsPass {
    /// The coordinators that join the two ends of a range of amounts.
    static let rangeJoiners = coordinators.subtracting(["by", "versus", "vs"])

    /// Words that name a currency and something else, so they keep their word: a pound also weighs.
    static let alsoMeasures: Set<String> = ["pound", "pounds"]

    /// The symbol written before an amount of this currency word, if it names one currency only and the symbol is ASCII, since the output is Latin script only.
    static func symbol(forCurrencyWord word: String) -> String? {
        guard !alsoMeasures.contains(word), let symbol = Quantities.currencyWords[word],
            symbol.allSatisfy(\.isASCII)
        else { return nil }
        return symbol
    }

    /// Writes "5 dollars" as "$5": the numeral takes the symbol and the currency word goes.
    static func writeSymbols(in draft: inout Draft) {
        let present = draft.presentIndices
        for index in present {
            // A major amount and its minor part are written as one word, "2.50 dollars".
            let shape = draft.shape(at: index)
            let parts = shape.core.split(separator: " ").map(String.init)
            if parts.count == 2, let symbol = symbol(forCurrencyWord: parts[1].lowercased()),
                isNumeral(parts[0])
            {
                draft.replace(at: index, with: shape.prefix + symbol + parts[0] + shape.suffix, by: id)
            }
        }
        for unit in draft.presentIndices {
            let word = draft.shape(at: unit)
            guard draft.words[unit].isPresent, let symbol = symbol(forCurrencyWord: word.key),
                word.prefix.isEmpty, let amount = amountIndex(before: unit, in: draft),
                !hasMinorPart(after: unit, in: draft)
            else { continue }
            let number = draft.shape(at: amount)
            draft.replace(at: amount, with: number.prefix + symbol + number.core + word.suffix, by: id)
            draft.remove(at: unit, by: id)
            // "between 500 and 600 dollars" names both amounts in the currency.
            let before = draft.presentIndices.filter { $0 < amount }.suffix(2)
            if before.count == 2, let first = before.first, let joiner = before.last,
                rangeJoiners.contains(draft.shape(at: joiner).key)
            {
                let earlier = draft.shape(at: first)
                if !earlier.prefix.contains(symbol), isAmount(core: earlier.core, suffix: earlier.suffix) {
                    draft.replace(at: first, with: earlier.prefix + symbol + earlier.core, by: id)
                }
            }
        }
    }

    /// The numeral a currency word names: the word before it, when that is a numeral.
    static func amountIndex(before unit: Int, in draft: Draft) -> Int? {
        guard let last = draft.presentIndices.last(where: { $0 < unit }) else { return nil }
        let word = draft.shape(at: last)
        return isAmount(core: word.core, suffix: word.suffix) ? last : nil
    }

    /// Whether a draft word is a bare numeral, not one that belongs to an "of" phrase such as "2 of 5".
    static func isAmount(core: String, suffix: String) -> Bool {
        suffix.isEmpty && isNumeral(figure(of: core)) && !core.split(separator: " ").contains("of")
    }

    /// The scale words that stay beside a numeral.
    static let magnitudes: Set<String> = ["million", "billion", "trillion"]

    /// Whether a smaller part of the amount follows the currency word, "and fifty cents", which "$12" would orphan.
    static func hasMinorPart(after unit: Int, in draft: Draft) -> Bool {
        let following = draft.presentIndices.filter { $0 > unit }.prefix(3).map { draft.shape(at: $0).key }
        let words = following.first == "and" ? Array(following.dropFirst()) : following
        guard words.count >= 2, words[0].first?.isNumber == true else { return false }
        return Quantities.isMinorUnit(words[1])
    }

    /// The number in an amount that may carry a magnitude word, "5" of "5 million".
    static func figure(of core: String) -> String {
        core.split(separator: " ").first.map(String.init) ?? core
    }

    /// Whether the text is digits with optional grouping commas and one decimal part.
    static func isNumeral(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isNumber else { return false }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count <= 2
            && parts.allSatisfy { $0.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ",") } }
            && parts.last?.last != ","
    }

    /// "a hundred and fifty" is one number, 150; a hundred with no tail stays a word.
    static func aHundredAndTail(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard position + 3 < keys.count, keys[position] == "a", keys[position + 1] == "hundred",
            keys[position + 2] == "and", (position + 1...position + 3).allSatisfy({ joined($0, shapes) }),
            let tail = NumberWords.cardinal(unbroken(from: position + 3, keys: keys, shapes: shapes)),
            tail.value < 100
        else { return nil }
        let next = position + 3 + tail.count
        guard next >= keys.count || NumberWords.ordinals[keys[next]] == nil else { return nil }
        let whole = 3 + tail.count
        if next < keys.count, keys[next] == "point" {
            guard let group = digitGroup(at: next + 1, keys: keys, shapes: shapes) else { return nil }
            let end = next + 1 + group.count
            let text = "\(100 + tail.value).\(group.text)"
            guard let percent = percentWords(at: end, keys: keys, shapes: shapes) else {
                return Phrase(text: text, count: whole + 1 + group.count)
            }
            return Phrase(text: text + "%", count: whole + 1 + group.count + percent)
        }
        return Phrase(text: String(100 + tail.value), count: whole)
    }

    /// "five million" as "5 million": a coefficient under 1000 and one scale word keep the magnitude word.
    static func magnitudeForm(at position: Int, end: Int, keys: [String]) -> String? {
        guard end - position >= 2, magnitudes.contains(keys[end - 1]),
            let coefficient = NumberWords.cardinal(keys[position..<(end - 1)]),
            coefficient.count == end - 1 - position, coefficient.value < 1000
        else { return nil }
        return "\(coefficient.value) \(keys[end - 1])"
    }
}
