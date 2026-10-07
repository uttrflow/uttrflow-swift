import NaturalLanguage

/// The one owner of whether a mark may follow a word, read as rows of the word's state against the mark.
public enum MarkLegality {
    /// A mark a pass may add or keep after a word.
    public enum Mark: CaseIterable, Sendable {
        case stop, question, exclamation, comma, colon
    }

    /// What the word before a position is, as far as closing a clause goes.
    public enum TokenState: CaseIterable, Sendable {
        /// An article, possessive, conjunction, preposition that takes an object, or copula: "the", "and", "of".
        case leadsOn
        /// A title or Latin lead-in, which opens onto what follows: "Dr.", "e.g.".
        case leadingAbbreviation
        /// An abbreviation that may close a sentence: "etc.", "p.m.".
        case abbreviation
        /// A word made of digits, such as "42" or "3.5".
        case number
        /// A URL, address, path or other technical token, whose own dots are not marks.
        case technical
        /// A word that already ends in a closing bracket or quote.
        case closer
        /// Marks with no letter or digit.
        case symbol
        /// Any other word.
        case word
    }

    /// The table's answer; `unknown` always leaves an existing mark as it is.
    public enum Verdict: Sendable {
        case legal, illegal, unknown
    }

    /// The state of `token`, read without any mark a pass is about to add after it.
    public static func state(of token: String) -> TokenState {
        let shape = WordShape(token)
        guard shape.core.contains(where: { $0.isLetter || $0.isNumber }) else { return .symbol }
        if shape.suffix.last.map(closers.contains) == true { return .closer }
        if shape.core.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) { return .number }
        if TechnicalToken.classify(token) != nil { return .technical }
        if let kind = Abbreviations.kind(of: shape.core), kind != .initial {
            return kind.leadsOn ? .leadingAbbreviation : .abbreviation
        }
        return FunctionWords.leadsOn(shape.core) ? .leadsOn : .word
    }

    /// Whether `mark` may stand straight after `token`.
    public static func verdict(_ mark: Mark, after token: String) -> Verdict {
        verdict(mark, after: state(of: token))
    }

    /// Whether `mark` may stand after a word in `state`; a pair with no row is unknown.
    public static func verdict(_ mark: Mark, after state: TokenState) -> Verdict {
        table[state]?[mark] ?? .unknown
    }

    /// Whether `words` read as a closed sentence: illegal when the last word leaves it open, legal when it can end and a verb was said.
    public static func sentenceCompleteness(_ words: [String]) -> Verdict {
        guard let last = words.last else { return .unknown }
        let ending = verdict(.stop, after: last)
        guard ending == .legal else { return ending }
        let bare = words.map { WordShape($0).core }
        return LexicalClass.tags(ofWords: bare).contains(.verb) ? .legal : .unknown
    }

    private static let closers: Set<Character> = [")", "]", "}", "\"", "\u{201D}", "\u{2019}", "'"]

    private static let ends: [Mark: Verdict] = [.stop: .legal, .question: .legal, .exclamation: .legal]
    private static let opens: [Mark: Verdict] = [
        .stop: .illegal, .question: .illegal, .exclamation: .illegal, .colon: .illegal,
    ]

    /// One row per state; a new case is a new row or cell, never a list inside a pass.
    private static let table: [TokenState: [Mark: Verdict]] = [
        .leadsOn: opens,
        .leadingAbbreviation: opens,
        .abbreviation: ends.merging([.comma: .legal]) { first, _ in first },
        .number: ends.merging([.comma: .legal, .colon: .legal]) { first, _ in first },
        .closer: ends.merging([.comma: .legal]) { first, _ in first },
        .word: ends.merging([.comma: .legal]) { first, _ in first },
    ]
}
