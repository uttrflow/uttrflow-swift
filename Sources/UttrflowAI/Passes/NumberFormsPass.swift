import Foundation
import NaturalLanguage
public import UttrflowCore

/// Writes spoken numbers as numerals, as many of them as the place asks for. See `Docs/cleanup.md`.
public struct NumberFormsPass: PieceCleaningPass {
    public static let id: PassID = .numberForms

    /// Which spoken numbers this place wants as numerals.
    let policy: NumberPolicy

    /// How this place writes a numeral's digits; somewhere machine-read wants no separators in them.
    let digits: DigitGrouping

    /// Words after which a lone digit is a numeral, digit groups run together, and no separator is used.
    static let contextWords: Set<String> = [
        "port", "version", "extension", "page", "chapter", "step", "number", "line", "section", "figure",
        "table", "level", "room", "floor", "route", "flight", "interstate", "highway", "bus", "gate",
    ]
    static let currencies: Set<String> = [
        "rupee", "rupees", "dollar", "dollars", "euro", "euros", "pound", "pounds",
    ]
    static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m"]
    /// The words a speaker uses for the leading zero of a clock minute.
    static let clockZeros: Set<String> = ["oh", "o", "zero"]
    static let idioms: [[String]] = [["twenty", "four", "seven"], ["fifty", "fifty"]]
    static let monthDays: [String: Int] = [
        "january": 31, "february": 29, "march": 31, "april": 30, "may": 31, "june": 30,
        "july": 31, "august": 31, "september": 30, "october": 31, "november": 30, "december": 31,
    ]
    static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
        "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "thirtieth": 30,
    ]
    /// Other currencies and units with no second meaning; "pound", "feet" and "second" stay out.
    static let measures: Set<String> = [
        "yen", "dirham", "dirhams", "franc", "francs", "kilometre", "kilometres", "kilometer", "kilometers",
        "kilogram", "kilograms", "metre", "metres", "meter", "meters", "litre", "litres", "liter", "liters",
        "minutes", "hours",
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
        let live = draft.presentIndices
        let shapes = live.map { draft.shape(at: $0) }
        let keys = shapes.map(\.key)
        var position = 0
        while position < live.count {
            if let percentile = Self.percentile(
                at: position, keys: keys, shapes: shapes, policy: policy, digits: digits)
            {
                let last = position + percentile.count - 1
                let text = shapes[position].prefix + "p" + percentile.text + shapes[last].suffix
                draft.replace(at: live[position], with: text, by: Self.id)
                for index in live[(position + 1)..<(last + 1)] { draft.remove(at: index, by: Self.id) }
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
                    at: position, keys: keys, shapes: shapes, policy: policy, digits: digits)
            else {
                position += Self.parseOrdinal(at: position, keys: keys, shapes: shapes)?.count ?? 1
                continue
            }
            let last = position + phrase.count - 1
            let text = shapes[position].prefix + phrase.text + shapes[last].suffix
            draft.replace(at: live[position], with: text, by: Self.id)
            for index in live[(position + 1)..<(last + 1)] { draft.remove(at: index, by: Self.id) }
            position += phrase.count
        }
        return draft
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
        let shapes = text.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)) }
        let keys = shapes.map(\.key)
        let clocks = shapes.indices.filter { dottedTime(at: $0, keys: keys, shapes: shapes) != nil }
        return Set(clocks.map { shapes[$0].core })
    }

    /// Writes one `H.MM` word as `H:MM` only with a meridiem or an `at`/`by` cue; only a cue reads past 12.
    private static func dottedTime(at position: Int, keys: [String], shapes: [WordShape]) -> String? {
        let parts = keys[position].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, shapes[position].prefix.isEmpty,
            parts[0].allSatisfy(\.isNumber), let hour = Int(parts[0]), (0...23).contains(hour),
            parts[1].count == 2, parts[1].allSatisfy(\.isNumber), let minute = Int(parts[1]),
            (0...59).contains(minute)
        else { return nil }
        let hasMeridiem =
            shapes[position].suffix.isEmpty && joined(position + 1, shapes)
            && meridiems.contains(keys[position + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        let hasCue =
            position > 0 && !startsASentence(position, shapes)
            && ["at", "by"].contains(keys[position - 1])
        guard hasCue || (hasMeridiem && (1...12).contains(hour)) else { return nil }
        return "\(hour):\(parts[1])"
    }

    /// The numeral for the number phrase starting at `position`, or nil when the words stay as they are.
    static func phrase(
        at position: Int, keys: [String], shapes: [WordShape], policy: NumberPolicy = .fromTen,
        digits: DigitGrouping = .thousands
    ) -> Phrase? {
        if keys[position] == "plus", joined(position + 1, shapes),
            let run = spokenDigitRun(at: position + 1, keys: keys, shapes: shapes)
        {
            return Phrase(text: "+" + run.text, count: run.count + 1)
        }
        if let date = numericDate(at: position, keys: keys, shapes: shapes) { return date }
        if let clock = cuedClock(at: position, keys: keys, shapes: shapes) { return clock }
        if let clock = twentyFourHourClock(at: position, keys: keys, shapes: shapes) { return clock }
        if let run = spokenDigitRun(at: position, keys: keys, shapes: shapes) { return run }
        if let decade = decade(at: position, keys: keys, shapes: shapes) {
            return decade
        }

        if (keys[position] == "negative" || keys[position] == "minus"), joined(position + 1, shapes) {
            if let numeral = NumberWords.digits(keys[position + 1]) {
                return Phrase(text: "-" + numeral, count: 2)
            }
            if let magnitude = phrase(
                at: position + 1, keys: keys, shapes: shapes, policy: policy, digits: digits)
            {
                return Phrase(text: "-" + magnitude.text, count: magnitude.count + 1)
            }
            return nil
        }

        guard !finishesAScale(at: position, keys: keys, shapes: shapes) else { return nil }
        if let limit = monthDays[keys[position]], joined(position + 1, shapes),
            let ordinal = parseOrdinal(at: position + 1, keys: keys, shapes: shapes),
            ordinal.value <= limit, policy == .always || ordinal.value >= 10,
            monthIsDated(at: position, keys: keys, shapes: shapes)
        {
            let day = Phrase(
                text: "\(WordShape.capitalised(keys[position])) \(ordinal.value)", count: ordinal.count + 1)
            return withYear(day, at: position, order: .monthFirst, keys: keys, shapes: shapes)
        }
        if let ordinal = parseOrdinal(at: position, keys: keys, shapes: shapes) {
            if ordinal.value >= 21,
                !isDateShapedOrdinal(at: position, ordinal: ordinal, keys: keys)
            {
                return Phrase(
                    text: "\(ordinal.value)\(ordinalSuffix(ordinal.value))", count: ordinal.count)
            }
            var end = position + ordinal.count
            guard joined(end, shapes) else { return nil }
            let hasOf = keys[end] == "of"
            if hasOf { end += 1 }
            guard joined(end, shapes), let limit = monthDays[keys[end]], ordinal.value <= limit else {
                return nil
            }
            if !hasOf, !monthIsDated(at: end, keys: keys, shapes: shapes) {
                return nil
            }
            guard policy == .always || ordinal.value >= 10 else { return nil }
            let month = WordShape.capitalised(keys[end])
            let preposition = hasOf ? " of" : ""
            let day = Phrase(
                text: "\(ordinal.value)\(ordinalSuffix(ordinal.value))\(preposition) \(month)",
                count: end - position + 1)
            return withYear(day, at: position, order: .dayFirst, keys: keys, shapes: shapes)
        }
        guard let item = item(at: position, keys: keys, shapes: shapes) else { return nil }
        let contextPosition =
            position > 0 && ["negative", "minus"].contains(keys[position - 1])
            ? position - 2 : position - 1
        let inContext =
            contextPosition >= 0 && !startsASentence(position, shapes)
            && contextWords.contains(keys[contextPosition])
        var end = position + item.count
        var text = item.text
        var isPhrase = false

        while joined(end, shapes), keys[end] == "point",
            let group = digitGroup(at: end + 1, keys: keys, shapes: shapes)
        {
            text += "." + group.text
            end += 1 + group.count
            isPhrase = true
        }
        if joined(end, shapes), keys[end] == "percent" {
            text += "%"
            end += 1
            isPhrase = true
        } else if joined(end, shapes), keys[end] == "per", joined(end + 1, shapes), keys[end + 1] == "cent" {
            text += "%"
            end += 2
            isPhrase = true
        }
        if !isPhrase, let value = item.value, !inContext {
            if let year = year(after: value, at: end, keys: keys, shapes: shapes) {
                text = year.text
                end += year.count
                isPhrase = true
            } else if let time = time(hour: value, at: end, keys: keys, shapes: shapes),
                timeAcceptable(
                    position: position, minuteStart: end, minuteEnd: end + time.count,
                    keys: keys, shapes: shapes
                )
            {
                text = time.text
                end += time.count
                isPhrase = true
            }
        }
        if !isPhrase, !inContext, item.spoken, item.count == 1,
            let hundred = NumberWords.colloquialHundred(unbroken(from: position, keys: keys, shapes: shapes)),
            readsAsOneQuantity(hundred, at: position, keys: keys, shapes: shapes)
        {
            text = String(hundred.value)
            end = position + hundred.count
            isPhrase = true
        }
        if !isPhrase, inContext, item.spoken {
            if joined(end, shapes), keys[end] == "of",
                let following = NumberWords.cardinal(unbroken(from: end + 1, keys: keys, shapes: shapes))
            {
                text += " of " + NumberWords.render(following.value, grouping: .none)
                end += following.count + 1
                isPhrase = true
            } else {
                while joined(end, shapes),
                    let group = NumberWords.cardinal(unbroken(from: end, keys: keys, shapes: shapes))
                {
                    text += String(group.value)
                    end += group.count
                    isPhrase = true
                }
            }
        }
        if !isPhrase, item.spoken, let value = item.value {
            let beforeAmount =
                joined(end, shapes) && (currencies.contains(keys[end]) || measures.contains(keys[end]))
                || completesAmount(at: position, keys: keys, shapes: shapes)
            guard policy == .always || inContext || value >= 10 || beforeAmount else { return nil }
            // The destination says whether digits are grouped; a context word still runs its own together.
            text = NumberWords.render(value, grouping: inContext ? .none : digits)
        } else if !isPhrase {
            return nil
        }
        return Phrase(text: text, count: end - position)
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

    /// A cued time whose minutes open with a spoken zero, read before the same words can join as a digit string.
    private static func cuedClock(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let hour = NumberWords.cardinal(keys[position...position])?.value,
            position + 1 < keys.count, clockZeros.contains(keys[position + 1]),
            let time = time(hour: hour, at: position + 1, keys: keys, shapes: shapes), time.count == 2
        else { return nil }
        let end = position + 1 + time.count
        guard !(joined(end, shapes) && singleDigit(keys[end]) != nil),
            timeAcceptable(
                position: position, minuteStart: position + 1, minuteEnd: end, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: time.text, count: end - position)
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

    /// Requires a time cue, or a sentence end after the minute, when the hour and minute form one phrase.
    private static func timeAcceptable(
        position: Int, minuteStart: Int, minuteEnd: Int,
        keys: [String], shapes: [WordShape]
    ) -> Bool {
        let hasBeforeCue = hasTimeCue(before: position, keys: keys, shapes: shapes)
        let endsTheSentence = minuteEnd >= shapes.count || shapes[minuteEnd - 1].endsSentence
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

    private static func singleDigit(_ key: String) -> String? {
        NumberWords.spokenDigit(key).map(String.init)
    }

    /// Joins three or more digit words with a nonzero one among them, no scale after them, and a cue before a count.
    private static func spokenDigitRun(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard let first = singleDigit(keys[start]) else { return nil }
        var text = first
        var end = start + 1
        while joined(end, shapes), let digit = singleDigit(keys[end]) {
            text.append(digit)
            end += 1
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
    static let digitCues: Set<String> = contextWords.union([
        "is", "code", "pin", "passcode", "password", "otp", "plus", "dial", "call", "on", "at", "was",
    ])

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

    private static func ordinalSuffix(_ value: Int) -> String {
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
            let year = year(after: century, at: start + 1, keys: keys, shapes: shapes)
        else { return nil }
        return Phrase(text: year.text, count: year.count + 1)
    }

    /// "twenty twenty four" and "nineteen ninety nine", from a spoken 19 or 20 and a spoken 10 to 99.
    private static func year(
        after century: Int, at start: Int, keys: [String], shapes: [WordShape]
    ) -> Phrase? {
        guard century == 19 || century == 20, joined(start, shapes),
            let rest = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
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
            cardinal.value >= 20
        {
            var ordinalPosition = position + cardinal.count
            var count = cardinal.count
            if joined(ordinalPosition, shapes), keys[ordinalPosition] == "and",
                joined(ordinalPosition + 1, shapes)
            {
                ordinalPosition += 1
                count += 1
            }
            if joined(ordinalPosition, shapes), let unit = ordinalUnits[keys[ordinalPosition]], unit < 10,
                !isHouseNumber(endingAt: position + cardinal.count - 1, keys: keys, shapes: shapes)
            {
                return (cardinal.value + unit, count + 1)
            }
        }
        return ordinalUnits[keys[position]].map { ($0, 1) }
    }

    /// Whether a number ending on a scale word is a house number, because a unit ordinal and a street word follow it.
    private static func isHouseNumber(endingAt last: Int, keys: [String], shapes: [WordShape]) -> Bool {
        NumberWords.scales[keys[last]] != nil && joined(last + 1, shapes) && joined(last + 2, shapes)
            && streetWords.contains(keys[last + 2])
    }

    /// Keeps date-like and interrupted date forms intact for the existing date parser to handle.
    private static func isDateShapedOrdinal(
        at position: Int, ordinal: (value: Int, count: Int), keys: [String]
    ) -> Bool {
        let end = position + ordinal.count
        guard end < keys.count else { return false }
        return keys[end] == "of" || monthDays[keys[end]] != nil
    }
}
