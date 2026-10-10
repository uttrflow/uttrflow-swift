import Foundation
import NaturalLanguage
public import UttrflowCore

/// Writes spoken numbers as numerals, as many of them as the place asks for. See `Docs/cleanup.md`.
public struct NumberFormsPass: PieceCleaningPass {
    public static let id: PassID = .numberForms
    public static let laws: Set<PassLaw> = [.idempotent, .latinOnly]
    public static let orderIndependentWith: Set<PassID> = [.contractions]

    /// Which spoken numbers this place wants as numerals.
    let policy: NumberPolicy

    /// How this place writes a numeral's digits; somewhere machine-read wants no separators in them.
    let digits: DigitGrouping

    /// Words after which a lone digit is a numeral, digit groups run together, and no separator is used.
    static let contextWords: Set<String> = [
        "port", "version", "extension", "page", "chapter", "step", "number", "line", "section", "figure",
        "table", "level", "room", "floor", "route", "flight", "interstate", "highway", "bus", "gate",
        "grade", "size", "model",
    ]
    /// The spoken currency words, bar those read with the `measures` ("yen").
    static let currencies = Set(Quantities.currencyWords.keys).subtracting(measures)
    static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m"]
    /// The words a speaker uses for the leading zero of a clock minute.
    static let clockZeros: Set<String> = ["oh", "o", "zero"]
    /// Words after which "nineteen oh five" is a year rather than a clock time or a count.
    static let yearCues: Set<String> = ["in", "since", "year", "of", "from", "until", "till"]
    static let idioms: [[String]] = [["twenty", "four", "seven"], ["fifty", "fifty"]]
    static let monthDays: [String: Int] = [
        "january": 31, "february": 29, "march": 31, "april": 30, "may": 31, "june": 30,
        "july": 31, "august": 31, "september": 30, "october": 31, "november": 30, "december": 31,
    ]
    package static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
        "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
    ]
    /// Other currencies and units with no second meaning; "pound", "feet" and "second" stay out.
    static let measures: Set<String> = [
        "yen", "dirham", "dirhams", "franc", "francs", "kilometre", "kilometres", "kilometer", "kilometers",
        "kilogram", "kilograms", "metre", "metres", "meter", "meters", "litre", "litres", "liter", "liters",
        "minutes", "hours",
    ]

    /// Romanised Hindi amount, unit and time words after which a Hindi number is written in digits.
    static let hindiMeasures: Set<String> = [
        "rupaye", "rupaiye", "rupay", "paise", "minat",
        "ghante", "ghanta", "baje", "din", "saal", "mahine", "hafte", "tareekh", "tarikh",
    ]

    /// Unit words English spells the same, after which a Hindi number is written in digits unless the sentence is English.
    static let sharedMeasures: Set<String> = ["rupee", "rupees", "kilo", "gram", "litre", "minute"]

    /// The separator words of a spoken numeric date and the mark each is written as.
    static let dateSeparators: [String: String] = ["slash": "/", "stroke": "/", "dash": "-"]

    /// Street words after which a scale number and a unit ordinal are a house number and a street name.
    static let streetWords: Set<String> = [
        "avenue", "street", "road", "drive", "lane", "boulevard", "court", "place", "way",
    ]

    /// One rendered number and how many words it replaces.
    struct Phrase: Equatable {
        let text: String
        let count: Int
    }

    /// A number as spoken or already in digits, before anything joins onto it.
    private struct Item {
        let value: Int?
        let text: String
        let count: Int
        let spoken: Bool
    }

    public init(policy: NumberPolicy = .fromTen, digits: DigitGrouping = .thousands) {
        self.policy = policy
        self.digits = digits
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let present = draft.presentIndices
        let (shapes, live) = Self.splittingTensUnits(present.map { draft.shape(at: $0) }, of: present)
        let keys = shapes.map(\.key)
        let arithmetic = Self.arithmetic(keys: keys, shapes: shapes, policy: policy)
        let grouped = Self.numeralGroupMembers(keys: keys, shapes: shapes, policy: policy, digits: digits)
            .union(arithmetic.numbers)
        var position = 0
        while position < live.count {
            guard position == 0 || live[position - 1] != live[position] else {
                position += 1
                continue
            }
            if let sign = arithmetic.operators[position] {
                let last = position + sign.count - 1
                let text = shapes[position].prefix + sign.symbol + shapes[last].suffix
                Self.write(text, over: position...last, of: live, in: &draft)
                position += sign.count
                continue
            }
            if let percentile = Self.percentile(
                at: position, keys: keys, shapes: shapes, policy: policy, digits: digits),
                Self.endsWord(position + percentile.count - 1, live)
            {
                let last = position + percentile.count - 1
                let text = shapes[position].prefix + "p" + percentile.text + shapes[last].suffix
                Self.write(text, over: position...last, of: live, in: &draft)
                position += percentile.count
                continue
            }
            if let count = Self.unchangedIdiomCount(at: position, keys: keys, shapes: shapes) {
                position += count
                continue
            }
            if let time = Self.dottedTime(at: position, keys: keys, shapes: shapes) {
                draft.replace(
                    at: live[position], with: shapes[position].replacingCore(with: time), by: Self.id)
                position += 1
                continue
            }
            guard
                let phrase = Self.phrase(
                    at: position, keys: keys, shapes: shapes,
                    policy: grouped.contains(position) ? .always : policy, digits: digits)
            else {
                position +=
                    Self.parseOrdinal(at: position, keys: keys, shapes: shapes)?.count
                    ?? Self.undecidedHundred(at: position, keys: keys, shapes: shapes) ?? 1
                continue
            }
            let last = position + phrase.count - 1
            guard Self.endsWord(last, live) else {
                position += 1
                continue
            }
            let text = shapes[position].prefix + phrase.text + shapes[last].suffix
            Self.write(text, over: position...last, of: live, in: &draft)
            position += phrase.count
        }
        return draft
    }

    /// Operator words to write as symbols, and the numbers beside them that become numerals.
    struct Arithmetic {
        var operators: [Int: (symbol: String, count: Int)] = [:]
        var numbers: Set<Int> = []
    }

    /// The spoken operator starting at `position`, joined to the words around it.
    private static func spokenOperator(
        at position: Int, keys: [String], shapes: [WordShape]
    ) -> (symbol: String, count: Int)? {
        for (words, symbol) in NumberCues.operators where position + words.count <= keys.count {
            guard Array(keys[position..<position + words.count]) == words,
                (position + 1..<position + words.count).allSatisfy({ joined($0, shapes) })
            else { continue }
            return (symbol, words.count)
        }
        return nil
    }

    /// Operators between numbers, under `.always` or in a sentence of only numbers and operators. See `Docs/data-tables.md`.
    static func arithmetic(keys: [String], shapes: [WordShape], policy: NumberPolicy) -> Arithmetic {
        func endsSentence(_ index: Int) -> Bool {
            index == keys.count - 1 || shapes[index].suffix.contains(where: { ".?!:;".contains($0) })
        }
        var found = Arithmetic()
        var start = 0
        while start < keys.count {
            // One run of numbers and operators, each word joined to the next; `items` holds each item's start.
            var items: [(start: Int, count: Int, symbol: String?)] = []
            var end = start
            while end < keys.count, end == start || joined(end, shapes) {
                if let sign = spokenOperator(at: end, keys: keys, shapes: shapes) {
                    guard items.last.map({ $0.symbol == nil }) == true else { break }
                    items.append((end, sign.count, sign.symbol))
                    end += sign.count
                } else if NumberWords.isNumber(keys[end]) {
                    if let previous = items.last, previous.symbol == nil {
                        items[items.count - 1].count += 1
                    } else {
                        items.append((end, 1, nil))
                    }
                    end += 1
                } else {
                    break
                }
            }
            while let last = items.last, last.symbol != nil {
                items.removeLast()
            }
            let runEnd = items.last.map { $0.start + $0.count } ?? start
            let wholeSentence =
                (start == 0 || endsSentence(start - 1)) && runEnd > start && endsSentence(runEnd - 1)
            if items.contains(where: { $0.symbol != nil }), policy == .always || wholeSentence {
                for item in items {
                    if let symbol = item.symbol {
                        found.operators[item.start] = (symbol, item.count)
                    } else {
                        found.numbers.insert(item.start)
                    }
                }
            }
            start = max(end, start + 1)
        }
        return found
    }

    /// Words between numbers that join them into one group written in one form.
    static let coordinators = NumberCues.words(for: .coordinator)
    /// Coordinators that join only a rising pair; a falling one is a clock reading such as "ten to six".
    static let rangeWords = NumberCues.words(for: .range)

    /// Number positions that `policy` leaves as words but that share a coordinated group with a numeral.
    static func numeralGroupMembers(
        keys: [String], shapes: [WordShape], policy: NumberPolicy, digits: DigitGrouping
    ) -> Set<Int> {
        guard policy != .always else { return [] }
        // The number here: its words, value, and whether `policy` alone writes it as a numeral.
        func member(at position: Int) -> (count: Int, value: Double?, isNumeral: Bool)? {
            guard position < keys.count else { return nil }
            if let written = NumberWords.digits(keys[position]) { return (1, Double(written), true) }
            guard
                let always = phrase(
                    at: position, keys: keys, shapes: shapes, policy: .always, digits: digits)
            else { return nil }
            let own = phrase(at: position, keys: keys, shapes: shapes, policy: policy, digits: digits)
            return (always.count, Double(always.text.filter { $0 != "," }), own != nil)
        }
        var members: Set<Int> = []
        var position = 0
        while position < keys.count {
            guard var current = member(at: position) else {
                position += 1
                continue
            }
            var group = [(start: position, isNumeral: current.isNumeral)]
            var coordinated = false
            var end = position + current.count
            // Only a comma or a coordinator sits between members, so "three apples and twelve pears" stays apart.
            while end < keys.count, shapes[end].prefix.isEmpty {
                let afterComma = shapes[end - 1].suffix == ","
                guard afterComma || shapes[end - 1].suffix.isEmpty else { break }
                var next = end
                if coordinators.contains(keys[end]), joined(end + 1, shapes) {
                    next += 1
                    coordinated = true
                } else if !afterComma {
                    break
                }
                guard let following = member(at: next) else { break }
                if rangeWords.contains(keys[end]), next > end {
                    guard let low = current.value, let high = following.value, low < high else { break }
                }
                group.append((next, following.isNumeral))
                current = following
                end = next + following.count
            }
            if coordinated, group.contains(where: \.isNumeral) {
                members.formUnion(group.filter { !$0.isNumeral }.map(\.start))
            }
            position = end
        }
        return members
    }

    /// Splits a written `tens-unit` word such as "twenty-one" into its two number words, each mapped to its draft index.
    static func splittingTensUnits(_ shapes: [WordShape], of indices: [Int]) -> ([WordShape], [Int]) {
        var split: [WordShape] = []
        var origins: [Int] = []
        for (shape, index) in zip(shapes, indices) {
            let parts = shape.core.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, NumberWords.tens[parts[0].lowercased()] != nil,
                let unit = NumberWords.units[parts[1].lowercased()], unit > 0
            {
                split += [WordShape(shape.prefix + parts[0]), WordShape(parts[1] + shape.suffix)]
                origins += [index, index]
            } else {
                split.append(shape)
                origins.append(index)
            }
        }
        return (split, origins)
    }

    /// Whether the split word at `position` is the last piece of its draft word.
    private static func endsWord(_ position: Int, _ live: [Int]) -> Bool {
        position + 1 >= live.count || live[position + 1] != live[position]
    }

    /// Writes `text` over the draft words behind the split words in `span`.
    private static func write(
        _ text: String, over span: ClosedRange<Int>, of live: [Int], in draft: inout Draft
    ) {
        draft.replace(at: live[span.lowerBound], with: text, by: id)
        for index in Set(live[span]).subtracting([live[span.lowerBound]]).sorted() {
            draft.remove(at: index, by: id)
        }
    }

    /// Joins a spoken percentile after `p` only for the commonly used latency ranks.
    private static func percentile(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy, digits: DigitGrouping
    ) -> Phrase? {
        guard keys[position] == "p", joined(position + 1, shapes),
            let number = phrase(at: position + 1, keys: keys, shapes: shapes, policy: policy, digits: digits),
            ["50", "90", "95", "99", "99.9"].contains(number.text)
        else { return nil }
        return Phrase(text: number.text, count: number.count + 1)
    }

    /// The `H.MM` words in `text` that read as a clock by the cue rule this pass writes them with.
    static func dottedClockTimes(in text: String) -> Set<String> {
        let shapes = WordTokens.words(text, .display).map(WordShape.init)
        let keys = shapes.map(\.key)
        let clocks = shapes.indices.filter { dottedTime(at: $0, keys: keys, shapes: shapes) != nil }
        return Set(clocks.map { shapes[$0].core })
    }

    /// Writes one `H.MM` word as `H:MM` only with a meridiem or a time cue; only a cue reads past 12.
    private static func dottedTime(at position: Int, keys: [String], shapes: [WordShape]) -> String? {
        let parts = keys[position].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, shapes[position].prefix.isEmpty,
            parts[0].allSatisfy(\.isNumber), let hour = Int(parts[0]), (0...23).contains(hour),
            parts[1].count == 2, parts[1].allSatisfy(\.isNumber), let minute = Int(parts[1]),
            (0...59).contains(minute), !quantified(at: position, keys: keys, shapes: shapes)
        else { return nil }
        let hasMeridiem =
            shapes[position].suffix.isEmpty && joined(position + 1, shapes)
            && meridiems.contains(keys[position + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        let hasCue = hasTimeCue(before: position, keys: keys, shapes: shapes)
        guard hasCue || (hasMeridiem && (1...12).contains(hour)) else { return nil }
        return "\(hour):\(parts[1])"
    }

    /// Whether a percent sign, a unit or a further digit group after the number at `position` makes it a quantity.
    private static func quantified(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        let next = position + 1
        return shapes[position].suffix.hasPrefix("%")
            || joined(next, shapes)
                && (leadingDecimalUnits.contains(keys[next]) || NumberWords.digits(keys[next]) != nil
                    || percentWords(at: next, keys: keys, shapes: shapes) != nil)
    }

    /// The numeral for the number phrase starting at `position`, or nil when the words stay as they are.
    static func phrase(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy = .fromTen,
        digits: DigitGrouping = .thousands
    ) -> Phrase? {
        let fixedShapes: [(Int, [String], [WordShape]) -> Phrase?] = [
            zoneOffset, signedDigitRun, numericDate, cuedYear, cuedClock, twentyFourHourClock,
            dottedNumber, spokenDigitRun, leadingDecimal, decade,
        ]
        for reading in fixedShapes {
            if let found = reading(position, keys, shapes) { return found }
        }
        if let amount = hindiAmount(at: position, keys: keys, shapes: shapes, digits: digits) {
            return amount
        }
        if (keys[position] == "negative" || keys[position] == "minus"), joined(position + 1, shapes),
            !subtracts(at: position, keys: keys, shapes: shapes)
        {
            return negative(at: position, keys: keys, shapes: shapes, policy: policy, digits: digits)
        }
        guard !finishesAScale(at: position, keys: keys, shapes: shapes) else { return nil }
        if let date = monthFirstDate(at: position, keys: keys, shapes: shapes, policy: policy) { return date }
        if let ordinal = parseOrdinal(at: position, keys: keys, shapes: shapes) {
            return ordinalReading(ordinal, at: position, keys: keys, shapes: shapes, policy: policy)
        }
        return cardinal(at: position, keys: keys, shapes: shapes, policy: policy, digits: digits)
    }

    /// "plus" followed by spoken digits, as a dialling prefix.
    private static func signedDigitRun(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard keys[position] == "plus", joined(position + 1, shapes),
            let run = spokenDigitRun(at: position + 1, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: "+" + run.text, count: run.count + 1)
    }

    /// "negative" or "minus" heading a number that is not a subtraction.
    private static func negative(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy, digits: DigitGrouping
    ) -> Phrase? {
        if let numeral = NumberWords.digits(keys[position + 1]) {
            return Phrase(text: "-" + numeral, count: 2)
        }
        guard
            let magnitude = phrase(
                at: position + 1, keys: keys, shapes: shapes, policy: policy, digits: digits)
        else { return nil }
        return Phrase(text: "-" + magnitude.text, count: magnitude.count + 1)
    }

    /// A month followed by its ordinal day: "march fifteenth".
    private static func monthFirstDate(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy
    ) -> Phrase? {
        guard let limit = monthDays[keys[position]], joined(position + 1, shapes),
            let ordinal = parseOrdinal(at: position + 1, keys: keys, shapes: shapes),
            ordinal.value <= limit, policy == .always || ordinal.value >= 10,
            monthIsDated(at: position, keys: keys, shapes: shapes)
        else { return nil }
        let day = Phrase(
            text: "\(WordShape.capitalised(keys[position])) \(ordinal.value)", count: ordinal.count + 1)
        return withYear(day, at: position, order: .monthFirst, keys: keys, shapes: shapes)
    }

    /// An ordinal: a large one alone, or a day heading its month, "fifteenth of march".
    private static func ordinalReading(
        _ ordinal: (value: Int, count: Int), at position: Int, keys: [String], shapes: [WordShape],
        policy: NumberPolicy
    ) -> Phrase? {
        if ordinal.value >= 21,
            !isDateShapedOrdinal(at: position, ordinal: ordinal, keys: keys, shapes: shapes)
        {
            return Phrase(text: "\(ordinal.value)\(ordinalSuffix(ordinal.value))", count: ordinal.count)
        }
        var end = position + ordinal.count
        guard joined(end, shapes) else { return nil }
        let hasOf = keys[end] == "of"
        if hasOf { end += 1 }
        guard joined(end, shapes), let limit = monthDays[keys[end]], ordinal.value <= limit else {
            return nil
        }
        guard hasOf || monthIsDated(at: end, keys: keys, shapes: shapes) else { return nil }
        guard policy == .always || ordinal.value >= 10 else { return nil }
        let month = WordShape.capitalised(keys[end])
        let preposition = hasOf ? " of" : ""
        let day = Phrase(
            text: "\(ordinal.value)\(ordinalSuffix(ordinal.value))\(preposition) \(month)",
            count: end - position + 1)
        return withYear(day, at: position, order: .dayFirst, keys: keys, shapes: shapes)
    }

    /// A cardinal and whatever joins onto it, each reading tried in a fixed order.
    private static func cardinal(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy, digits: DigitGrouping
    ) -> Phrase? {
        guard let item = item(at: position, keys: keys, shapes: shapes) else { return nil }
        let contextPosition =
            position > 0 && ["negative", "minus"].contains(keys[position - 1])
            ? position - 2 : position - 1
        let inContext =
            contextPosition >= 0 && !startsASentence(position, shapes)
            && contextWords.contains(keys[contextPosition])
        if let measured = decimalAndPercent(item, at: position, keys: keys, shapes: shapes) {
            return measured
        }
        if !inContext, let value = item.value,
            let reading = yearOrTime(value, item: item, at: position, keys: keys, shapes: shapes)
        {
            return reading
        }
        if !inContext, item.spoken, item.count == 1,
            let hundred = NumberWords.colloquialHundred(unbroken(from: position, keys: keys, shapes: shapes)),
            readsAsOneQuantity(hundred, at: position, keys: keys, shapes: shapes)
        {
            return Phrase(text: String(hundred.value), count: hundred.count)
        }
        if inContext, item.spoken, let run = contextDigits(item, at: position, keys: keys, shapes: shapes) {
            return run
        }
        return plainNumber(
            item, at: position, inContext: inContext, keys: keys, shapes: shapes, policy: policy,
            digits: digits)
    }

    /// Decimal places joined with "point", then "percent" or "per cent".
    private static func decimalAndPercent(
        _ item: Item, at position: Int, keys: [String], shapes: [WordShape]
    ) -> Phrase? {
        var end = position + item.count
        var text = item.text
        while joined(end, shapes), keys[end] == "point",
            let group = digitGroup(at: end + 1, keys: keys, shapes: shapes)
        {
            text += "." + group.text
            end += 1 + group.count
        }
        if let percent = percentWords(at: end, keys: keys, shapes: shapes) {
            text += "%"
            end += percent
        }
        return end == position + item.count ? nil : Phrase(text: text, count: end - position)
    }

    /// A year read in two halves, "nineteen ninety", or a clock time, "ten thirty".
    private static func yearOrTime(
        _ value: Int, item: Item, at position: Int, keys: [String], shapes: [WordShape]
    ) -> Phrase? {
        let end = position + item.count
        if let year = year(after: value, at: end, keys: keys, shapes: shapes) {
            return Phrase(text: year.text, count: item.count + year.count)
        }
        guard let time = time(hour: value, at: end, keys: keys, shapes: shapes),
            timeAcceptable(
                position: position, minuteStart: end, minuteEnd: end + time.count, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: time.text, count: item.count + time.count)
    }

    /// After a context word, the following numbers run together as one string of digits.
    private static func contextDigits(
        _ item: Item, at position: Int, keys: [String], shapes: [WordShape]
    ) -> Phrase? {
        var end = position + item.count
        if joined(end, shapes), keys[end] == "of",
            let following = NumberWords.cardinal(unbroken(from: end + 1, keys: keys, shapes: shapes))
        {
            let text = item.text + " of " + NumberWords.render(following.value, grouping: .none)
            return Phrase(text: text, count: end + following.count + 1 - position)
        }
        var text = item.text
        while joined(end, shapes),
            let group = NumberWords.cardinal(unbroken(from: end, keys: keys, shapes: shapes))
        {
            text += String(group.value)
            end += group.count
        }
        return end == position + item.count ? nil : Phrase(text: text, count: end - position)
    }

    /// A spoken number alone, written as digits when the policy threshold allows it.
    private static func plainNumber(
        _ item: Item, at position: Int, inContext: Bool, keys: [String], shapes: [WordShape],
        policy: NumberPolicy, digits: DigitGrouping
    ) -> Phrase? {
        guard item.spoken, let value = item.value else { return nil }
        let end = position + item.count
        let beforeAmount =
            joined(end, shapes)
            && (currencies.contains(keys[end]) || measures.contains(keys[end])
                || namesAUnit(at: end, keys: keys, shapes: shapes))
            || completesAmount(at: position, keys: keys, shapes: shapes)
        guard policy == .always || inContext || value >= 10 || beforeAmount else { return nil }
        guard
            inContext || beforeAmount || value != 1 || item.count != 1
                || !headsItsOwnPhrase(at: position, keys: keys)
        else { return nil }
        // The destination says whether digits are grouped; a context word still runs its own together.
        return Phrase(
            text: NumberWords.render(value, grouping: inContext ? .none : digits), count: item.count)
    }

    /// Whether "one" is the pronoun of "no one", "this one" or "one another" rather than a count of what follows.
    private static func headsItsOwnPhrase(at position: Int, keys: [String]) -> Bool {
        let tags = LexicalClass.tags(ofWords: keys)
        func tag(_ index: Int) -> NLTag? { tags.indices.contains(index) ? tags[index] : nil }
        let modifiable: Set<NLTag> = [.noun, .adjective, .number]
        if tag(position) == .noun || tag(position) == .pronoun { return true }
        if tag(position - 1) == .determiner, !modifiable.contains(tag(position + 1) ?? .otherWord) {
            return true
        }
        if tag(position + 1) == .determiner, !modifiable.contains(tag(position + 2) ?? .otherWord) {
            return true
        }
        let distributive = { (by: Int, other: Int) in
            keys.indices.contains(by) && keys.indices.contains(other) && keys[by] == "by"
                && keys[other] == keys[position]
        }
        return distributive(position + 1, position + 2) || distributive(position - 1, position - 2)
    }

    /// Whether the words at `start` are a unit symbol `Abbreviations` names, written ("GB") or spelled in single letters ("g b").
    private static func namesAUnit(at start: Int, keys: [String], shapes: [WordShape]) -> Bool {
        var end = start
        while end < keys.count, end == start || joined(end, shapes), keys[end].count == 1,
            keys[end].allSatisfy(\.isLetter)
        {
            end += 1
        }
        let letters = end - start >= 2 ? keys[start..<end].joined() : keys[start]
        return Abbreviations.unitSymbol(spelled: letters) != nil
    }

    /// The words of a colloquial hundred left unread because it may be a time, unless its tail counts the noun after it.
    private static func undecidedHundred(at position: Int, keys: [String], shapes: [WordShape]) -> Int? {
        let words = unbroken(from: position, keys: keys, shapes: shapes)
        guard let hundred = NumberWords.colloquialHundred(words) else { return nil }
        // "two twenty dollar bills" is a count of what the tail modifies, so its tail is written on its own.
        let after = position + hundred.count
        let countsANoun = joined(after, shapes) && LexicalClass.tag(ofWordAt: after, in: keys) == .noun
        return countsANoun ? nil : hundred.count
    }

    /// Whether a colloquial hundred is one value: its tail cannot be a minute, or it is a ratio's first term.
    private static func readsAsOneQuantity(
        _ hundred: (value: Int, count: Int), at position: Int, keys: [String], shapes: [WordShape]
    ) -> Bool {
        if hundred.value % 100 >= 60 { return true }
        let after = position + hundred.count
        return joined(after, shapes) && keys[after] == "over" && joined(after + 1, shapes)
            && NumberWords.isNumber(keys[after + 1])
    }

    /// A cued time whose minutes open with a spoken zero; a sentence end alone is no cue, so "extension three zero two" stays digits.
    private static func cuedClock(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let hour = NumberWords.cardinal(keys[position...position])?.value,
            position + 1 < keys.count, clockZeros.contains(keys[position + 1]),
            let time = time(hour: hour, at: position + 1, keys: keys, shapes: shapes), time.count == 2
        else { return nil }
        let end = position + 1 + time.count
        guard !(joined(end, shapes) && singleDigit(keys[end]) != nil),
            timeAcceptable(
                position: position, minuteStart: position + 1, minuteEnd: end, keys: keys, shapes: shapes,
                sentenceEndIsCue: false)
        else { return nil }
        return Phrase(text: time.text, count: end - position)
    }

    /// "u t c plus five thirty" as `UTC+5:30`: a zone, a sign, an hour up to 14 and an optional :30 or :45.
    private static func zoneOffset(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        for (heard, zone) in TimeZones.offsetZones {
            let sign = position + heard.count
            guard sign + 1 < keys.count, Array(keys[position..<sign]) == heard,
                (position + 1...sign + 1).allSatisfy({ joined($0, shapes) }),
                let mark = ["plus": "+", "minus": "-"][keys[sign]],
                let hour = NumberWords.cardinal(keys[(sign + 1)...(sign + 1)])?.value ?? Int(keys[sign + 1]),
                (0...14).contains(hour)
            else { continue }
            let end = sign + 2
            if joined(end, shapes), let minutes = minutes(at: end, keys: keys, shapes: shapes),
                ["30", "45"].contains(minutes.text)
            {
                let text = "\(zone)\(mark)\(hour):\(minutes.text)"
                return Phrase(text: text, count: end + minutes.count - position)
            }
            return Phrase(text: "\(zone)\(mark)\(hour)", count: end - position)
        }
        return nil
    }

    /// "fourteen thirty" after a time cue as `14:30`, and "oh nine hundred" before "hours" as `0900`.
    private static func twentyFourHourClock(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase?
    {
        let zeroLed = clockZeros.contains(keys[position])
        let hourStart = zeroLed ? position + 1 : position
        guard !zeroLed || joined(hourStart, shapes), hourStart < keys.count else { return nil }
        let hour: (value: Int, count: Int)
        if zeroLed {
            guard let unit = NumberWords.units[keys[hourStart]] else { return nil }
            hour = (unit, 1)
        } else {
            let words = unbroken(from: hourStart, keys: keys, shapes: shapes).prefix { $0 != "hundred" }
            guard let parsed = NumberWords.cardinal(words),
                parsed.count <= 2, (10...23).contains(parsed.value)
            else { return nil }
            hour = parsed
        }
        let minuteStart = hourStart + hour.count
        guard joined(minuteStart, shapes) else { return nil }
        let minutes: Phrase
        if keys[minuteStart] == "hundred" {
            minutes = Phrase(text: "00", count: 1)
        } else if zeroLed || hour.value >= 13,
            let spoken = self.minutes(at: minuteStart, keys: keys, shapes: shapes)
        {
            minutes = spoken
        } else {
            return nil
        }
        let end = minuteStart + minutes.count
        guard !(joined(end, shapes) && NumberWords.isNumber(keys[end])) else { return nil }
        let hourText = hour.value < 10 ? "0\(hour.value)" : String(hour.value)
        if joined(end, shapes), keys[end] == "hours" {
            return Phrase(text: hourText + minutes.text, count: end - position)
        }
        let hasBeforeCue =
            position > 0 && !startsASentence(position, shapes) && timeCues.contains(keys[position - 1])
        guard hasBeforeCue, keys[minuteStart] != "hundred" else { return nil }
        return Phrase(text: "\(hourText):\(minutes.text)", count: end - position)
    }

    /// Words before an hour-and-minute phrase that mark it as a time of day.
    static let timeCues: Set<String> = [
        "at", "by", "until", "till", "from", "around", "about", "before", "after", "since",
    ]

    /// Nouns that take a time of day, after which "for" is a time cue as in "an alarm for seven thirty".
    static let timedNouns: Set<String> = [
        "alarm", "alarms", "appointment", "appointments", "booking", "meeting", "meetings",
        "reminder", "reminders", "reservation",
    ]

    /// Whether the word before `position` cues a time of day within the same sentence.
    private static func hasTimeCue(before position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard position > 0, !startsASentence(position, shapes) else { return false }
        if timeCues.contains(keys[position - 1]) { return true }
        return keys[position - 1] == "for" && position > 1 && !startsASentence(position - 1, shapes)
            && timedNouns.contains(keys[position - 2])
    }

    /// Whether the number here is the smaller part of an amount, after a number and its currency.
    private static func completesAmount(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        var currency = position - 1
        if currency > 0, keys[currency] == "and", joined(currency + 1, shapes) { currency -= 1 }
        guard currency > 0, currencies.contains(keys[currency]), joined(currency + 1, shapes),
            joined(currency, shapes)
        else { return false }
        let major = currency - 1
        return NumberWords.digits(keys[major]) != nil || NumberWords.cardinal(keys[major..<currency]) != nil
    }

    /// Requires a time cue, or a sentence end after the minute unless the caller needs a cue, when the hour and minute form one phrase.
    private static func timeAcceptable(
        position: Int, minuteStart: Int, minuteEnd: Int,
        keys: [String], shapes: [WordShape], sentenceEndIsCue: Bool = true
    ) -> Bool {
        let hasBeforeCue = hasTimeCue(before: position, keys: keys, shapes: shapes)
        let endsTheSentence =
            sentenceEndIsCue && (minuteEnd >= shapes.count || shapes[minuteEnd - 1].endsSentence)
        let hasAfterCue =
            minuteEnd < shapes.count && joined(minuteEnd, shapes)
            && (meridiems.contains(keys[minuteEnd]) || keys[minuteEnd] == "o'clock")
        return hasBeforeCue || hasAfterCue || endsTheSentence
    }

    /// Whether the words here finish a scale the parser could not read whole, as in "a hundred and fifty".
    private static func finishesAScale(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        position >= 2 && !startsASentence(position, shapes) && !startsASentence(position - 1, shapes)
            && keys[position - 1] == "and" && NumberWords.scales[keys[position - 2]] != nil
    }

    /// Whether a "minus" here follows a number, so it subtracts rather than signs the number after it.
    private static func subtracts(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard keys[position] == "minus", position > 0, joined(position, shapes) else { return false }
        let previous = keys[position - 1]
        return NumberWords.digits(previous) != nil || NumberWords.cardinal([previous]) != nil
            || NumberWords.scales[previous] != nil
    }

    /// The number of words of a spoken "percent" or "per cent" at `index`, if one is there.
    private static func percentWords(at index: Int, keys: [String], shapes: [WordShape]) -> Int? {
        guard joined(index, shapes) else { return nil }
        if keys[index] == "percent" { return 1 }
        return keys[index] == "per" && joined(index + 1, shapes) && keys[index + 1] == "cent" ? 2 : nil
    }

    /// Units after which a decimal with no whole part reads as a number; "second" is safe after digits.
    static let leadingDecimalUnits = measures.union(currencies).union(["second", "seconds", "minute", "hour"])

    /// "point five percent", "minus point two": a decimal with no whole part, cued by a sign before or a unit after.
    private static func leadingDecimal(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard keys[position] == "point", let group = digitGroup(at: position + 1, keys: keys, shapes: shapes)
        else { return nil }
        let end = position + 1 + group.count
        let text = "0." + group.text
        if let percent = percentWords(at: end, keys: keys, shapes: shapes) {
            return Phrase(text: text + "%", count: end + percent - position)
        }
        let signed =
            position > 0 && joined(position, shapes) && ["negative", "minus"].contains(keys[position - 1])
        // An adjective before "point" makes it the noun, as in "a good point five minutes ago".
        let measured =
            joined(end, shapes) && leadingDecimalUnits.contains(keys[end])
            && (position == 0 || LexicalClass.tag(ofWordAt: position - 1, in: keys) != .adjective)
        guard signed || measured else { return nil }
        return Phrase(text: text, count: end - position)
    }

    /// Whether the word at `index` opens a sentence, past which a number reads none of its context.
    private static func startsASentence(_ index: Int, _ shapes: [WordShape]) -> Bool {
        index > 0 && shapes[index - 1].endsSentence
    }

    private static func item(at position: Int, keys: [String], shapes: [WordShape]) -> Item? {
        if let digits = NumberWords.digits(keys[position]) {
            return Item(value: Int(digits), text: digits, count: 1, spoken: false)
        }
        guard let parsed = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)) else {
            return nil
        }
        // A unit after a scale starts a digit string only when another spoken digit follows it.
        let last = position + parsed.count - 1
        if parsed.count > 1, last + 1 < keys.count,
            ["hundred", "thousand"].contains(keys[last - 1]),
            singleDigit(keys[last]) != nil,
            joined(last, shapes), joined(last + 1, shapes), singleDigit(keys[last + 1]) != nil,
            let shorter = NumberWords.cardinal(keys[position..<last]), shorter.count == parsed.count - 1
        {
            return Item(value: shorter.value, text: String(shorter.value), count: shorter.count, spoken: true)
        }
        return Item(value: parsed.value, text: String(parsed.value), count: parsed.count, spoken: true)
    }

    /// Whether the word at `index` follows its predecessor with no punctuation between them.
    private static func joined(_ index: Int, _ shapes: [WordShape]) -> Bool {
        index < shapes.count && shapes[index - 1].suffix.isEmpty && shapes[index].prefix.isEmpty
    }

    /// Whether a month word reads as a date; one that is also a verb or modal needs a heard capital or a dating clause.
    static func monthIsDated(at index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard keys[index] == "may" || keys[index] == "march" else { return monthDays[keys[index]] != nil }
        if shapes[index].core == WordShape.capitalised(keys[index]) { return true }
        return dayOfMonthPrecedes(index, keys: keys, shapes: shapes)
            || dayFollows(index, keys: keys, shapes: shapes)
    }

    /// The positions of the month words in `shapes` that `monthIsDated` reads as dates.
    static func datedMonths(in shapes: [WordShape]) -> Set<Int> {
        let keys = shapes.map(\.key)
        return Set(keys.indices.filter { monthIsDated(at: $0, keys: keys, shapes: shapes) })
    }

    /// "the third of march": an ordinal day that fits the month, then "of", straight before it.
    private static func dayOfMonthPrecedes(_ index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard index >= 2, keys[index - 1] == "of", joined(index, shapes), joined(index - 1, shapes),
            let limit = monthDays[keys[index]]
        else { return false }
        return (max(0, index - 4)..<(index - 1)).contains { start in
            guard let ordinal = parseOrdinal(at: start, keys: keys, shapes: shapes) else { return false }
            return start + ordinal.count == index - 1 && ordinal.value <= limit
        }
    }

    /// "march fifth": an ordinal day that fits the month straight after it, unless a pronoun subject makes the word a verb.
    private static func dayFollows(_ index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard joined(index + 1, shapes), let limit = monthDays[keys[index]],
            let ordinal = parseOrdinal(at: index + 1, keys: keys, shapes: shapes), ordinal.value <= limit
        else { return false }
        guard index > 0, !startsASentence(index, shapes) else { return true }
        return LexicalClass.tag(ofWordAt: index - 1, in: keys) != .pronoun
    }

    /// A romanised Hindi number before an amount, unit or time word, as "paanch sau rupaye" for "500 rupaye".
    private static func hindiAmount(
        at position: Int, keys: [String], shapes: [WordShape], digits: DigitGrouping
    ) -> Phrase? {
        var end = position
        while end < keys.count, end == position || joined(end, shapes), NumberWords.hindi[keys[end]] != nil {
            end += 1
            if !shapes[end - 1].suffix.isEmpty { break }
        }
        guard let read = NumberWords.hindiCardinal(keys[position..<end]) else { return nil }
        let unit = position + read.count
        guard joined(unit, shapes) else { return nil }
        let shared = sharedMeasures.contains(keys[unit])
        guard
            hindiMeasures.contains(keys[unit])
                || shared && !isEnglishSentence(around: position, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: NumberWords.render(read.value, grouping: digits), count: read.count)
    }

    /// Whether the sentence holding `position` has an English small word and no Hindi one, so a Hindi number in it is a borrowed word.
    private static func isEnglishSentence(around position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        var start = position
        while start > 0, !shapes[start - 1].endsSentence { start -= 1 }
        var end = position
        while end < keys.count, end == position || !shapes[end - 1].endsSentence { end += 1 }
        let words = keys[start..<end].filter { NumberWords.hindi[$0] == nil }
        let hindi = words.contains { HindiWords.functionWords.contains($0) }
        let english = words.contains { FunctionWords.holds($0) && HindiWords.classes(of: $0).isEmpty }
        return english && !hindi
    }

    /// The keys from `start` up to the first word that carries punctuation.
    private static func unbroken(from start: Int, keys: [String], shapes: [WordShape]) -> ArraySlice<String> {
        var end = start
        // A number reads only number words and "and", so the run ends at the first other word.
        while end < keys.count, end == start || joined(end, shapes),
            NumberWords.value(of: keys[end]) != nil || keys[end] == "and"
        {
            end += 1
            if !shapes[end - 1].suffix.isEmpty { break }
        }
        return keys[start..<end]
    }

    /// The digits after "point": single digits run together, or one number from ten up.
    private static func digitGroup(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        var text = ""
        var end = start
        while joined(end, shapes), let digit = singleDigit(keys[end]) {
            text.append(digit)
            end += 1
        }
        if !text.isEmpty { return Phrase(text: text, count: end - start) }
        guard joined(start, shapes) else { return nil }
        if let digits = NumberWords.digits(keys[start]) { return Phrase(text: digits, count: 1) }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            group.value >= 10
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }

    /// Words before two dotted digit groups that say they are an address, version or decimal.
    static let dottedCues = NumberCues.words(for: .dotted)

    /// "one nine two dot one six eight dot one dot one": digit groups a spoken "dot" joins, three or more or two after a cue.
    private static func dottedNumber(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let first = leadingGroup(at: position, keys: keys, shapes: shapes) else { return nil }
        var text = first.text
        var end = position + first.count
        var groups = 1
        while joined(end, shapes), keys[end] == "dot",
            let group = digitGroup(at: end + 1, keys: keys, shapes: shapes)
        {
            text += "." + group.text
            end += 1 + group.count
            groups += 1
        }
        let cued =
            position > 0 && !startsASentence(position, shapes) && dottedCues.contains(keys[position - 1])
        guard groups >= 3 || (groups == 2 && cued) else { return nil }
        return Phrase(text: text, count: end - position)
    }

    /// The first group of a dotted number: single digit words run together, digits, or one cardinal.
    private static func leadingGroup(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        var text = ""
        var end = position
        while end < keys.count, end == position || joined(end, shapes), let digit = singleDigit(keys[end]) {
            text.append(digit)
            end += 1
        }
        if !text.isEmpty { return Phrase(text: text, count: end - position) }
        if let digits = NumberWords.digits(keys[position]) { return Phrase(text: digits, count: 1) }
        guard let group = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)) else {
            return nil
        }
        return Phrase(text: String(group.value), count: group.count)
    }

    private static func singleDigit(_ key: String) -> String? {
        NumberWords.spokenDigit(key).map(String.init)
    }

    /// How many times "double", "triple" and "quadruple" repeat the digit word after them.
    static let digitRepeats: [String: Int] = ["double": 2, "triple": 3, "quadruple": 4]

    /// The digits one step of a spoken run reads: a digit word, or a repeat word joined to one.
    private static func digitStep(at index: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard index < keys.count else { return nil }
        if let digit = singleDigit(keys[index]) { return Phrase(text: digit, count: 1) }
        guard let times = digitRepeats[keys[index]], joined(index + 1, shapes),
            let digit = singleDigit(keys[index + 1])
        else { return nil }
        return Phrase(text: String(repeating: digit, count: times), count: 2)
    }

    /// Joins three or more digits with a nonzero one among them, no scale after them, and a cue before a count.
    private static func spokenDigitRun(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let first = digitStep(at: start, keys: keys, shapes: shapes) else { return nil }
        var text = first.text
        var end = start + first.count
        while joined(end, shapes), let step = digitStep(at: end, keys: keys, shapes: shapes) {
            text += step.text
            end += step.count
        }
        guard text.count >= 3, text.contains(where: { $0 != "0" }) else { return nil }
        guard !(joined(end, shapes) && NumberWords.scales[keys[end]] != nil) else { return nil }
        var runStart = start
        var run = text
        while runStart > 0, joined(runStart, shapes), let digit = singleDigit(keys[runStart - 1]) {
            run = digit + run
            runStart -= 1
        }
        guard !isCount(run) || hasDigitCue(before: runStart, keys: keys, shapes: shapes) else { return nil }
        return Phrase(text: text, count: end - start)
    }

    /// Words before a digit run that say it is a code or a number to dial, not a count.
    static let digitCues = contextWords.union(NumberCues.words(for: .digitRun))

    /// Whether the digits step up or down by one each time, as a count-off or countdown does.
    private static func isCount(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        let steps = zip(values, values.dropFirst()).map { $1 - $0 }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }

    /// Whether the word before a run's first digit introduces a number or is itself one, within the same sentence.
    private static func hasDigitCue(before start: Int, keys: [String], shapes: [WordShape]) -> Bool {
        start > 0 && !startsASentence(start, shapes)
            && (digitCues.contains(keys[start - 1]) || NumberWords.isNumber(keys[start - 1]))
    }

    static func ordinalSuffix(_ value: Int) -> String {
        let remainder = value % 100
        if (11...13).contains(remainder) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// Which part of a date was spoken first; the parts are never reordered.
    enum DateOrder {
        case monthFirst, dayFirst

        /// What stands between the day and the year: month-first dates set the year off with a comma.
        var yearSeparator: String { self == .monthFirst ? ", " : " " }
    }

    /// A day and month with the year spoken straight after it, written as one date in the spoken order.
    private static func withYear(
        _ day: Phrase, at position: Int, order: DateOrder, keys: [String], shapes: [WordShape]
    ) -> Phrase {
        guard let year = dateYear(at: position + day.count, keys: keys, shapes: shapes) else { return day }
        return Phrase(text: day.text + order.yearSeparator + year.text, count: day.count + year.count)
    }

    /// "oh three slash oh four slash twenty twenty five" as 03/04/2025: the groups in the spoken order, padded as spoken.
    private static func numericDate(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let first = dateGroup(at: position, keys: keys, shapes: shapes) else { return nil }
        let firstSeparator = position + first.count
        guard joined(firstSeparator, shapes), let mark = dateSeparators[keys[firstSeparator]],
            joined(firstSeparator + 1, shapes),
            let second = dateGroup(at: firstSeparator + 1, keys: keys, shapes: shapes)
        else { return nil }
        let secondSeparator = firstSeparator + 1 + second.count
        guard joined(secondSeparator, shapes), dateSeparators[keys[secondSeparator]] == mark,
            let year = numericYear(at: secondSeparator + 1, keys: keys, shapes: shapes),
            let firstValue = Int(first.text), let secondValue = Int(second.text),
            min(firstValue, secondValue) <= 12
        else { return nil }
        return Phrase(
            text: [first.text, second.text, year.text].joined(separator: mark),
            count: secondSeparator + 1 + year.count - position)
    }

    /// A day or month of a numeric date, 1 to 31, with the leading zero only when one was spoken.
    private static func dateGroup(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        if clockZeros.contains(keys[start]), joined(start + 1, shapes),
            let digit = NumberWords.units[keys[start + 1]], (1...9).contains(digit)
        {
            return Phrase(text: "0\(digit)", count: 2)
        }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (1...31).contains(group.value), group.count <= 2
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }

    /// The year of a numeric date: a four-digit date year, or two digits as spoken.
    private static func numericYear(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        if let year = dateYear(at: start, keys: keys, shapes: shapes) { return year }
        guard joined(start, shapes) else { return nil }
        if clockZeros.contains(keys[start]), joined(start + 1, shapes),
            let digit = NumberWords.units[keys[start + 1]]
        {
            return Phrase(text: "0\(digit)", count: 2)
        }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (10...99).contains(group.value), group.count <= 2
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }

    /// The year that can close a date: four written digits from 1900 to 2099, or a spoken year.
    private static func dateYear(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard joined(start, shapes) else { return nil }
        if let digits = NumberWords.digits(keys[start]), digits.count == 4, let value = Int(digits),
            (1900...2099).contains(value)
        {
            return Phrase(text: digits, count: 1)
        }
        guard let century = NumberWords.teens[keys[start]] ?? NumberWords.tens[keys[start]],
            let year = year(after: century, at: start + 1, keys: keys, shapes: shapes, cued: true)
        else { return nil }
        return Phrase(text: year.text, count: year.count + 1)
    }

    /// A spoken year after a year cue or a month, so "in twenty oh five" is 2005 and never a clock time.
    private static func cuedYear(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard position > 0, !startsASentence(position, shapes),
            yearCues.contains(keys[position - 1]) || monthDays[keys[position - 1]] != nil,
            let century = NumberWords.teens[keys[position]] ?? NumberWords.tens[keys[position]],
            let year = year(after: century, at: position + 1, keys: keys, shapes: shapes, cued: true)
        else { return nil }
        return Phrase(text: year.text, count: year.count + 1)
    }

    /// "twenty twenty four" and "nineteen ninety nine"; a cued year also takes "oh" and a unit, as in "twenty oh five".
    private static func year(
        after century: Int, at start: Int, keys: [String], shapes: [WordShape], cued: Bool = false
    ) -> Phrase? {
        guard century == 19 || century == 20, joined(start, shapes) else { return nil }
        if cued, clockZeros.contains(keys[start]), joined(start + 1, shapes),
            let unit = NumberWords.units[keys[start + 1]], unit > 0
        {
            return Phrase(text: String(century * 100 + unit), count: 2)
        }
        guard let rest = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (10...99).contains(rest.value), rest.count <= 2
        else { return nil }
        return Phrase(text: String(century * 100 + rest.value), count: rest.count)
    }

    /// Reads a plural decade such as "nineteen nineties" as one year range.
    private static func decade(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let century = NumberWords.teens[keys[position]] ?? NumberWords.tens[keys[position]],
            [19, 20].contains(century),
            joined(position + 1, shapes),
            let decade = NumberWords.tens.first(where: {
                $0.value >= 20 && $0.value <= 90
                    && ($0.key.hasSuffix("y") ? String($0.key.dropLast()) + "ies" : $0.key + "s")
                        == keys[position + 1]
            })?.value
        else { return nil }
        return Phrase(text: "\(century * 100 + decade)s", count: 2)
    }

    /// Keeps fixed spoken idioms intact so their number words are not partially rewritten.
    private static func unchangedIdiomCount(at position: Int, keys: [String], shapes: [WordShape]) -> Int? {
        idioms.first { idiom in
            position + idiom.count <= keys.count
                && Array(keys[position..<(position + idiom.count)]) == idiom
                && (position + 1..<position + idiom.count).allSatisfy { joined($0, shapes) }
        }?.count
    }

    /// "two thirty", "two thirty pm", "two oh five pm", "ten am", "five o'clock"; am and pm stay separate.
    private static func time(hour: Int, at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard (1...12).contains(hour), joined(start, shapes) else { return nil }
        if let minutes = minutes(at: start, keys: keys, shapes: shapes) {
            return Phrase(text: "\(hour):\(minutes.text)", count: minutes.count)
        }
        guard meridiems.contains(keys[start]) || keys[start] == "o'clock" else { return nil }
        return Phrase(text: String(hour), count: 0)
    }

    private static func minutes(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        if clockZeros.contains(keys[start]), joined(start + 1, shapes),
            let digit = NumberWords.units[keys[start + 1]], digit > 0
        {
            return Phrase(text: "0\(digit)", count: 2)
        }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (10...59).contains(group.value), group.count <= 2
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }

    /// Reads whole ordinals, including compounds that must stay intact when they are not dates.
    private static func parseOrdinal(
        at position: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, count: Int)? {
        let parts = keys[position].split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, let ten = NumberWords.tens[String(parts[0])],
            let unit = ordinalUnits[String(parts[1])], unit < 10
        {
            return (ten + unit, 1)
        }
        if let ten = NumberWords.tens[keys[position]], joined(position + 1, shapes),
            let unit = ordinalUnits[keys[position + 1]], unit < 10
        {
            return (ten + unit, 2)
        }
        if let cardinal = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)),
            let room = ordinalRoom(after: cardinal.value)
        {
            var ordinalPosition = position + cardinal.count
            var count = cardinal.count
            if joined(ordinalPosition, shapes), keys[ordinalPosition] == "and",
                joined(ordinalPosition + 1, shapes)
            {
                ordinalPosition += 1
                count += 1
            }
            if joined(ordinalPosition, shapes),
                let tail = parseOrdinal(at: ordinalPosition, keys: keys, shapes: shapes), tail.value < room,
                !isHouseNumber(endingAt: position + cardinal.count - 1, keys: keys, shapes: shapes)
            {
                return (cardinal.value + tail.value, count + tail.count)
            }
        }
        return ordinalUnits[keys[position]].map { ($0, 1) }
    }

    /// The ordinal a cardinal of twenty or more can take after it, filling its empty places: under ten after a ten, under a hundred after a scale.
    package static func ordinalRoom(after cardinal: Int) -> Int? {
        guard cardinal >= 20 else { return nil }
        return cardinal % 100 == 0 ? 100 : cardinal % 10 == 0 ? 10 : 1
    }

    /// Whether a number ending on a scale word is a house number, because a unit ordinal and a street word follow it.
    private static func isHouseNumber(endingAt last: Int, keys: [String], shapes: [WordShape]) -> Bool {
        NumberWords.scales[keys[last]] != nil && joined(last + 1, shapes) && joined(last + 2, shapes)
            && streetWords.contains(keys[last + 2])
    }

    /// Keeps date-like and interrupted date forms intact for the existing date parser to handle.
    private static func isDateShapedOrdinal(
        at position: Int, ordinal: (value: Int, count: Int), keys: [String], shapes: [WordShape]
    ) -> Bool {
        // A day after a dated month is the date parser's, which refuses an impossible one: "March thirty second".
        if position > 0, joined(position, shapes), monthIsDated(at: position - 1, keys: keys, shapes: shapes)
        {
            return true
        }
        let end = position + ordinal.count
        guard end < keys.count else { return false }
        return keys[end] == "of" || monthDays[keys[end]] != nil
    }
}
