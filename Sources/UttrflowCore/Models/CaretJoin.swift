/// Whether a space separates two characters that meet at a caret edge, read from one table for both edges.
enum CaretJoin {
    /// What one character is to the join beside it.
    enum CharacterClass: CaseIterable, Sendable {
        case word
        case openingBracket
        case closingBracket
        case openingQuote
        case closingQuote
        /// A currency, mention or hash sign, which leads the word after it.
        case sign
        /// A maths, dash or other symbol, which stands apart from a word on either side.
        case symbol
        /// Clause and sentence marks, which attach to the text before them.
        case mark
        case emoji
        case space
        case newline
    }

    /// The destinations that write code, where a word runs straight into the bracket after it.
    static let codeDestinations: Set<Destination> = [.codeEditor, .terminal, .sqlEditor]

    /// The classes a space may follow: what ends a run of words.
    static let separatesAfter: Set<CharacterClass> = [.word, .closingBracket, .closingQuote, .mark, .symbol, .emoji]

    /// The classes a space may precede: what starts a run of words.
    static let separatesBefore: Set<CharacterClass> = [.word, .openingBracket, .openingQuote, .sign, .symbol, .emoji]

    /// The pairs that join without a space where code is written, as a call or a subscript does.
    static let joinedInCode: Set<Pair> = [Pair(before: .word, after: .openingBracket)]

    /// Two classes that meet at an edge, the earlier one first.
    struct Pair: Hashable, Sendable {
        let before: CharacterClass
        let after: CharacterClass
    }

    /// Whether a space belongs between a character of class `before` and one of class `after` in `destination`.
    static func needsSpace(between before: CharacterClass, and after: CharacterClass, in destination: Destination)
        -> Bool
    {
        guard separatesAfter.contains(before), separatesBefore.contains(after) else { return false }
        return !(codeDestinations.contains(destination) && joinedInCode.contains(Pair(before: before, after: after)))
    }

    /// Classifies `character`; a straight quote opens only at the start or after a space or an opener.
    static func classify(_ character: Character, after previous: Character?) -> CharacterClass {
        if character.isNewline { return .newline }
        if character.isWhitespace { return .space }
        if character.isLetter || character.isNumber || character == "_" { return .word }
        if character == "\"" || character == "'" {
            let opens = previous.map { [.space, .newline, .openingBracket, .openingQuote].contains(classify($0, after: nil)) } ?? true
            return opens ? .openingQuote : .closingQuote
        }
        if openingQuotes.contains(character) { return .openingQuote }
        if closingQuotes.contains(character) { return .closingQuote }
        if marks.contains(character) || SentenceMarks.ends.contains(character) { return .mark }
        if isEmoji(character) { return .emoji }
        switch character.unicodeScalars.first?.properties.generalCategory {
        case .openPunctuation: return .openingBracket
        case .closePunctuation: return .closingBracket
        case .currencySymbol: return .sign
        default: return leadingSigns.contains(character) ? .sign : .symbol
        }
    }

    /// The signs besides currency that lead the word after them: a mention and a hash tag.
    private static let leadingSigns: Set<Character> = ["@", "#"]

    /// Curly and angle quotes that open a quotation.
    private static let openingQuotes: Set<Character> = ["\u{201C}", "\u{2018}", "\u{00AB}", "\u{2039}"]

    /// Curly and angle quotes that close a quotation.
    private static let closingQuotes: Set<Character> = ["\u{201D}", "\u{2019}", "\u{00BB}", "\u{203A}"]

    /// Clause marks that attach to the text before them, besides every script's sentence end.
    private static let marks: Set<Character> = [",", ";", ":", "%", SentenceMarks.ellipsis, "\u{060C}", "\u{3001}", "\u{FF0C}"]

    /// Whether `character` draws as a pictograph rather than as a digit or a symbol.
    static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value >= 0x1F000
        }
    }
}
