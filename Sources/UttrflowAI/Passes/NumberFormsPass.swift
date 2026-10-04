import Foundation
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
    static let currencies: Set<String> = ["rupee", "rupees", "dollar", "dollars", "euro", "euros"]
    static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m"]
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
                let last = position + 1
                draft.replace(
                    at: live[position], with: shapes[position].prefix + time.text + shapes[last].suffix,
                    by: Self.id)
                draft.remove(at: live[last], by: Self.id)
                position += 2
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

    /// Reads `H.MM` as a clock only with a meridiem or an `at`/`by` cue.
    private static func dottedTime(at position: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard position + 1 < shapes.count,
            let hour = Int(keys[position]), (1...12).contains(hour),
            shapes[position].core.allSatisfy(\.isNumber),
            let minute = Int(keys[position + 1]), (0...59).contains(minute),
            shapes[position + 1].core.count == 2,
            shapes[position].suffix == ".", shapes[position + 1].suffix.isEmpty,
            joined(position + 1, shapes)
        else { return nil }
        let hasMeridiem =
            position + 2 < keys.count && joined(position + 2, shapes)
            && meridiems.contains(keys[position + 2].trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        let hasCue =
            position > 0 && !startsASentence(position, shapes)
            && ["at", "by"].contains(keys[position - 1])
        guard hasMeridiem || hasCue else { return nil }
        return Phrase(text: "\(hour):\(keys[position + 1])", count: 2)
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
            bareMonthIsValid(at: position, keys: keys, shapes: shapes)
        {
            return Phrase(text: "\(shapes[position].core) \(ordinal.value)", count: ordinal.count + 1)
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
            if !hasOf, !bareMonthIsValid(at: end, keys: keys, shapes: shapes) {
                return nil
            }
            guard policy == .always || ordinal.value >= 10 else { return nil }
            let month = WordShape.capitalised(keys[end])
            let preposition = hasOf ? " of" : ""
            return Phrase(
                text: "\(ordinal.value)\(ordinalSuffix(ordinal.value))\(preposition) \(month)",
                count: end - position + 1)
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
                text += " of " + NumberWords.render(following.value, grouped: false)
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
            let beforeCurrency = joined(end, shapes) && currencies.contains(keys[end])
            guard policy == .always || inContext || value >= 10 || beforeCurrency else { return nil }
            // The destination says whether digits are grouped; a context word still runs its own together.
            text = NumberWords.render(value, grouped: digits == .thousands && !inContext)
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

    /// Requires temporal evidence when the hour and minute form one phrase.
    private static func timeAcceptable(
        position: Int, minuteStart: Int, minuteEnd: Int,
        keys: [String], shapes: [WordShape]
    ) -> Bool {
        let hasBeforeCue =
            position > 0 && !startsASentence(position, shapes)
            && ["at", "by", "until", "from"].contains(keys[position - 1])
        let hasAfterCue =
            minuteEnd < shapes.count && joined(minuteEnd, shapes)
            && (meridiems.contains(keys[minuteEnd]) || keys[minuteEnd] == "o'clock")
        return hasBeforeCue || hasAfterCue
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

    /// Whether a bare month is capitalized when its name could also be an ordinary word.
    private static func bareMonthIsValid(at index: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard keys[index] == "may" || keys[index] == "march" else { return true }
        return shapes[index].core == WordShape.capitalised(keys[index])
    }

    /// The keys from `start` up to the first word that carries punctuation.
    private static func unbroken(from start: Int, keys: [String], shapes: [WordShape]) -> ArraySlice<String> {
        var end = start
        while end < keys.count, end == start || joined(end, shapes) {
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

    /// Joins three or more digit words with a nonzero one among them and no scale after them.
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
        return Phrase(text: text, count: end - start)
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
        if keys[start] == "oh" || keys[start] == "zero", joined(start + 1, shapes),
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
            if joined(ordinalPosition, shapes), let unit = ordinalUnits[keys[ordinalPosition]], unit < 10 {
                return (cardinal.value + unit, count + 1)
            }
        }
        return ordinalUnits[keys[position]].map { ($0, 1) }
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
