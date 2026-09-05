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

    /// The word with a full stop when it ends in a letter or a digit; code, a mark or a quote is left alone.
    public static func finished(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + "."
    }

    /// Takes back one trailing full stop; a question or exclamation mark, or an ellipsis, stays.
    public static func withoutTrailingStop(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }
}

extension Draft {
    /// The shape of the word at `index`.
    public func shape(at index: Int) -> WordShape { WordShape(words[index].text) }
}
