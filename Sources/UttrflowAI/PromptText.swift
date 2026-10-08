// The one sanitiser for every value a prompt quotes, so no value can open a new prompt line.

/// Makes text safe to place inside one prompt line. See Docs/cleanup.md.
public enum PromptText {
    /// The value as one line: no control characters, bidirectional marks or zero-width spaces, whitespace collapsed, quotes single, capped.
    public static func quoted(_ text: String, limit: Int? = nil) -> String {
        let flattened = TextTidy.collapseWhitespace(scrubbed(text, lineBreak: " "))
        guard let limit else { return flattened }
        return truncated(flattened, to: limit)
    }

    /// Prompt-safe text: escape line breaks, replace other controls with spaces, and optionally replace quotes.
    public static func promptValue(
        _ text: String, limit: Int? = nil, replaceQuotes: Bool = false
    ) -> String {
        let safe = scrubbed(text, lineBreak: "\\n", replaceQuotes: replaceQuotes)
        guard let limit else { return safe }
        return truncated(safe, to: limit)
    }

    /// The spoken text with each line break written as one `\n` and every other line made safe as `quoted` makes it.
    public static func spoken(_ text: String) -> String {
        TextTidy.collapseSpacing(scrubbed(text, lineBreak: "\n"))
    }

    /// Context text with safe line feeds preserved and other invisible/control hazards removed.
    public static func blockValue(_ text: String) -> String {
        scrubbed(text, lineBreak: "\n", replaceQuotes: false)
    }

    /// The text with every double-quote variant made a single quote, so it cannot close the quotation it sits in.
    public static func withSingleQuotes(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { doubleQuotes.contains($0) ? "'" : $0 }))
    }

    /// The answer with the spoken text's double quotes put back where the fold left the model only single ones.
    public static func restoringDoubleQuotes(in answer: String, from spoken: String) -> String {
        let said = quoteMarks(in: Array(spoken.unicodeScalars)).map(\.scalar)
        guard said.contains(where: doubleQuotes.contains) else { return answer }
        var scalars = Array(answer.unicodeScalars)
        let answered = quoteMarks(in: scalars)
        // Marks pair up only in order and one for one; any other count means the model moved them.
        guard answered.count == said.count else { return answer }
        for (mark, original) in zip(answered, said)
        where doubleQuotes.contains(original) && singleQuotes.contains(mark.scalar) {
            scalars[mark.index] = original
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Every double or single quote mark, leaving out an apostrophe between two letters.
    private static func quoteMarks(in scalars: [Unicode.Scalar]) -> [(index: Int, scalar: Unicode.Scalar)] {
        scalars.indices.compactMap { index in
            let scalar = scalars[index]
            guard doubleQuotes.contains(scalar) || singleQuotes.contains(scalar) else { return nil }
            let between =
                index > 0 && index < scalars.count - 1
                && scalars[index - 1].properties.isAlphabetic && scalars[index + 1].properties.isAlphabetic
            return doubleQuotes.contains(scalar) || !between ? (index, scalar) : nil
        }
    }

    /// The single-quote characters the fold writes or a model writes in its place.
    private static let singleQuotes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}"]

    /// Cuts at the last word boundary inside the limit, so a quotation does not end in the middle of a name.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        // A single word longer than the budget keeps the hard cut rather than becoming a lone ellipsis.
        let kept = cut.isEmpty ? head : cut
        return "\(kept)…"
    }

    /// The double-quote characters a model could read as the end of a quoted value.
    static let doubleQuotes: Set<Unicode.Scalar> = [
        "\u{22}", "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}", "\u{2036}", "\u{FF02}",
    ]

    /// Line breaks become `lineBreak`, other controls a space, bidirectional marks and zero-width spaces nothing, double quotes single.
    private static func scrubbed(_ text: String, lineBreak: String, replaceQuotes: Bool = true) -> String {
        var scalars = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            defer { previous = scalar }
            if isUnsafeFormat(scalar) { continue }
            if isLineBreak(scalar) {
                // A carriage return and line feed are one break, not two.
                if scalar == "\n", previous == "\r" { continue }
                scalars.append(contentsOf: lineBreak.unicodeScalars)
            } else if scalar.properties.generalCategory == .control {
                scalars.append(" ")
            } else {
                scalars.append(replaceQuotes && doubleQuotes.contains(scalar) ? "'" : scalar)
            }
        }
        return String(scalars)
    }

    /// Keep joiners used by words and emoji; discard other invisible formatting controls.
    private static func isUnsafeFormat(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isBidiControl
            || scalar == "\u{200B}"
            || (scalar.properties.generalCategory == .format && scalar != "\u{200C}" && scalar != "\u{200D}")
    }

    /// Whether the scalar ends a line: line feed, vertical tab, form feed, carriage return, NEL, U+2028 or U+2029.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
