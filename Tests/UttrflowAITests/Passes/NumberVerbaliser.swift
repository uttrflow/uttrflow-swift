import Foundation

/// How a value is said aloud: the spoken variants a speaker may choose between.
struct SpokenStyle: Hashable {
    /// "one hundred and five" rather than "one hundred five".
    var and = false
    /// "a hundred" rather than "one hundred" for a leading one before a scale word.
    var leadingA = false
    /// "twenty-one" rather than "twenty one".
    var hyphen = false

    var name: String {
        [and ? "and" : nil, leadingA ? "a" : nil, hyphen ? "hyphen" : nil].compactMap(\.self)
            .joined(separator: "+").ifEmpty("plain")
    }
}

extension String {
    fileprivate func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Test-only verbaliser: writes a value out in words, every way a speaker says it.
enum NumberVerbaliser {
    static let units = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    static let scales: [(Int, String)] = [
        (1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"),
        (1000, "thousand"),
    ]

    /// A cardinal from 0 up to a trillion in words.
    static func cardinal(_ value: Int, style: SpokenStyle = SpokenStyle()) -> String {
        if value == 0 { return "zero" }
        var words: [String] = []
        var rest = value
        for (size, name) in scales where rest >= size {
            words.append(underThousand(rest / size, style: style, leading: words.isEmpty) + " " + name)
            rest %= size
        }
        if rest > 0 {
            let andBeforeTail = style.and && !words.isEmpty && rest < 100
            words.append(
                (andBeforeTail ? "and " : "") + underThousand(rest, style: style, leading: words.isEmpty))
        }
        return words.joined(separator: " ")
    }

    static func underThousand(_ value: Int, style: SpokenStyle, leading: Bool) -> String {
        guard value >= 100 else { return underHundred(value, style: style) }
        let head = value / 100 == 1 && style.leadingA && leading ? "a" : units[value / 100]
        let tail = value % 100
        guard tail > 0 else { return head + " hundred" }
        return head + " hundred " + (style.and ? "and " : "") + underHundred(tail, style: style)
    }

    static func underHundred(_ value: Int, style: SpokenStyle) -> String {
        if value < 20 { return units[value] }
        let unit = value % 10
        guard unit > 0 else { return tens[value / 10] }
        return tens[value / 10] + (style.hyphen ? "-" : " ") + units[unit]
    }

    /// Two digits as a year half or clock minute says them: "oh five", "zero five", "thirty".
    static func pair(_ value: Int, zero: String) -> String {
        value < 10 ? zero + " " + units[value] : underHundred(value, style: SpokenStyle())
    }

    /// A year from 1900 to 2099 as people say it.
    static func year(_ value: Int, zero: String) -> String {
        let century = value / 100
        let rest = value % 100
        if century == 20 && rest < 10 {
            return rest == 0 ? "two thousand" : "two thousand " + (zero == "and" ? "and " : "") + units[rest]
        }
        if rest == 0 { return underHundred(century, style: SpokenStyle()) + " hundred" }
        return underHundred(century, style: SpokenStyle()) + " "
            + pair(rest, zero: zero == "and" ? "oh" : zero)
    }

    /// An ordinal from 1 up, said in words: "twenty first", "one hundred and twelfth".
    static func ordinal(_ value: Int, style: SpokenStyle = SpokenStyle()) -> String {
        let spoken = cardinal(value, style: style)
        let separators = CharacterSet(charactersIn: " -")
        guard let cut = spoken.rangeOfCharacter(from: separators, options: .backwards) else {
            return ordinalWord(spoken)
        }
        return String(spoken[..<cut.upperBound]) + ordinalWord(String(spoken[cut.upperBound...]))
    }

    static func ordinalWord(_ word: String) -> String {
        let irregular = [
            "one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
            "nine": "ninth", "twelve": "twelfth",
        ]
        if let form = irregular[word] { return form }
        if word.hasSuffix("y") { return word.dropLast() + "ieth" }
        return word + "th"
    }

    /// The numeral the pass writes for a cardinal in prose: a comma every three digits from ten thousand.
    static func numeral(_ value: Int) -> String {
        guard value >= 10_000 else { return String(value) }
        var digits = Array(String(value))
        var index = digits.count - 3
        while index > 0 {
            digits.insert(",", at: index)
            index -= 3
        }
        return String(digits)
    }

    static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
