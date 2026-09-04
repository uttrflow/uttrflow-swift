/// Where a full line is cut to make the text typed so far, so one line yields several completion cases.
public enum LineCut: Sendable, Equatable, Hashable {
    /// After this many words and the space after them, so the next word is wholly the model's to supply.
    case afterWord(Int)
    /// This many characters into this word, so the rest of the word is what the line determines.
    case intoWord(Int, by: Int)
    /// Halfway into this word, at least one character in and one left to write.
    case midWord(Int)
    /// After exactly this many characters, wherever they fall, with something still to write.
    case characters(Int)
    /// The whole line, for a line that is already complete.
    case whole

    /// The text typed so far when the line is cut here, or nil when the line is too short to cut this way.
    public func typed(of line: String) -> String? {
        let characters = Array(line)
        let words = Self.words(in: characters)
        switch self {
        case .afterWord(let count):
            guard count >= 1, words.count > count else { return nil }
            return String(characters[..<(words[count - 1].upperBound + 1)])
        case .intoWord(let index, let depth):
            guard index >= 1, depth >= 1, words.count >= index, words[index - 1].count > depth else {
                return nil
            }
            return String(characters[..<(words[index - 1].lowerBound + depth)])
        case .midWord(let index):
            guard index >= 1, words.count >= index, words[index - 1].count >= 2 else { return nil }
            return LineCut.intoWord(index, by: words[index - 1].count / 2).typed(of: line)
        case .characters(let count):
            guard count >= 1, count < characters.count else { return nil }
            return String(characters[..<count])
        case .whole:
            return line
        }
    }

    /// The offset range of each run of non-space characters, which is what a word is here.
    static func words(in characters: [Character]) -> [Range<Int>] {
        var words: [Range<Int>] = []
        var start: Int?
        for (offset, character) in characters.enumerated() {
            if character == " " {
                if let begun = start {
                    words.append(begun..<offset)
                    start = nil
                }
            } else if start == nil {
                start = offset
            }
        }
        if let begun = start { words.append(begun..<characters.count) }
        return words
    }
}

/// How much of a line past its cut the cut itself determines, which is how much a completion is held to.
public enum Determinacy: Sendable, Equatable {
    /// The rest of the piece being typed, up to the next of these separators, and only when the cut falls inside one.
    case segment(until: Set<Character>)
    /// The whole rest of the line, wherever it is cut.
    case line
    /// Nothing in particular, so any continuation in register counts.
    case any
    /// No continuation at all, because the line is complete or too short to guess from.
    case nothing

    /// The rest of the word being typed, for lines whose pieces are separated by spaces.
    public static let word = Determinacy.segment(until: [" "])
}
