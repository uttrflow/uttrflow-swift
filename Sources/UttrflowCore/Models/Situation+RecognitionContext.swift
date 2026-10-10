extension Situation {
    /// The prose before the caret the recogniser may be conditioned on, or `nil` when none is fit.
    ///
    /// The only producer of the recogniser's lead-in. See `Docs/speech-vocabulary-prompt.md`.
    public var recognitionContext: String? {
        guard let slice = app.recognitionContext else { return nil }
        // Where the whole line is not prose, none of it is: a cell, a query, a terminal's scrollback.
        switch destination {
        case .spreadsheet, .sqlEditor, .terminal: return nil
        case .document, .codeEditor, .messaging, .email, .plain: break
        }
        let region = CaretStructure.region(
            precedingText: app.precedingText.map(InsertionPoint.visibleText), documentName: app.documentName)
        switch (destination, region) {
        case (_, .code), (_, .string): return nil
        case (.codeEditor, .unrecognised): return nil
        default: break
        }
        let lines = InsertionPoint.visibleText(slice).split(whereSeparator: \.isNewline)
            .compactMap { Self.proseLine(from: $0) }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: " ")
    }

    /// Characters that open a list item, quotation, heading or comment.
    private static let markerCharacters: Set<Character> = ["/", "#", "*", "-", ">", "\u{2022}", "\u{00B7}"]

    /// Symbols that code carries and prose seldom does.
    private static let codeSymbols: Set<Character> = [
        "{", "}", "[", "]", "<", ">", "=", ";", "|", "\\", "$", "`", "^", "~",
    ]

    /// Operators that mark a line as code wherever they sit.
    private static let codeOperators = ["::", "->", "=>", "&&", "||", "==", "!="]

    /// Shell prompts that open a line.
    private static let promptPrefixes = ["$ ", "% ", "\u{276F}", "\u{279C}", "\u{00BB} "]

    /// The words of `line` with its marker taken off, or `nil` when it is a formula, a prompt or code.
    private static func proseLine(from line: Substring) -> String? {
        var body = line.drop(while: \.isWhitespace)
        if promptPrefixes.contains(where: body.hasPrefix) || body.hasPrefix("=") || body.contains("~$")
            || body.contains("~%")
        {
            return nil
        }
        body = withoutMarker(body)
        guard body.contains(where: \.isLetter) else { return nil }
        if codeOperators.contains(where: { body.contains($0) }) || hasCallSyntax(body) { return nil }
        let marks = body.filter { !$0.isWhitespace }
        let symbols = marks.filter { codeSymbols.contains($0) }.count
        guard symbols * 10 < marks.count else { return nil }
        return body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The line without the list, quotation, heading or comment mark it opens with, which is typed but not said.
    private static func withoutMarker(_ line: Substring) -> Substring {
        var body = line
        let run = body.prefix { markerCharacters.contains($0) }
        // A lone mark is one only when a space follows it, so "-5 degrees" keeps its sign.
        if !run.isEmpty, run.count > 1 || body.dropFirst().first?.isWhitespace != false {
            body = body.dropFirst(run.count).drop(while: \.isWhitespace)
        }
        let digits = body.prefix(while: \.isNumber)
        let rest = body.dropFirst(digits.count)
        if !digits.isEmpty, let closing = rest.first, ".)".contains(closing),
            rest.dropFirst().first?.isWhitespace == true
        {
            body = rest.dropFirst().drop(while: \.isWhitespace)
        }
        return body
    }

    /// Whether a word is followed at once by an opening parenthesis, as in `run(x)`.
    private static func hasCallSyntax(_ text: Substring) -> Bool {
        var previous: Character?
        for character in text {
            if character == "(", let previous, previous.isLetter || previous.isNumber || previous == "_" {
                return true
            }
            previous = character
        }
        return false
    }
}
