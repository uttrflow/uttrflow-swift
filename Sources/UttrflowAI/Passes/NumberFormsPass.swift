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
    static let contextWords = NumberCues.words(for: .designator)
    /// The spoken currency words, bar those read with the `measures` ("yen").
    static let currencies = Set(Quantities.currencyWords.keys).subtracting(measures)
    static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m"]
    /// The words a speaker uses for the leading zero of a clock minute.
    static let clockZeros: Set<String> = ["oh", "o", "zero"]
    /// Words after which "nineteen oh five" is a year rather than a clock time or a count.
    static let yearCues: Set<String> = ["in", "since", "year", "of", "from", "until", "till"]
    /// Fixed expressions whose number words are not a count, kept as words under every policy.
    static let idioms: [[String]] = [
        ["twenty", "four", "seven"], ["fifty", "fifty"], ["one", "or", "two"],
        ["my", "two", "cents"], ["your", "two", "cents"], ["our", "two", "cents"], ["their", "two", "cents"],
        ["his", "two", "cents"], ["her", "two", "cents"],
    ]
    static let monthDays: [String: Int] = [
        "january": 31, "february": 29, "march": 31, "april": 30, "may": 31, "june": 30,
        "july": 31, "august": 31, "september": 30, "october": 31, "november": 30, "december": 31,
    ]
    package static let ordinalUnits = NumberWords.ordinals
    /// Other currencies and units with no second meaning; "pound", "feet" and "second" stay out.
    static let measures: Set<String> = [
        "yen", "dirham", "dirhams", "franc", "francs", "kilometre", "kilometres", "kilometer", "kilometers",
        "kilogram", "kilograms", "metre", "metres", "meter", "meters", "litre", "litres", "liter", "liters",
        "minutes", "hours",
    ]

    /// The currency and unit words a numeral at the end of a piece takes from the next piece across a seam.
    package static let seamUnits: Set<String> = leadingDecimalUnits.union(hindiMeasures)
        .union(sharedMeasures).union(["percent"]).subtracting(["second"])

    /// Romanised Hindi amount, unit and time words after which a Hindi number is written in digits.
    static let hindiMeasures: Set<String> = [
        "rupaye", "rupaiye", "rupay", "rupye", "paise", "minat",
        "ghante", "ghanta", "baje", "din", "saal", "mahine", "hafte", "haphte", "tareekh", "tarikh",
        "taareekh",
    ]

    /// Romanised Hindi time-of-day words, which take a digit like "o'clock" does: "five baje" is "5 baje".
    static let hindiClockWords: Set<String> = ["baje"]

    /// Unit words English spells the same, after which a Hindi number is written in digits unless the sentence is English.
    static let sharedMeasures: Set<String> = [
        "rupee", "rupees", "kilo", "gram", "graam", "litre", "leetar", "minute",
    ]

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
    /// Units between two numbers that make them one measure: "five foot ten", "two hours thirty minutes".
    static let measureLeads = NumberCues.words(for: .measureLead)
    /// Units that close a two-part measure after its second number.
    static let measureTails = NumberCues.words(for: .measureTail)

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
                var measure = false
                if coordinators.contains(keys[end]), joined(end + 1, shapes) {
                    next += 1
                    coordinated = true
                } else if !afterComma, measureLeads.contains(keys[end]), joined(end + 1, shapes) {
                    next += 1
                    measure = true
                } else if !afterComma {
                    break
                }
                guard let following = member(at: next) else { break }
                if rangeWords.contains(keys[end]), next > end {
                    guard let low = current.value, let high = following.value, low < high else { break }
                }
                if measure {
                    // The second part ends the measure: a smaller unit, or nothing joined, as in "five foot ten".
                    let after = next + following.count
                    guard !joined(after, shapes) || measureTails.contains(keys[after]) else { break }
                    coordinated = true
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
        let attached = attachedMeridiem(in: keys[position])
        let digits = keys[position].dropLast(attached.count)
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, shapes[position].prefix.isEmpty,
            parts[0].allSatisfy(\.isNumber), let hour = Int(parts[0]), (0...23).contains(hour),
            parts[1].count == 2, parts[1].allSatisfy(\.isNumber), let minute = Int(parts[1]),
            (0...59).contains(minute), !quantified(at: position, keys: keys, shapes: shapes)
        else { return nil }
        let dots = CharacterSet(charactersIn: ".")
        let next = position + 1 < keys.count ? keys[position + 1].trimmingCharacters(in: dots) : ""
        let hasMeridiem =
            !attached.isEmpty
            || shapes[position].suffix.isEmpty && joined(position + 1, shapes) && meridiems.contains(next)
        let hasCue = hasTimeCue(before: position, keys: keys, shapes: shapes)
        guard hasCue || (hasMeridiem && (1...12).contains(hour)) else { return nil }
        return "\(hour):\(parts[1])" + attached
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
        if let price = minorAmount(at: position, keys: keys, shapes: shapes, digits: digits)
            ?? priceShorthand(at: position, keys: keys, shapes: shapes)
        {
            return price
        }
        if let range = sharedScaleRange(at: position, keys: keys, shapes: shapes, digits: digits) {
            return range
        }
        let fixedShapes: [(Int, [String], [WordShape]) -> Phrase?] = [
            score, readingOver, zoneOffset, signedDigitRun, numericDate, cuedYear, cuedClock,
            colonClock, twentyFourHourClock, dottedNumber, spokenDigitRun, leadingDecimal, decade,
        ]
        for reading in fixedShapes {
            if let found = reading(position, keys, shapes) { return found }
        }
        if let amount = hindiAmount(at: position, keys: keys, shapes: shapes, digits: digits) {
            return amount
        }
        if (keys[position] == "negative" || keys[position] == "minus"), joined(position + 1, shapes),
            !subtracts(at: position, keys: keys, shapes: shapes),
            !completesPlusOrMinus(at: position, keys: keys, shapes: shapes)
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

    /// A major amount, its currency word and a smaller number, "two dollars fifty", written "2.50 dollars".
    private static func minorAmount(
        at position: Int, keys: [String], shapes: [WordShape], digits: DigitGrouping
    ) -> Phrase? {
        guard let major = item(at: position, keys: keys, shapes: shapes), let value = major.value else {
            return nil
        }
        let currency = position + major.count
        guard joined(currency, shapes), Quantities.hasMinorUnit(keys[currency]), joined(currency + 1, shapes),
            let minor = hundredth(at: currency + 1, keys: keys, shapes: shapes)
        else { return nil }
        let end = currency + 1 + minor.count
        if joined(end, shapes),
            Quantities.isMinorUnit(keys[end])
                || LexicalClass.tag(ofWordAt: end, in: keys) == .noun
        {
            return nil
        }
        let whole = major.spoken ? NumberWords.render(value, grouping: digits, isAmount: true) : major.text
        return Phrase(
            text: "\(whole).\(twoDigits(minor.value)) \(shapes[currency].core)", count: end - position)
    }

    /// Words before a price said as two numbers, "two ninety nine", that mark it as money and not a time.
    static let priceCues: Set<String> = ["cost", "costs", "price", "priced", "for"]

    /// Words that may stand between a price cue and the price, "the price is two ninety nine".
    static let priceLinks: Set<String> = ["is", "was", "of", "only", "just"]

    /// A one-digit amount and a two-digit part after a price cue, "costs two ninety nine", written "2.99".
    private static func priceShorthand(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard position > 0, joined(position, shapes), !startsASentence(position, shapes) else { return nil }
        var cue = position - 1
        if priceLinks.contains(keys[cue]), cue > 0, joined(cue, shapes) { cue -= 1 }
        guard priceCues.contains(keys[cue]), !hasTimeCue(before: position, keys: keys, shapes: shapes),
            let whole = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)),
            whole.count == 1, (1...9).contains(whole.value),
            joined(position + 1, shapes), let part = hundredth(at: position + 1, keys: keys, shapes: shapes),
            part.value >= 10, keys[cue] != "for" || part.value > 59
        else { return nil }
        let end = position + 1 + part.count
        if joined(end, shapes),
            isMeridiem(at: end, keys: keys, shapes: shapes)
                || LexicalClass.tag(ofWordAt: end, in: keys) == .noun
        {
            return nil
        }
        return Phrase(text: "\(whole.value).\(twoDigits(part.value))", count: end - position)
    }

    /// The number from one to ninety-nine at `start`, spoken or in digits, that is the hundredth part of an amount.
    private static func hundredth(
        at start: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, count: Int)? {
        let read: (value: Int, count: Int)?
        if let written = NumberWords.digits(keys[start]) {
            read = Int(written).map { ($0, 1) }
        } else {
            read = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes))
        }
        guard let read, (1...99).contains(read.value) else { return nil }
        return read
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }

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
            ordinal.value <= limit, monthIsDated(at: position, keys: keys, shapes: shapes)
        else { return nil }
        // A day the number policy leaves in words is still part of the date, so the month is written as one: "March third".
        let number =
            policy == .always || ordinal.value >= 10
            ? String(ordinal.value)
            : shapes[(position + 1)..<(position + 1 + ordinal.count)].map(\.core).joined(separator: " ")
        let day = Phrase(
            text: "\(WordShape.capitalised(keys[position])) \(number)", count: ordinal.count + 1)
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
        guard var item = item(at: position, keys: keys, shapes: shapes) else { return nil }
        let written = item.text
        if !item.spoken {
            let end = position + item.count
            let quantity =
                joined(end, shapes) && (currencies.contains(keys[end]) || measures.contains(keys[end]))
            item = Item(
                value: item.value, text: regrouped(item.text, digits: digits, quantity: quantity),
                count: item.count, spoken: false)
        }
        // "the code and one with the price": a label word earlier in the clause does not make the pronoun a code digit.
        let inContext =
            hasLabelCue(at: position, keys: keys, shapes: shapes)
            && !(item.spoken && item.value == 1 && item.count == 1
                && isDescribedOne(at: position, keys: keys))
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
        if let plain = plainNumber(
            item, at: position, inContext: inContext, keys: keys, shapes: shapes, policy: policy,
            digits: digits)
        {
            return plain
        }
        return item.text == written ? nil : Phrase(text: item.text, count: item.count)
    }

    /// A written numeral in the grouping `digits` says, at the same value; plain digits gain commas only as a quantity.
    static func regrouped(_ key: String, digits: DigitGrouping, quantity: Bool) -> String {
        if let scaled = scaledGroupedDecimal(key) {
            guard digits != .none else { return String(scaled) }
            return NumberWords.render(scaled, grouping: digits, isAmount: true)
        }
        let plain = key.filter { $0 != "," }
        guard plain.allSatisfy({ $0.isASCII && $0.isNumber }), plain.first != "0", let value = Int(plain)
        else { return key }
        guard key.contains(",") else {
            let reads = quantity && (4...9).contains(plain.count)
            guard reads, digits != .none else { return key }
            return NumberWords.render(value, grouping: digits, isAmount: true)
        }
        guard DigitGrouping.thousands.matches(key) || DigitGrouping.indian.matches(key) else { return key }
        // Prose keeps a person's Indian grouping; only an explicit style or a parsed place rewrites commas.
        return digits == .thousands || digits.matches(key) && digits != .none
            ? key : NumberWords.render(value, grouping: digits)
    }

    /// Decimal places joined with "point", then "percent" or "per cent", or a letter for a magnitude.
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
        if text.filter({ $0 == "." }).count >= 2,
            let suffix = preReleaseSuffix(at: end, keys: keys, shapes: shapes)
        {
            return Phrase(text: text + suffix.text, count: end + suffix.count - position)
        }
        if let percent = percentWords(at: end, keys: keys, shapes: shapes) {
            text += "%"
            end += percent
        } else if let mark = magnitudeMark(
            at: end, after: position, decimal: text.contains("."), keys: keys, shapes: shapes),
            LetterRun.knownCodes[text + keys[end]] == nil
        {
            text += mark
            end += 1
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
        // A scale then single digits is the scale and the digits, as it is outside a context, so a toll-free prefix keeps its zeros.
        while joined(end, shapes) {
            if let group = digitStringAware(at: end, keys: keys, shapes: shapes) {
                text += String(group.value)
                end += group.count
            } else if let step = digitStep(at: end, keys: keys, shapes: shapes) {
                text += step.text
                end += step.count
            } else {
                break
            }
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
        let beforeWord =
            joined(end, shapes)
            && (currencies.contains(keys[end]) || measures.contains(keys[end])
                || hindiClockWords.contains(keys[end]))
        let beforeAmount =
            beforeWord || joined(end, shapes) && namesAUnit(at: end, keys: keys, shapes: shapes)
            || completesAmount(at: position, keys: keys, shapes: shapes)
        guard policy == .always || inContext || value >= 10 || beforeAmount else { return nil }
        guard
            inContext || beforeAmount || value != 1 || item.count != 1
                || !headsItsOwnPhrase(at: position, keys: keys)
        else { return nil }
        // A spelled unit symbol is a specification, "3000 mAh", so only a currency or measure word makes an amount.
        let isAmount =
            beforeWord || completesAmount(at: position, keys: keys, shapes: shapes)
            || isRatioTerm(at: position, end: end, keys: keys, shapes: shapes)
        // The destination says whether digits are grouped; a context word still runs its own together.
        return Phrase(
            text: NumberWords.render(value, grouping: inContext ? .none : digits, isAmount: isAmount),
            count: item.count)
    }

    /// Whether the number is a term of "N out of M", an amount against its whole.
    private static func isRatioTerm(at position: Int, end: Int, keys: [String], shapes: [WordShape]) -> Bool {
        let leads =
            joined(end, shapes) && keys[end] == "out" && joined(end + 1, shapes) && keys[end + 1] == "of"
        let closes =
            position > 1 && joined(position, shapes) && keys[position - 2] == "out"
            && keys[position - 1] == "of" && joined(position - 1, shapes)
        return leads || closes
    }

    /// Words that after "one" start a phrase describing it, "one with a flag", so "one" stands for a thing.
    private static let pronounPrepositions: Set<String> = ["with", "without", "for"]

    /// Whether the word after the "one" at `position` opens a phrase that describes it, "one with a flag".
    private static func isDescribedOne(at position: Int, keys: [String]) -> Bool {
        keys.indices.contains(position + 1) && pronounPrepositions.contains(keys[position + 1])
    }

    /// Whether "one" is the pronoun of "no one", "this one" or "one another" rather than a count of what follows.
    private static func headsItsOwnPhrase(at position: Int, keys: [String]) -> Bool {
        let tags = LexicalClass.tags(ofWords: keys)
        func tag(_ index: Int) -> NLTag? { tags.indices.contains(index) ? tags[index] : nil }
        let modifiable: Set<NLTag> = [.noun, .adjective, .number]
        if tag(position) == .noun || tag(position) == .pronoun { return true }
        if isDescribedOne(at: position, keys: keys) { return true }
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
        // "one twenty twenty six" is a digit, then the year: the tail that starts a year is not part of a hundred.
        let tail = position + 1
        if let century = NumberWords.teens[keys[tail]] ?? NumberWords.tens[keys[tail]],
            year(after: century, at: tail + 1, keys: keys, shapes: shapes) != nil
        {
            return nil
        }
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

    /// "one thirty eight over eighty six" or "one oh five over sixty": a reading of two values, such as a blood pressure, written "138/86".
    private static func readingOver(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let upper = spokenHundred(at: position, keys: keys, shapes: shapes) else { return nil }
        let over = position + upper.count
        guard joined(over, shapes), keys[over] == "over", joined(over + 1, shapes) else { return nil }
        let words = unbroken(from: over + 1, keys: keys, shapes: shapes)
        guard let lower = NumberWords.colloquialHundred(words) ?? NumberWords.cardinal(words)
        else { return nil }
        return Phrase(text: "\(upper.value)/\(lower.value)", count: upper.count + 1 + lower.count)
    }

    /// A hundred said as its digit then its tail, "one thirty eight", or with a spoken zero, "one oh five".
    private static func spokenHundred(
        at position: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, count: Int)? {
        if let hundred = NumberWords.colloquialHundred(unbroken(from: position, keys: keys, shapes: shapes)) {
            return hundred
        }
        guard let digit = NumberWords.units[keys[position]], digit > 0, joined(position + 1, shapes),
            clockZeros.contains(keys[position + 1]), joined(position + 2, shapes),
            let unit = NumberWords.units[keys[position + 2]], unit > 0
        else { return nil }
        return (digit * 100 + unit, 3)
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

    /// An hour, a spoken "colon" and its minutes as one clock time, "ten colon thirty" as `10:30`, only where a time is cued.
    private static func colonClock(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        let hourWords = unbroken(from: position, keys: keys, shapes: shapes)
        guard let hour = NumberWords.cardinal(hourWords), (0...23).contains(hour.value),
            hour.count == hourWords.count, position + hour.count < keys.count,
            shapes[position + hour.count - 1].suffix == ":"
        else { return nil }
        let minuteStart = position + hour.count
        guard shapes[minuteStart].prefix.isEmpty else { return nil }
        let minutes: Phrase
        if clockZeros.contains(keys[minuteStart]), minuteStart + 1 < keys.count,
            clockZeros.contains(keys[minuteStart + 1]), shapes[minuteStart].suffix.isEmpty
        {
            minutes = Phrase(text: "00", count: 2)
        } else if let spoken = self.minutes(at: minuteStart, keys: keys, shapes: shapes) {
            minutes = spoken
        } else {
            return nil
        }
        let end = minuteStart + minutes.count
        guard
            timeAcceptable(
                position: position, minuteStart: minuteStart, minuteEnd: end, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: "\(hour.value):\(minutes.text)", count: end - position)
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
        // Only "at" says a clock: after any other cue "twenty twenty four" is the year, said in two halves.
        let readsAsYear =
            hour.value == 20 && keys[position - 1] != "at"
            && year(after: 20, at: minuteStart, keys: keys, shapes: shapes) != nil
        guard !readsAsYear else { return nil }
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

    /// Singular nouns for something that runs to a timetable, after which an hour and minute is a time of day: "the nine thirty train".
    static let scheduledNouns = NumberCues.words(for: .scheduled)

    /// Whether the word before `position` cues a time of day within the same sentence.
    private static func hasTimeCue(before position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard position > 0, !startsASentence(position, shapes) else { return false }
        if timeCues.contains(keys[position - 1]) { return true }
        if endsAClockRange(at: position, keys: keys, shapes: shapes) { return true }
        return keys[position - 1] == "for" && position > 1 && !startsASentence(position - 1, shapes)
            && timedNouns.contains(keys[position - 2])
    }

    /// The meridiem written straight after the minutes of a dotted word, as the "pm" of "2.30pm", or empty.
    private static func attachedMeridiem(in key: String) -> String {
        ["am", "pm", "a.m", "p.m"].first { key.hasSuffix($0) && key.count > $0.count } ?? ""
    }

    /// Whether the word at `position` ends a range opened by "from" and an hour, or by "between" and an hour.
    private static func endsAClockRange(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard position > 2, joined(position, shapes), joined(position - 1, shapes),
            joined(position - 2, shapes), !startsASentence(position - 3, shapes),
            (keys[position - 1] == "to" && keys[position - 3] == "from")
                || (keys[position - 1] == "and" && keys[position - 3] == "between")
        else { return false }
        let parts = keys[position - 2].split(separator: ".", omittingEmptySubsequences: false)
        let isHour = (1...2).contains(parts[0].count) && parts[0].allSatisfy(\.isNumber)
        let hasMinutes = parts.count == 2 && parts[1].count == 2 && parts[1].allSatisfy(\.isNumber)
        return isHour && (parts.count == 1 || hasMinutes)
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
            && !continuesACount(at: position, keys: keys, shapes: shapes)
        let hasAfterCue =
            minuteEnd < shapes.count && joined(minuteEnd, shapes)
            && (isMeridiem(at: minuteEnd, keys: keys, shapes: shapes) || keys[minuteEnd] == "o'clock")
        let hasNounAfter =
            minuteEnd < shapes.count && joined(minuteEnd, shapes) && scheduledNouns.contains(keys[minuteEnd])
        return hasBeforeCue || hasAfterCue || hasNounAfter || endsTheSentence
    }

    /// Whether the words here finish a scale the parser could not read whole, as in "a hundred and fifty".
    private static func finishesAScale(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        position >= 2 && !startsASentence(position, shapes) && !startsASentence(position - 1, shapes)
            && keys[position - 1] == "and" && NumberWords.scales[keys[position - 2]] != nil
            && !opensItsOwnHundred(at: position, keys: keys)
    }

    /// Whether the number here is followed by "hundred" after a hundred and an "and", which are two numbers.
    private static func opensItsOwnHundred(at position: Int, keys: [String]) -> Bool {
        keys[position - 2] == "hundred" && position + 1 < keys.count && keys[position + 1] == "hundred"
    }

    /// Whether a "minus" here follows a number, so it subtracts rather than signs the number after it.
    private static func subtracts(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard keys[position] == "minus", position > 0, joined(position, shapes) else { return false }
        let previous = keys[position - 1]
        return NumberWords.digits(previous) != nil || NumberWords.cardinal([previous]) != nil
            || NumberWords.scales[previous] != nil
    }

    /// Whether "minus" here ends "plus or minus", a tolerance whose number is not negative.
    private static func completesPlusOrMinus(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        keys[position] == "minus" && position > 1 && joined(position - 1, shapes) && joined(position, shapes)
            && keys[position - 1] == "or" && keys[position - 2] == "plus"
    }

    /// The written magnitude of a lone "k", "m" or "b" at `index`: "m" and "b" count only after a decimal or before a noun, else nil.
    private static func magnitudeMark(
        at index: Int, after position: Int, decimal: Bool, keys: [String], shapes: [WordShape]
    ) -> String? {
        guard joined(index, shapes), ["k", "m", "b"].contains(keys[index]) else { return nil }
        let next = index + 1
        let letterFollows = joined(next, shapes) && keys[next].count == 1 && keys[next].allSatisfy(\.isLetter)
        let designated = position > 0 && SpelledInitialismPass.designators[keys[position - 1]] != nil
        guard !letterFollows, !designated else { return nil }
        if keys[index] == "k" { return shapes[index].core }
        let countsANoun =
            joined(next, shapes)
            && (currencies.contains(keys[next]) || LexicalClass.tag(ofWordAt: next, in: keys) == .noun)
        return decimal || countsANoun ? keys[index].uppercased() : nil
    }

    /// "three out of ten": a score on a scale of ten, written "3/10" unless the ten counts a plural noun after it.
    private static func score(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let item = item(at: position, keys: keys, shapes: shapes), let value = item.value,
            (0...10).contains(value)
        else { return nil }
        let out = position + item.count
        let scale = out + 2
        guard joined(scale, shapes), joined(out, shapes), keys[out] == "out", joined(out + 1, shapes),
            keys[out + 1] == "of", ["ten", "10"].contains(keys[scale])
        else { return nil }
        // Ten counts a plural noun after it, "ten people"; a singular one such as "down" starts the next phrase.
        let next = scale + 1
        let countsANoun =
            joined(next, shapes) && LexicalClass.tag(ofWordAt: next, in: keys) == .noun
            && LexicalClass.lemma(ofWordAt: next, in: keys).map { $0 != keys[next] } == true
        return countsANoun ? nil : Phrase(text: "\(value)/10", count: next - position)
    }

    /// The number of words of a spoken "percent" or "per cent" at `index`, if one is there.
    private static func percentWords(at index: Int, keys: [String], shapes: [WordShape]) -> Int? {
        guard joined(index, shapes) else { return nil }
        if keys[index] == "percent" { return 1 }
        return keys[index] == "per" && joined(index + 1, shapes) && keys[index + 1] == "cent" ? 2 : nil
    }

    /// Units after which a decimal with no whole part reads as a number; "second" is safe after digits.
    static let leadingDecimalUnits = measures.union(currencies).union(["second", "seconds", "minute", "hour"])

    /// Whether the word is a scale of a thousand or more, which a bare decimal before it is a fraction of.
    private static func isBigScale(_ key: String) -> Bool {
        NumberWords.scales[key].map { $0 >= 1000 } ?? false
    }

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
            joined(end, shapes) && (leadingDecimalUnits.contains(keys[end]) || isBigScale(keys[end]))
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
        guard let reading = digitStringAware(at: position, keys: keys, shapes: shapes) else { return nil }
        return Item(value: reading.value, text: String(reading.value), count: reading.count, spoken: true)
    }

    /// The longest cardinal at `position`, shortened by its last unit when that unit starts a string of single digits, so "eight hundred" and the digits after it stay apart.
    private static func digitStringAware(
        at position: Int, keys: [String], shapes: [WordShape]
    ) -> (value: Int, count: Int)? {
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
            return (shorter.value, shorter.count)
        }
        return (parsed.value, parsed.count)
    }

    /// Whether a meridiem stands at `index`, written as one word or said as its two letters, "p m".
    private static func isMeridiem(at index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        if meridiems.contains(keys[index]) { return true }
        return ["a", "p"].contains(keys[index]) && joined(index + 1, shapes) && keys[index + 1] == "m"
    }

    /// Whether the word at `index` follows its predecessor with no punctuation between them.
    static func joined(_ index: Int, _ shapes: [WordShape]) -> Bool {
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

    /// "march fifth", "may 2027": an ordinal day that fits the month, or a year, straight after it, unless a pronoun subject makes the word a verb.
    private static func dayFollows(_ index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard joined(index + 1, shapes), let limit = monthDays[keys[index]] else { return false }
        let ordinal = parseOrdinal(at: index + 1, keys: keys, shapes: shapes)
        guard ordinal.map({ $0.value <= limit }) == true || isYear(keys[index + 1]) else { return false }
        guard index > 0, !startsASentence(index, shapes) else { return true }
        return LexicalClass.tag(ofWordAt: index - 1, in: keys) != .pronoun
    }

    /// Whether a word is a four-digit calendar year.
    private static func isYear(_ key: String) -> Bool {
        key.count == 4 && key.allSatisfy { $0.isASCII && $0.isNumber }
            && (1900...2099).contains(Int(key) ?? 0)
    }

    /// A romanised Hindi number before an amount, unit or time word, as "paanch sau rupaye" for "500 rupaye".
    private static func hindiAmount(
        at position: Int, keys: [String], shapes: [WordShape], digits: DigitGrouping
    ) -> Phrase? {
        let fraction = NumberWords.hindiFractions[keys[position]]
        let start = fraction == nil ? position : position + 1
        guard fraction == nil || joined(start, shapes) else { return nil }
        var end = start
        while end < keys.count, end == start || joined(end, shapes), NumberWords.hindi[keys[end]] != nil {
            end += 1
            if !shapes[end - 1].suffix.isEmpty { break }
        }
        guard let read = NumberWords.hindiCardinal(keys[start..<end]) else { return nil }
        // A scale word straight after a numeral multiplies it ("5 hazaar") and is not an amount of its own.
        let scaleOnly = NumberWords.hindi[keys[start]].map { $0 >= 100 } ?? false
        guard !(scaleOnly && start > 0 && joined(start, shapes) && keys[start - 1].first?.isNumber == true)
        else { return nil }
        let unit = start + read.count
        guard joined(unit, shapes) else { return nil }
        // No clock shows past 24, so a larger number before a clock word is another word the recogniser misheard.
        guard !(hindiClockWords.contains(keys[unit]) && read.value > 24) else { return nil }
        let shared = sharedMeasures.contains(keys[unit])
        guard
            hindiMeasures.contains(keys[unit])
                || shared && !isEnglishSentence(around: position, keys: keys, shapes: shapes)
        else { return nil }
        var value = read.value
        if let fraction {
            guard let scaled = scaled(read, by: fraction, keys: keys[start...]) else { return nil }
            value = scaled
        }
        let text = NumberWords.render(value, grouping: digits, isAmount: true)
        return Phrase(text: text, count: read.count + start - position)
    }

    /// "dedh sau" is 150, "saade teen sau" 350: a fraction scales the number's one magnitude, or nil if not whole.
    private static func scaled(
        _ read: (value: Int, count: Int), by fraction: (value: Double, isOffset: Bool),
        keys: ArraySlice<String>
    ) -> Int? {
        let words = keys.prefix(read.count).compactMap { NumberWords.hindi[$0] }
        guard let magnitude = words.last, magnitude >= 100, words.filter({ $0 >= 100 }).count == 1,
            read.value % magnitude == 0
        else { return nil }
        let count = Double(read.value / magnitude)
        let total = (fraction.isOffset ? count + fraction.value : fraction.value) * Double(magnitude)
        guard fraction.isOffset || read.value == magnitude, total == total.rounded() else { return nil }
        return Int(total)
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
    static func unbroken(from start: Int, keys: [String], shapes: [WordShape]) -> ArraySlice<String> {
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
        // A digit word that opens a spoken hundred is the whole number: "one hundred" is 100, not 1 and a stray word.
        if !text.isEmpty {
            if end < keys.count, joined(end, shapes), keys[end] == "hundred",
                let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
                group.count > end - start
            {
                return Phrase(text: String(group.value), count: group.count)
            }
            return Phrase(text: text, count: end - start)
        }
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
        if groups >= 3, let suffix = preReleaseSuffix(at: end, keys: keys, shapes: shapes) {
            return Phrase(text: text + suffix.text, count: end + suffix.count - position)
        }
        return Phrase(text: text, count: end - position)
    }

    /// Identifiers a version's pre-release suffix names after "dash".
    private static let preReleaseLabels = NumberCues.words(for: .preRelease)

    /// A version's pre-release suffix: "dash rc dot one" is "-rc.1", the label alone is "-rc". The spoken dash may already be a hyphen.
    private static func preReleaseSuffix(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard start < shapes.count, shapes[start - 1].suffix.isEmpty else { return nil }
        var label = keys[start]
        var end = start + 1
        if label == "dash", shapes[start].prefix.isEmpty {
            guard joined(end, shapes) else { return nil }
            label = keys[end]
            end += 1
        } else if shapes[start].prefix != "-" {
            return nil
        }
        guard preReleaseLabels.contains(label) else { return nil }
        var text = "-" + label
        if joined(end, shapes), keys[end] == "dot" || keys[end] == "point",
            let group = digitGroup(at: end + 1, keys: keys, shapes: shapes)
        {
            text += "." + group.text
            end += 1 + group.count
        }
        return Phrase(text: text, count: end - start)
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

    /// Verbs of having, which end a label cue: a count after "has" counts the things after it and does not take the noun before it as a label.
    private static let labelBreakers: Set<String> = ["has", "have", "had"]

    /// Conjunctions that start a new conjunct: a label before one does not cue a number after it, "the code and one more".
    private static let conjunctBreakers: Set<String> = ["and", "or", "but"]

    /// Whether a label word cues the number, across a sign and English function words such as "to"; a Hindi word or a lone letter ends it.
    package static func hasLabelCue(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard position > 0, !startsASentence(position, shapes) else { return false }
        var cuePosition = position - 1
        if keys[cuePosition].count == 1, keys[cuePosition].allSatisfy(\.isLetter) { return false }
        if ["negative", "minus"].contains(keys[cuePosition]) { cuePosition -= 1 }
        while cuePosition >= 0 {
            if shapes[cuePosition].endsSentence { return false }
            let word = keys[cuePosition]
            if contextWords.contains(word) { return true }
            if labelBreakers.contains(word) || FunctionWords.isContent(word) { return false }
            if conjunctBreakers.contains(word), cuePosition > 0, !NumberWords.isNumber(keys[cuePosition - 1])
            {
                return false
            }
            if HindiWords.functionWords.contains(word), !FunctionWords.english.contains(word) { return false }
            cuePosition -= 1
        }
        return false
    }

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
            let decade = decadeValue(of: keys[position + 1])
        else { return nil }
        return Phrase(text: "\(century * 100 + decade)s", count: 2)
    }

    /// The tens a plural decade word stands for: "eighties" is 80, "tens" is 10, and "hundreds" is the century's own 0.
    private static func decadeValue(of key: String) -> Int? {
        switch key {
        case "hundreds": return 0
        case "tens": return 10
        default:
            return NumberWords.tens.first(where: {
                $0.value >= 20 && $0.value <= 90
                    && ($0.key.hasSuffix("y") ? String($0.key.dropLast()) + "ies" : $0.key + "s") == key
            })?.value
        }
    }

    /// Keeps fixed spoken idioms intact so their number words are not partially rewritten.
    /// An idiom may open on a word before the number, so the count returned is of the words from `position` on.
    private static func unchangedIdiomCount(at position: Int, keys: [String], shapes: [WordShape]) -> Int? {
        for idiom in idioms {
            for offset in 0..<idiom.count {
                let start = position - offset
                guard start >= 0, start + idiom.count <= keys.count,
                    Array(keys[start..<(start + idiom.count)]) == idiom,
                    (start + 1..<start + idiom.count).allSatisfy({ joined($0, shapes) })
                else { continue }
                return idiom.count - offset
            }
        }
        return nil
    }

    /// "two thirty", "two thirty pm", "two oh five pm", "ten am", "five o'clock"; am and pm stay separate.
    private static func time(hour: Int, at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard (1...12).contains(hour), joined(start, shapes) else { return nil }
        if let minutes = minutes(at: start, keys: keys, shapes: shapes) {
            return Phrase(text: "\(hour):\(minutes.text)", count: minutes.count)
        }
        guard isMeridiem(at: start, keys: keys, shapes: shapes) || keys[start] == "o'clock" else {
            return nil
        }
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
