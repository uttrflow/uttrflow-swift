public import UttrflowCore

/// Takes back the text before a mid-sentence caret when a model repeats it at the head of its answer.
public struct CaretEchoPass: PieceCleaningPass {
    public static let id: PassID = .caretEcho
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    public let state: InsertionPoint.SentenceState
    /// The field's text before the caret, which the answer must not begin by repeating.
    public let precedingText: String?
    /// The words the speaker dictated, used to preserve a faithful repeated phrase.
    public let spokenText: String?

    public init(
        state: InsertionPoint.SentenceState = .unknown,
        precedingText: String? = nil,
        spokenText: String? = nil
    ) {
        self.state = state
        self.precedingText = precedingText
        self.spokenText = spokenText
    }

    public func apply(_ draft: Draft) -> Draft {
        guard let precedingText,
            state == .midSentence || Self.isStandaloneMarker(precedingText)
        else { return draft }
        let targets = Self.targets(precedingText)
        guard !targets.isEmpty else { return draft }
        var draft = draft
        let present = draft.presentIndices
        var seen: [String] = []
        var echoed: Int?
        for (position, index) in present.enumerated() {
            let word = draft.words[index]
            guard !word.isLayoutMark else { break }
            seen.append(Self.folded(word.text))
            let rawJoined = seen.joined(separator: " ")
            let joined = Self.withoutTrailingMarks(rawJoined)
            if targets.contains(rawJoined) || targets.contains(joined) {
                echoed = position
                break
            }
            guard targets.contains(where: { $0.hasPrefix(joined) }) else { break }
        }
        guard let echoed else { return draft }
        let repeated = Self.withoutTrailingMarks(seen.joined(separator: " "))
        if let spokenText {
            let spokenWords = Self.words(Self.folded(TextTidy.collapseWhitespace(spokenText)))
            let repeatedWords = Self.words(repeated)
            let answerWords = present.map { Self.words(Self.folded(draft.words[$0].text)) }.flatMap { $0 }
            if !repeatedWords.isEmpty, spokenWords.starts(with: repeatedWords),
                answerWords == Array(spokenWords)
            {
                return draft
            }
        }
        for index in present[...echoed] { draft.remove(at: index, by: Self.id) }
        if echoed + 1 < present.count { Self.stripLeadingMarks(&draft, at: present[echoed + 1]) }
        return draft
    }

    /// Splits folded text into comparable word tokens.
    static func words(_ text: String) -> [String] {
        WordTokens.words(text, .echo)
    }

    /// The whole preceding text and the tail the prompt quoted, plus a standalone comment or list marker.
    static func targets(_ precedingText: String) -> Set<String> {
        let insertion = InsertionPoint(precedingText: precedingText)
        let forms = [precedingText, PromptBuilder.caretText(insertion) ?? ""]
        return Set(
            forms.compactMap { form in
                let folded = folded(TextTidy.collapseWhitespace(form))
                let normalized = withoutTrailingMarks(folded)
                if normalized.split(separator: " ").count >= 2 { return normalized }
                if Self.isStandaloneMarker(folded) { return folded }
                return nil
            })
    }

    /// Whether the preceding text is one standalone code-comment or list marker.
    private static func isStandaloneMarker(_ text: String) -> Bool {
        ["//", "#", "--", "-"].contains(folded(TextTidy.collapseWhitespace(text)))
    }

    /// Lower-cased, with the quote the prompt swaps and the ellipsis it cuts with both folded away.
    static func folded(_ text: String) -> String {
        PromptText.withSingleQuotes(text.lowercased()).replacingOccurrences(of: "…", with: "")
    }

    /// The text without the punctuation and spaces after its last letter or digit.
    static func withoutTrailingMarks(_ text: String) -> String {
        String(text.reversed().drop { !$0.isLetter && !$0.isNumber }.reversed())
    }

    /// Drops the punctuation or line break an echo left at the head of the word after it, or the whole word when that is all it was.
    private static func stripLeadingMarks(_ draft: inout Draft, at index: Int) {
        let word = draft.words[index]
        let stripped = word.isLayoutMark ? "" : String(word.text.drop { !$0.isLetter && !$0.isNumber })
        if stripped.isEmpty {
            draft.remove(at: index, by: id)
        } else {
            draft.replace(at: index, with: stripped, by: id)
        }
    }
}
