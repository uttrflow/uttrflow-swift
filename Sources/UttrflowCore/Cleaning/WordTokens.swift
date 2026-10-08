/// One word cut from a text, with the range it covers in that text.
public struct WordToken: Equatable, Sendable {
    public let text: String
    public let range: Range<String.Index>
}

/// The one place that decides where a word ends; each profile names one boundary rule as data.
public enum WordTokens {
    /// Which characters end a word.
    public enum Profile: Sendable {
        /// Whitespace ends a word and punctuation stays on it, so "don't." is one token: the words as written.
        case display
        /// Anything but a letter or a digit ends a word, so "don't" is "don" and "t": the unit comparisons count in.
        case comparison
        /// Anything but a letter ends a word, so "B2B" is "B" and "B": the letters a name is read by.
        case letters
        /// Whitespace, a hyphen or a slash ends a word, so "and/or" is two words: the units grammar reads.
        case grammar
        /// A space or a punctuation mark ends a word, so "p.m." is "p" and "m": the units an echo is matched in.
        case echo
        /// Only a line break ends a token, so each token is one line as written, its spaces kept.
        case line

        func isBoundary(_ character: Character) -> Bool {
            switch self {
            case .display: character.isWhitespace
            case .comparison: !character.isLetter && !character.isNumber
            case .letters: !character.isLetter
            case .grammar: character.isWhitespace || character == "-" || character == "/"
            case .echo: character == " " || character.isPunctuation
            case .line: character.isNewline
            }
        }
    }

    /// The words of the text under the profile, each with its range, empty runs dropped.
    public static func tokens<Text: StringProtocol>(_ text: Text, _ profile: Profile) -> [WordToken] {
        var tokens: [WordToken] = []
        var start: String.Index?
        for index in text.indices {
            if profile.isBoundary(text[index]) {
                if let open = start {
                    tokens.append(WordToken(text: String(text[open..<index]), range: open..<index))
                }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let open = start {
            tokens.append(WordToken(text: String(text[open...]), range: open..<text.endIndex))
        }
        return tokens
    }

    /// The words of the text under the profile, without their ranges.
    public static func words<Text: StringProtocol>(_ text: Text, _ profile: Profile) -> [String] {
        tokens(text, profile).map(\.text)
    }
}
