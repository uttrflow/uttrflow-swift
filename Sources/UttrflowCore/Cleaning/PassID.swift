/// Names one cleaning pass, so a word can say which pass removed or rewrote it.
public struct PassID: Hashable, Sendable, RawRepresentable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

extension PassID {
    /// Um, uh, hmm and the rest of what was never meant as words.
    public static let fillers: PassID = "fillers"
    /// The same short word said twice in a row.
    public static let stammers: PassID = "stammers"
    /// A run of two to four words said twice in a row.
    public static let repeatedPhrase: PassID = "repeatedPhrase"
    /// The half of a sentence the speaker took back.
    public static let selfCorrection: PassID = "selfCorrection"
    /// "Comma", "full stop" and their kind, spoken as instructions.
    public static let spokenPunctuation: PassID = "spokenPunctuation"
    /// "New line", "new paragraph", "bullet point", spoken as instructions.
    public static let layoutWords: PassID = "layoutWords"
    /// Spoken numbers written as numerals.
    public static let numberForms: PassID = "numberForms"
    /// Spaces around the marks the other passes put in.
    public static let spacing: PassID = "spacing"
    /// The case of the first word, which the formatter decides.
    public static let firstWord: PassID = "firstWord"
    /// The last mark, which the formatter decides.
    public static let terminalStop: PassID = "terminalStop"
    /// The words a model repeated back from the text before the caret.
    public static let caretEcho: PassID = "caretEcho"
}
