// The rules both sides go through before a word error rate is counted.
private import Foundation

/// Whether any Devanagari is present, the only script distinction the product turns on.
public enum Script: String, Sendable, Equatable, CaseIterable, Codable {
    case latin
    case devanagari

    private static let devanagariRange: ClosedRange<UInt32> = 0x0900...0x097F

    public static func of(_ text: String) -> Script {
        text.unicodeScalars.contains { devanagariRange.contains($0.value) } ? .devanagari : .latin
    }
}

/// One thing done to both sides before comparing; printed beside every rate because it decides the rate.
public enum NormalisationRule: String, Sendable, Equatable, CaseIterable, Codable {
    /// Lowercases everything.
    case caseFolding
    /// Removes apostrophes rather than treating them as separators.
    case apostropheFolding
    /// Splits on anything that is neither letter nor digit, except a full stop or underscore joining two.
    case punctuationAsSeparators
    /// Rewrites Devanagari digits as Western ones.
    case devanagariDigits
    /// Rewrites number words as digits.
    case numberWords
    /// Joins a spoken decimal — "3 point 11" — back into one token.
    case spokenDecimalPoint

    public var explanation: String {
        switch self {
        case .caseFolding:
            "Case is folded. A recogniser capitalises by guesswork, and a capital is not a word."
        case .apostropheFolding:
            "Apostrophes are dropped, so \"don't\" and \"dont\" are one word rather than two errors."
        case .punctuationAsSeparators:
            """
            Punctuation separates words, except a full stop or underscore between two \
            alphanumerics — splitting "3.11" or "get_user" would manufacture an error out of \
            a term the product has to keep whole.
            """
        case .devanagariDigits:
            "Devanagari digits are folded to Western ones; only the glyph differs."
        case .numberWords:
            """
            Number words become digits — "twenty five" to 25 — because a recogniser picks \
            between the two spellings freely and the choice is not a mishearing.
            """
        case .spokenDecimalPoint:
            """
            A digit, "point" and a digit become a decimal, so a recogniser that spells out \
            "3 point 11" is not charged for hearing it correctly.
            """
        }
    }
}

/// Turns text into the words a word error rate is counted over. See Docs/eval-methodology.md.
public struct TextNormaliser: Sendable, Equatable {
    public let rules: [NormalisationRule]

    public init(rules: [NormalisationRule]) {
        self.rules = rules
    }

    /// What every reported score is measured under, unless a caller says otherwise.
    public static let standard = TextNormaliser(rules: NormalisationRule.allCases)

    /// The words to compare, in order.
    public func words(_ text: String) -> [String] {
        var tokens = split(applyingCharacterRules(to: text))
        if rules.contains(.numberWords) { tokens = foldNumberWords(tokens) }
        if rules.contains(.spokenDecimalPoint) { tokens = joinSpokenDecimals(tokens) }
        return tokens
    }

    /// The normalised text as one string, for showing a person what was compared.
    public func normalised(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    // MARK: Character-level rules

    private func applyingCharacterRules(to text: String) -> String {
        var result = text
        if rules.contains(.caseFolding) { result = result.lowercased() }
        if rules.contains(.apostropheFolding) {
            // Both the typewriter apostrophe and the one a recogniser prefers.
            result = result.replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\u{2019}", with: "")
        }
        if rules.contains(.devanagariDigits) { result = String(result.map(westernDigit)) }
        return result
    }

    private func westernDigit(_ character: Character) -> Character {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
            (0x0966...0x096F).contains(scalar.value)
        else { return character }
        return Character(UnicodeScalar(scalar.value - 0x0966 + 48) ?? scalar)
    }

    /// Splits into words, keeping a full stop or underscore that joins two alphanumerics.
    private func split(_ text: String) -> [String] {
        guard rules.contains(.punctuationAsSeparators) else {
            return text.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        let characters = Array(text)
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if character.isLetter || character.isNumber {
                current.append(character)
                continue
            }
            let joinsIdentifier = character == "." || character == "_"
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let between =
                (previous?.isLetter ?? false) || (previous?.isNumber ?? false)
                ? (next?.isLetter ?? false) || (next?.isNumber ?? false) : false
            if joinsIdentifier, between {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: Number rules

    /// Maps a number word to its digits, with a second pass for "twenty five".
    private func foldNumberWords(_ tokens: [String]) -> [String] {
        var folded: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let tens = NumberWords.tens[token], index + 1 < tokens.count,
                let unit = NumberWords.units[tokens[index + 1]], unit > 0
            {
                folded.append(String(tens + unit))
                index += 2
                continue
            }
            folded.append(NumberWords.digits[token].map(String.init) ?? token)
            index += 1
        }
        return folded
    }

    /// Joins "3 point 11" into "3.11", only when both neighbours are entirely digits.
    private func joinSpokenDecimals(_ tokens: [String]) -> [String] {
        var joined: [String] = []
        var index = 0
        while index < tokens.count {
            if tokens[index] == "point", let previous = joined.last, index + 1 < tokens.count,
                previous.allSatisfy(\.isNumber), tokens[index + 1].allSatisfy(\.isNumber),
                !previous.isEmpty, !tokens[index + 1].isEmpty
            {
                joined[joined.count - 1] = previous + "." + tokens[index + 1]
                index += 2
                continue
            }
            joined.append(tokens[index])
            index += 1
        }
        return joined
    }
}

/// The number words the normaliser knows: English to ninety-nine plus the Devanagari spellings.
enum NumberWords {
    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9,
    ]

    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]

    /// Everything that maps on its own; "एक" and "दो" are left out because they are also "a" and "give".
    static let digits: [String: Int] =
        units.merging(tens) { first, _ in first }
        .merging([
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        ]) { first, _ in first }
        .merging([
            "तीन": 3, "चार": 4, "पाँच": 5, "पांच": 5, "छह": 6, "सात": 7, "आठ": 8, "नौ": 9,
            "दस": 10, "बीस": 20, "तीस": 30, "चालीस": 40, "पचास": 50,
        ]) { first, _ in first }
}

extension String {
    /// The text in Latin letters via ICU, a last resort that inflates the rate; see Docs/eval-methodology.md.
    var transliteratedToLatin: String {
        let latin = applyingTransform(.toLatin, reverse: false) ?? self
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }
}
