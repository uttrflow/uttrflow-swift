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

    /// The most UTF-16 units kept before the caret.
    public static let precedingLimit = 300
    /// The most UTF-16 units kept after the selection.
    public static let followingLimit = 100

    /// Text before the caret, or `nil` when the field will not report its value.
    public let precedingText: String?
    /// Text after the selection, or `nil` when the field will not report its value.
    public let followingText: String?

    public init(precedingText: String? = nil, followingText: String? = nil) {
        self.precedingText = precedingText
        self.followingText = followingText
    }

    /// The same caret with secret-shaped runs taken out of its text, for word lists and prompts; casing reads `self`.
    public var vocabulary: InsertionPoint {
        InsertionPoint(
            precedingText: precedingText.map(SecretShapes.vocabulary(of:)),
            followingText: followingText.map(SecretShapes.vocabulary(of:)))
    }

    /// The most sentences before the caret offered to recognition and its scorer.
    static let recognitionSentences = 2
    /// The most UTF-16 units of those sentences kept, cut at a word.
    static let recognitionLimit = 200

    /// The last sentence or two before the caret, secret-shaped runs out; `nil` when nothing is written there.
    public var recognitionContext: String? {
        guard let text = vocabulary.precedingText else { return nil }
        var body = Substring(text)
        while let last = body.last, last.isWhitespace { body.removeLast() }
        var start = body.startIndex
        var boundaries = 0
        var index = body.endIndex
        while index > body.startIndex {
            let before = body.index(before: index)
            let isBoundary =
                body[before].isNewline
                || (index < body.endIndex && body[index].isWhitespace
                    && SentenceMarks.ends.contains(body[before]))
            if isBoundary {
                boundaries += 1
                if boundaries == Self.recognitionSentences {
                    start = index
                    break
                }
            }
            index = before
        }
        var kept = body[start...].drop(while: \.isWhitespace)
        if kept.utf16.count > Self.recognitionLimit {
            while kept.utf16.count > Self.recognitionLimit { kept = kept.dropFirst() }
            // A word cut by the limit is dropped whole, so the recogniser never reads half a word.
            kept = kept.drop(while: { !$0.isWhitespace }).drop(while: \.isWhitespace)
        }
        return kept.isEmpty ? nil : String(kept)
    }

    /// The insertion point of a field that says nothing about itself.
    public static let unknown = InsertionPoint()

    /// Derived from the preceding text, never read from the field.
    public var sentenceState: SentenceState { Self.sentenceState(before: precedingText) }

    /// What the caret stands inside, or `nil` when the field will not report its value.
    public var structure: CaretStructure? { precedingText.map(CaretStructure.init(precedingText:)) }

    /// Whether the caret's line opens with a list marker, so added text stays an unfinished list item.
    public var isOnListItemLine: Bool {
        guard let precedingText else { return false }
        return Self.listItemRemainder(in: CaretStructure.caretLine(of: Self.visibleText(precedingText)))
            != nil
    }

    /// Reads the sentence state off the line the caret sits on, since a list marker is not a word.
    public static func sentenceState(before text: String?) -> SentenceState {
        guard let text = text.map(visibleText) else { return .unknown }
        let line = CaretStructure.caretLine(of: text)
        let body = withoutOpeningMarker(line)
        guard body.contains(where: { !$0.isWhitespace }) else {
            // Only a marker, a blank line or an empty field stands here; a line break still opened a line.
            let isBlank = line.allSatisfy(\.isWhitespace)
            return isBlank && text.contains(where: \.isNewline) ? .startOfSentence : .startOfText
        }
        let terminal = body.reversed().drop(while: Self.isTrailingSentenceDecoration).first
        if let terminal, SentenceMarks.ends.contains(terminal) || terminal == SentenceMarks.ellipsis {
            let word =
                body.reversed().drop(while: Self.isTrailingSentenceDecoration).reversed()
                .split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            let normalizedWord = String(
                word.lowercased().reversed()
                    .drop(while: { ".!?…,:;\"'”’)]}".contains($0) })
                    .reversed()
                    .drop(while: { "\"'“(".contains($0) })
            )
            let isKnownAbbreviation =
                terminal == "." && !Abbreviations.endsSentence(normalizedWord + ".", followedBy: nil)
            if !word.isEmpty, !isKnownAbbreviation {
                return .startOfSentence
            }
        }
        return .midSentence
    }

    /// The line without the one list, quote or heading marker it opens with, which is typed but not written.
    private static func withoutOpeningMarker(_ line: Substring) -> Substring {
        if let list = listItemRemainder(in: line) { return list }
        let body = line.drop(while: \.isWhitespace)
        if let marker = openingMarkers.first(where: { body.hasPrefix($0) }) {
            // A run of the marker's marks is one marker: "## " is a heading, "///" and "/**" open a comment.
            return body.drop { marker.contains($0) }
        }
        return body
    }

    /// The text after the bullet or number that opens a list item.
    private static func listItemRemainder(in line: Substring) -> Substring? {
        let body = line.drop(while: \.isWhitespace)
        if let marker = Draft.bulletTokens.sorted().first(where: { body.hasPrefix($0) }) {
            return body.drop { String($0) == marker }
        }
        let digits = body.prefix(while: \.isNumber)
        let closingMark = body.dropFirst(digits.count)
        guard !digits.isEmpty, closingMark.first.map({ ".)".contains($0) }) == true else { return nil }
        return closingMark.dropFirst()
    }

    /// What a line may open with that is a marker, not words: a list item, quotation, heading or comment.
    private static let openingMarkers: [String] =
        ["/*", "/"] + Draft.bulletTokens.sorted()
        + ["#", ">", "\"", "'", "\u{201C}", "\u{2018}", "(", "[", "{"]

    /// Whether one trailing character does not change the sentence end before it.
    private static func isTrailingSentenceDecoration(_ character: Character) -> Bool {
        character.isWhitespace || closingSentenceCharacters.contains(character)
            || CaretJoin.isEmoji(character)
    }

    /// Closing quotes and brackets may follow a sentence end without changing it.
    private static let closingSentenceCharacters: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]

    /// Pads `text` with a space at each caret edge where it would otherwise join a neighbouring word in `destination`.
    public func paddedBoundary(for text: String, in destination: Destination) -> String {
        // A field that hides its preceding text gets the dictated text unchanged.
        guard let preceding = precedingText.map(Self.visibleText), let first = text.first,
            let last = text.last,
            !text.allSatisfy(\.isWhitespace)
        else {
            return text
        }
        var result = ""
        let previous = preceding.last
        // A clitic attaches to the word before it, though it opens with a letter.
        if let previous, !Self.attachingCliticPrefixes.contains(where: text.hasPrefix),
            CaretJoin.needsSpace(
                between: CaretJoin.classify(previous, after: preceding.dropLast().last),
                and: CaretJoin.classify(first, after: previous), in: destination)
        {
            result += " "
        }
        result += text
        if let next = followingText.map(Self.visibleText)?.first,
            CaretJoin.needsSpace(
                between: CaretJoin.classify(last, after: text.dropLast().last ?? previous),
                and: CaretJoin.classify(next, after: last), in: destination)
        {
            result += " "
        }
        return result
    }

    /// The text as it reads: attachments, zero-width and bidi marks hold no letters, so no classifier counts them.
    public static func visibleText(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isInvisible) else { return text }
        var visible = String.UnicodeScalarView()
        visible.append(contentsOf: text.unicodeScalars.lazy.filter { !isInvisible($0) })
        return String(visible)
    }

    /// An object replacement or a format character; a joiner and tag characters build an emoji, so they stay.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\u{FFFC}" { return true }
        guard scalar.properties.generalCategory == .format else { return false }
        return scalar != "\u{200D}" && !(0xE0000...0xE007F).contains(scalar.value)
    }

    /// Clitic spellings whose first character is not punctuation.
    private static let attachingCliticPrefixes = ["n't", "n’t"]
}
