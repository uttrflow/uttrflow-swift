// What a wrong swap between two readings costs, read by both of `DoubtPolicy`'s directions.
import UttrflowCore
import UttrflowDictionary

/// The cost class of confusing one reading for another: a number or a negation turns the meaning, a spelling does not. See Docs/ai-correction-thresholds.md.
public enum ConfusionCost: Int, Sendable, Comparable, CaseIterable {
    /// The readings differ in spelling or a word whose loss the reader repairs.
    case cosmetic
    /// The readings differ in a quantity: "fifteen" for "fifty", "hundred" for "thousand".
    case numberFlip
    /// One reading reverses the other: "can" for "can't", a dropped "not".
    case meaningFlip

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The class of confusing `heard` with `candidate`, the costlier side deciding.
    public static func of(heard: String, candidate: String) -> ConfusionCost {
        let heardWords = spokenWords(heard)
        let candidateWords = spokenWords(candidate)
        if negations(in: heardWords) != negations(in: candidateWords) { return .meaningFlip }
        if quantities(in: heardWords) != quantities(in: candidateWords) { return .numberFlip }
        return .cosmetic
    }

    /// Lowercased words split on spaces with apostrophes kept, so "can't" stays one negator.
    private static func spokenWords(_ text: String) -> [String] {
        WordTokens.words(text.lowercased(), .display).map {
            $0.filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}" }
                .replacingOccurrences(of: "\u{2019}", with: "'")
        }
    }

    /// How many words reverse the sentence, so a negator swapped for another is not a flip.
    private static func negations(in words: [String]) -> Int {
        words.filter { MeaningPreservationGuard.isNegation($0) }.count
    }

    /// The quantity words in order, so any change to them is a number flip.
    private static func quantities(in words: [String]) -> [String] {
        words.filter { $0.allSatisfy(\.isNumber) || quantityWords.contains($0) }
    }

    /// Words that state an amount; "a"/"an" and "one" are left to the cosmetic class until measured error promotes them.
    static let quantityWords: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
        "million", "billion", "half", "quarter", "dozen", "percent",
    ]
}
