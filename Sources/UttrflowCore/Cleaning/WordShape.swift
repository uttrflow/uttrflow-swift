/// A word split into the punctuation before it, the word itself, and the punctuation after it.
public struct WordShape: Equatable, Sendable {
    public let prefix: String
    public let core: String
    public let suffix: String

    public init(_ text: String) {
        let leading = text.prefix(while: Self.isMark)
        let rest = text.dropFirst(leading.count)
        let trailing = rest.reversed().prefix(while: Self.isMark).reversed()
        prefix = String(leading)
        core = String(rest.dropLast(trailing.count))
        suffix = String(trailing)
    }

    /// The word lower-cased, which is what every pass compares on.
    public var key: String { core.lowercased() }

    /// Lower-cased runs of letters and digits, which is the unit every word comparison counts in.
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: isMark).map(String.init)
    }

    /// Whether the word closes a clause or a sentence.
    public var endsClause: Bool { suffix.contains(where: { ",.;:!?".contains($0) }) }

    /// Whether the word closes a sentence.
    public var endsSentence: Bool { suffix.contains(where: { ".!?".contains($0) }) }

    /// The same word with a new core, keeping the punctuation around it.
    public func replacingCore(with text: String) -> String { prefix + text + suffix }

    private static func isMark(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }

    // MARK: Shaping a word

    /// Uppercases the first letter; a leading digit counts as the start and stays as it is.
    public static func capitalised(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return text }
        return String(text[..<start]) + text[start].uppercased() + String(text[text.index(after: start)...])
    }

    /// Lowercases the first letter; a leading digit counts as the start and stays as it is.
    public static func lowercased(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }), text[start].isLetter else {
            return text
        }
        return String(text[..<start]) + text[start].lowercased() + String(text[text.index(after: start)...])
    }

    /// Marks that end a text already: a clause mark, an ellipsis, or a bracket the words closed themselves.
    static let finishers: Set<Character> = [",", ".", ";", ":", "!", "?", "\u{2026}", ")", "]", "}"]

    /// Quotes that open a quotation, read on the word's own prefix.
    static let openingQuotes: Set<Character> = ["\"", "'", "\u{201C}", "\u{2018}", "\u{00AB}"]

    /// Quotes a full stop belongs inside, which is where a spoken "close quote" leaves the end of a sentence.
    static let closingQuotes: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}"]

    /// The word with a full stop where the sentence wants one: after a symbol like `%`, inside a closing quote.
    public static func finished(_ text: String) -> String {
        let shape = WordShape(text)
        guard !shape.core.isEmpty, !shape.suffix.contains(where: finishers.contains) else { return text }
        let quoted = trailingQuotes(of: text)
        // A quotation opening and closing on one word is a quoted term rather than a sentence, so it takes none.
        guard quoted.isEmpty || !shape.prefix.contains(where: openingQuotes.contains) else { return text }
        return String(text.dropLast(quoted.count)) + "." + quoted
    }

    /// The word with `mark` on its end; a clause mark replaces one already there, a quote follows it.
    public static func marked(_ text: String, with mark: String) -> String {
        if mark == "\u{2014}" { return text + " " + mark }
        if let last = text.last, ",.;:!?".contains(last), ",.;:!?".contains(mark) {
            return String(text.dropLast()) + mark
        }
        return text + mark
    }

    /// The word with every mark of `marks` on its end, each merged in turn under `marked(_:with:)`.
    public static func marked(_ text: String, withAll marks: some Sequence<Character>) -> String {
        marks.reduce(text) { marked($0, with: String($1)) }
    }

    /// Takes back one trailing full stop, inside a closing quote too; a question or exclamation mark, or an ellipsis, stays.
    public static func withoutTrailingStop(_ text: String) -> String {
        let quoted = trailingQuotes(of: text)
        let body = String(text.dropLast(quoted.count))
        guard body.hasSuffix("."), !body.hasSuffix("..") else { return text }
        return String(body.dropLast()) + quoted
    }

    /// The run of closing quotes the text ends on, which a full stop goes inside rather than after.
    private static func trailingQuotes(of text: String) -> String {
        String(text.reversed().prefix(while: closingQuotes.contains).reversed())
    }
}

extension Draft {
    /// The shape of the word at `index`.
    public func shape(at index: Int) -> WordShape { WordShape(words[index].text) }

    /// The live positions from `position` to the end of the sentence it sits in, which one spoken phrase cannot run past.
    public func sentenceRun(from position: Int, in live: [Int]) -> Range<Int> {
        let end = live[position...].firstIndex { shape(at: $0).endsSentence }.map { $0 + 1 }
        return position..<(end ?? live.count)
    }
}
