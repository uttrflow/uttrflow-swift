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

    /// Reads the sentence state off the last mark before the caret, spaces and tabs aside.
    public static func sentenceState(before text: String?) -> SentenceState {
        guard let text else { return .unknown }
        let tail = text.reversed().drop { $0.isWhitespace && !$0.isNewline }
        guard let last = tail.first else { return .startOfText }
        if last.isNewline { return .startOfSentence }
        return sentenceEnds.contains(last) ? .startOfSentence : .midSentence
    }

    /// The marks after which a new sentence begins.
    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}
