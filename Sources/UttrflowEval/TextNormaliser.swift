// The rules both sides go through before a word error rate is counted.
private import Foundation
import UttrflowCore

/// Whether any Devanagari is present, the only script distinction the product turns on.
public enum Script: String, Sendable, Equatable, CaseIterable, Codable {
    case latin
    case devanagari

    public static func of(_ text: String) -> Script {
        Romaniser.containsDevanagari(text) ? .devanagari : .latin
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
            return WordTokens.words(text, .display)
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

    /// Number words below a hundred, English and Devanagari, less the Hindi words as often ordinary ones.
    static let numberWordDigits: [String: Int] = NumberWords.english
        .merging(NumberWords.hindi.filter { Script.of($0.key) == .devanagari }) { first, _ in first }
        .filter { $0.value < 100 && !NumberWords.hindiHomographs.contains($0.key) }

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
            folded.append(Self.numberWordDigits[token].map(String.init) ?? token)
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

extension String {
    /// The text in Latin letters via ICU, a last resort that inflates the rate; see Docs/eval-methodology.md.
    var transliteratedToLatin: String {
        let latin = applyingTransform(.toLatin, reverse: false) ?? self
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }
}
