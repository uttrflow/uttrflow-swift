/// Trims strings without Foundation, which this module does not import for the sake of one function.
enum Whitespace {
    /// A string without the whitespace around it.
    static func trimmed(_ text: some StringProtocol) -> String {
        var characters = Array(text)
        while let first = characters.first, first.isWhitespace { characters.removeFirst() }
        while let last = characters.last, last.isWhitespace { characters.removeLast() }
        return String(characters)
    }
}
