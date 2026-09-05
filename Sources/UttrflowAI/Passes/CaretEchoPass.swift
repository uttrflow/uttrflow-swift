public import UttrflowCore

/// Takes back the text before a mid-sentence caret when a model repeats it at the head of its answer.
public struct CaretEchoPass: CleaningPass {
    public static let id: PassID = "caretEcho"

    public let state: InsertionPoint.SentenceState
    /// The field's text before the caret, which the answer must not begin by repeating.
    public let precedingText: String?

    public init(state: InsertionPoint.SentenceState = .unknown, precedingText: String? = nil) {
        self.state = state
        self.precedingText = precedingText
    }

    public func apply(_ draft: Draft) -> Draft {
        guard state == .midSentence, let precedingText else { return draft }
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
            let joined = Self.withoutTrailingMarks(seen.joined(separator: " "))
            if targets.contains(joined) {
                echoed = position
                break
            }
            guard targets.contains(where: { $0.hasPrefix(joined) }) else { break }
        }
        guard let echoed else { return draft }
        for index in present[...echoed] { draft.remove(at: index, by: Self.id) }
        if echoed + 1 < present.count { Self.stripLeadingMarks(&draft, at: present[echoed + 1]) }
        return draft
    }

    /// The whole preceding text and the tail the prompt quoted, each folded, each at least two words.
    static func targets(_ precedingText: String) -> Set<String> {
        let insertion = InsertionPoint(precedingText: precedingText)
        let forms = [precedingText, PromptBuilder.caretText(insertion) ?? ""]
        return Set(
            forms.map { withoutTrailingMarks(folded(TextTidy.collapseWhitespace($0))) }
                .filter { $0.split(separator: " ").count >= 2 })
    }

    /// Lower-cased, with the quote the prompt swaps and the ellipsis it cuts with both folded away.
    static func folded(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "…", with: "")
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
