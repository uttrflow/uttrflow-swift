import UttrflowCore
import UttrflowDictionary

// The guard's number checks: invented numbers, changed quantities and Indian digit grouping.
extension MeaningPreservationGuard {
    /// The first number the rewrite states that the speaker did not state, there and that many times, or nil.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        // Read in words on the written side too, so "twenty chairs" and "assi log" are refused as "20 chairs" is.
        let spoken = numberSequence(in: original, reading: quantityWords)
        let written = numberSequence(in: rewritten, reading: writtenQuantityWords)
        var cursor = spoken.startIndex
        var index = written.startIndex
        while index < written.endIndex {
            guard let match = firstMatch(of: written[index...], in: spoken[cursor...]) else {
                return written[index]
            }
            cursor = match.spokenEnd
            index += match.writtenCount
        }
        return nil
    }

    /// The next spoken match: same value, digits said one by one ("one two three" as 123), or a run written in groups.
    private static func firstMatch(
        of written: ArraySlice<String>, in spoken: ArraySlice<String>
    ) -> (spokenEnd: Int, writtenCount: Int)? {
        guard let number = written.first else { return nil }
        for start in spoken.indices {
            if sameValue(spoken[start], number) { return (start + 1, 1) }
            if let end = joinedEnd(of: spoken[start...], matching: number) { return (end, 1) }
            if let count = joinedEnd(of: written, matching: spoken[start]) {
                return (start + 1, count - written.startIndex)
            }
        }
        return nil
    }

    /// The end of a run of two or more whole numbers from the start of `pieces` that reads as `whole`, or nil.
    private static func joinedEnd(of pieces: ArraySlice<String>, matching whole: String) -> Int? {
        guard whole.allSatisfy(\.isNumber) else { return nil }
        var joined = ""
        for index in pieces.indices {
            let piece = pieces[index]
            guard piece.allSatisfy(\.isNumber) else { return nil }
            joined += piece
            guard whole.hasPrefix(joined) else { return nil }
            if joined == whole { return index > pieces.startIndex ? index + 1 : nil }
        }
        return nil
    }

    /// Two spellings of one number, a zero written before it ("01" for "one") included.
    private static func sameValue(_ spoken: String, _ written: String) -> Bool {
        func unpadded(_ number: String) -> Substring {
            var digits = number[...]
            while digits.count > 1, digits.first == "0", digits.dropFirst().first != "." {
                digits = digits.dropFirst()
            }
            return digits
        }
        return spoken == written || unpadded(spoken) == unpadded(written)
    }

    /// A number whose sign or symbol the rewrite dropped, changed or invented; the digits alone are `inventedNumber`'s job.
    static func changedQuantity(original: String, rewritten: String) -> String? {
        let spoken = amounts(in: original)
        let written = amounts(in: rewritten)
        guard !spoken.isEmpty, !written.isEmpty else { return nil }
        // Pairs by digits, so a number turned from words into digits ("three" as 3) does not shift later pairs.
        var matched = Set<Int>()
        var cursor = spoken.startIndex
        for found in written {
            guard let index = spoken[cursor...].firstIndex(where: { $0.digits == found.digits }) else {
                continue
            }
            let quantity = spoken[index]
            if quantity.sign != found.sign || quantity.symbol != found.symbol { return quantity.written }
            matched.insert(index)
            cursor = index + 1
        }
        guard written.count < spoken.count else { return nil }
        return spoken.indices.first { !matched.contains($0) }.map { spoken[$0].written }
    }

    /// The quantities a text states, a currency said as a word after the amount ("12 dollars") read as its symbol.
    private static func amounts(in text: String) -> [Quantity] {
        let characters = Array(text)
        return Quantities.spans(in: text).map { span in
            let quantity = span.quantity
            guard quantity.symbol.isEmpty else { return quantity }
            let named = Quantities.currencyNamed(after: characters, at: span.range.upperBound)
            return Quantity(digits: quantity.digits, sign: quantity.sign, symbol: named)
        }
    }

    /// Refuses a rewrite that changes an amount already written with Indian digit grouping.
    static func changedIndianGrouping(original: String, rewritten: String) -> String? {
        let spoken = numericSpellings(in: original)
        let written = numericSpellings(in: rewritten)
        for (index, spelling) in spoken.enumerated()
        where DigitGrouping.indian.matches(spelling) && !DigitGrouping.thousands.matches(spelling) {
            guard written.indices.contains(index), written[index] == spelling else { return spelling }
        }
        return nil
    }

    /// The digit runs and comma separators as they appear, kept in text order.
    private static func numericSpellings(in text: String) -> [String] {
        let characters = Array(text)
        let separators = Quantities.groupingCommas(in: characters)
        var spellings: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < characters.count, characters[index].isNumber || separators.contains(index) {
                index += 1
            }
            spellings.append(String(characters[start..<index]))
        }
        return spellings
    }

    /// The numbers a text states, in order and with repeats kept, each number word read through `table` and every run of them composed after it.
    static func numberSequence(in text: String, reading table: [String: String]) -> [String] {
        var pieces: [(text: String, isDigits: Bool)] = []
        var run = ""
        func flush() {
            if !run.isEmpty { pieces.append((run, false)) }
            run = ""
        }
        // Each number is read once, by `Quantities`, so "50K", "50 thousand" and "50,000" come to one value here too.
        let characters = Array(text)
        var spans = Quantities.spans(in: text)[...]
        var position = 0
        while position < characters.count {
            if let span = spans.first, span.range.lowerBound == position {
                flush()
                pieces.append((span.quantity.digits, true))
                spans = spans.dropFirst()
                position = span.range.upperBound
                continue
            }
            let character = characters[position]
            position += 1
            guard character.isLetter else {
                flush()
                continue
            }
            run.append(character)
        }
        flush()
        // A run of digits stands between number words, so it ends a spoken number rather than joining it.
        let words = pieces.map { $0.isDigits ? "" : $0.text.lowercased() }
        var found: [String] = []
        var index = words.startIndex
        while index < words.endIndex {
            if pieces[index].isDigits {
                found.append(pieces[index].text)
                index += 1
            } else if let read =
                NumberWords.cardinal(words[index...]) ?? NumberWords.hindiCardinal(words[index...]),
                read.count > 1
            {
                found += words[index..<(index + read.count)].compactMap { table[$0] }
                found.append(String(read.value))
                index += read.count
            } else {
                if let digits = table[words[index]] { found.append(digits) }
                index += 1
            }
        }
        return found
    }

    /// Drops a comma that groups digits, so "12,000" and "1,50,000" read as the numbers they are and "10,20" as two.
    static func withoutThousandsSeparators(_ text: String) -> String {
        let characters = Array(text)
        let separators = Quantities.groupingCommas(in: characters)
        return String(characters.indices.filter { !separators.contains($0) }.map { characters[$0] })
    }

    /// Digits people dictate as words, in English and Hindi; traps if a shared word ("lakh") differs in value.
    static let numberWords: [String: String] = Dictionary(
        NumberWords.english.map { ($0.key, String($0.value)) }
            + NumberWords.hindi.map { ($0.key, String($0.value)) }
    ) { english, hindi in
        precondition(english == hindi, "a number word means one value in both tables")
        return english
    }

    /// Each ordinal word as the numeral the rules write for it, "third" as "3rd".
    static let ordinalNumerals: [String: String] = NumberFormsPass.ordinalUnits.mapValues {
        "\($0)\(NumberFormsPass.ordinalSuffix($0))"
    }

    /// The number words, the Hindi fraction words and the ordinals, each as the value it states.
    private static let quantityWords: [String: String] = numberWords.merging(
        NumberWords.hindiFractions.mapValues { String($0.value) }
    ) { first, _ in first }.merging(NumberFormsPass.ordinalUnits.mapValues { String($0) }) { first, _ in first
    }

    /// The quantity words read on the written side, less the Hindi ones as often an ordinary word ("do", "saath").
    private static let writtenQuantityWords: [String: String] = quantityWords.filter {
        !NumberWords.hindiHomographs.contains($0.key)
    }

    /// The positions of every spoken number run the rewrite wrote as the one numeral it comes to.
    static func composedNumbers(_ tokens: [GrammarToken], in pool: Set<String>) -> Set<Int> {
        var covered: Set<Int> = []
        for run in cardinalRuns(tokens.map(\.matching)) where pool.contains(String(run.value)) {
            covered.formUnion(run.start..<(run.start + run.count))
        }
        return covered
    }

    /// Every run of two or more words that `NumberWords` reads as one cardinal, longest first from each start.
    private static func cardinalRuns(_ words: [String]) -> [(start: Int, count: Int, value: Int)] {
        var runs: [(start: Int, count: Int, value: Int)] = []
        var index = words.startIndex
        while index < words.endIndex {
            guard let read = NumberWords.cardinal(words[index...]), read.count > 1 else {
                index += 1
                continue
            }
            runs.append((index, read.count, read.value))
            index += read.count
        }
        return runs
    }
}
