/// What the caret stands inside, derived once from the text before it so every pass reads the same answer.
public struct CaretStructure: Sendable, Equatable {
    /// A bracket opened before the caret and not closed there.
    public struct OpenBracket: Sendable, Equatable {
        /// The opening character: `(`, `[` or `{`.
        public let opener: Character
        /// Whether it was opened on the line the caret sits on.
        public let isOnCaretLine: Bool
    }

    /// The text from the last line break to the caret.
    public let caretLine: Substring
    /// Brackets still open at the caret, innermost last.
    public let openBrackets: [OpenBracket]
    /// Whether a straight, curly or guillemet quotation is still open at the caret.
    public let hasOpenQuotation: Bool

    /// Reads the structure off the text before the caret.
    public init(precedingText text: String) {
        caretLine = Self.caretLine(of: text)
        var brackets: [(closer: Character, opener: Character, line: Int)] = []
        var line = 0
        var doubleQuoteIsOpen = false
        var singleQuoteIsOpen = false
        var curlyDoubleQuoteIsOpen = false
        var curlySingleQuoteIsOpen = false
        var guillemetIsOpen = false
        let characters = Array(text)
        var precedingBackslashes = 0

        for (offset, character) in characters.enumerated() {
            let previous = offset > 0 ? characters[offset - 1] : nil
            let next = offset + 1 < characters.count ? characters[offset + 1] : nil
            let isInsideWord = previous?.isLetter == true && next?.isLetter == true
            let isEscaped = !precedingBackslashes.isMultiple(of: 2)
            switch character {
            case "(": brackets.append((")", character, line))
            case "[": brackets.append(("]", character, line))
            case "{": brackets.append(("}", character, line))
            case ")", "]", "}":
                if brackets.last?.closer == character { brackets.removeLast() }
            case "\"" where !isEscaped: doubleQuoteIsOpen.toggle()
            // An apostrophe inside a word is not a quotation mark.
            case "'" where !isEscaped && !isInsideWord: singleQuoteIsOpen.toggle()
            case "\u{201C}": curlyDoubleQuoteIsOpen = true
            case "\u{201D}": curlyDoubleQuoteIsOpen = false
            case "\u{2018}": curlySingleQuoteIsOpen = true
            case "\u{2019}" where !isInsideWord: curlySingleQuoteIsOpen = false
            case "\u{00AB}": guillemetIsOpen = true
            case "\u{00BB}": guillemetIsOpen = false
            default: if character.isNewline { line += 1 }
            }
            precedingBackslashes = character == "\\" ? precedingBackslashes + 1 : 0
        }
        openBrackets = brackets.map { OpenBracket(opener: $0.opener, isOnCaretLine: $0.line == line) }
        hasOpenQuotation =
            doubleQuoteIsOpen || singleQuoteIsOpen || curlyDoubleQuoteIsOpen || curlySingleQuoteIsOpen
            || guillemetIsOpen
    }

    /// Whether any bracket or quotation opened before the caret is still open.
    public var hasOpenDelimiter: Bool { !openBrackets.isEmpty || hasOpenQuotation }

    /// Whether a bracket opened on the caret's own line is still open.
    public var hasOpenBracketOnCaretLine: Bool { openBrackets.contains(where: \.isOnCaretLine) }

    /// The text after the last line break; a CRLF pair is one `Character`, so it is one break.
    public static func caretLine(of text: String) -> Substring {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
    }
}
