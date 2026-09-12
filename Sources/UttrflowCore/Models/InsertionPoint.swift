/// What sits at the caret, so the first word can match what came before it.
public struct InsertionPoint: Sendable, Equatable, Codable {
    /// Where the caret stands in the sentence around it.
    public enum SentenceState: String, Sendable, Equatable, Codable {
        case startOfText
        case startOfSentence
        case midSentence
        /// The field would not say, which every formatter treats as the start of a sentence.
        case unknown
    }

    /// The most characters kept before the caret.
    public static let precedingLimit = 300
    /// The most characters kept after the selection.
    public static let followingLimit = 100

    /// Text before the caret, or `nil` when the field will not report its value.
    public let precedingText: String?
    /// Text after the selection, or `nil` when the field will not report its value.
    public let followingText: String?

    public init(precedingText: String? = nil, followingText: String? = nil) {
        self.precedingText = precedingText
        self.followingText = followingText
    }

    /// The insertion point of a field that says nothing about itself.
    public static let unknown = InsertionPoint()

    /// Derived from the preceding text, never read from the field.
    public var sentenceState: SentenceState { Self.sentenceState(before: precedingText) }

    /// Reads the sentence state off the line the caret sits on, since a list marker is not a word.
    public static func sentenceState(before text: String?) -> SentenceState {
        guard let text else { return .unknown }
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        guard let last = withoutOpeningMarker(line).last(where: { !$0.isWhitespace }) else {
            // Only a marker, a blank line or an empty field stands here; a line break still opened a line.
            let isBlank = line.allSatisfy(\.isWhitespace)
            return isBlank && text.contains(where: \.isNewline) ? .startOfSentence : .startOfText
        }
        return sentenceEnds.contains(last) ? .startOfSentence : .midSentence
    }

    /// The line without the one list, quote or heading marker it opens with, which is typed but not written.
    private static func withoutOpeningMarker(_ line: Substring) -> Substring {
        let body = line.drop(while: \.isWhitespace)
        if let marker = openingMarkers.first(where: { body.hasPrefix($0) }) {
            // A run of the same mark is one marker: "## " is a heading, ">>" a quotation inside a quotation.
            return body.drop { String($0) == marker }
        }
        // A numbered item: its digits, then the stop or bracket that closes the number.
        let digits = body.prefix(while: \.isNumber)
        let rest = body.dropFirst(digits.count)
        guard !digits.isEmpty, rest.first.map({ ".)".contains($0) }) == true else { return body }
        return rest.dropFirst()
    }

    /// What a line may open with that is a marker rather than words: a list item, a quotation, a heading.
    private static let openingMarkers: [String] =
        Draft.bulletTokens.sorted() + ["#", ">", "\"", "'", "\u{201C}", "\u{2018}", "(", "[", "{"]

    /// The marks after which a new sentence begins.
    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}
