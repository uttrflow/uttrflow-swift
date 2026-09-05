public import UttrflowCore

/// Capitalises each sentence and the pronoun "I", then cases the first word the way the formatter and the caret say.
public struct FirstWordPass: CleaningPass {
    public static let id: PassID = "firstWord"

    public let policy: FirstWordPolicy
    public let state: InsertionPoint.SentenceState
    /// Where a name can be sighted besides the text itself: the title, the selection, the text at the caret.
    public let onScreen: [String]
    /// The transcript whose case `.asSpoken` copies; nil reads it off the draft's own heard words.
    public let heard: String?

    public init(
        policy: FirstWordPolicy = .fromInsertionPoint, state: InsertionPoint.SentenceState = .unknown,
        onScreen: [String] = [], heard: String? = nil
    ) {
        self.policy = policy
        self.state = state
        self.onScreen = onScreen
        self.heard = heard
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let text = draft.text
        let heardWords =
            heard.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            ?? draft.words.map(\.heard)
        var startOfSentence = true
        var isFirst = true
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard !word.isLayoutMark else {
                startOfSentence = word.text != "\n"
                continue
            }
            var cased = Self.pronounCapitalised(word.text)
            if isFirst {
                cased = firstWord(cased, in: text, heard: heardWords)
            } else if startOfSentence {
                cased = WordShape.capitalised(cased)
            }
            draft.replace(at: index, with: cased, by: Self.id)
            startOfSentence = WordShape(cased).endsSentence
            isFirst = false
        }
        return draft
    }

    /// The first word under the policy: a capital, the case it was heard in, or lower-case after a mid-sentence caret.
    private func firstWord(_ word: String, in text: String, heard: [String]) -> String {
        switch policy {
        case .alwaysCapital:
            return WordShape.capitalised(word)
        case .asSpoken:
            return Self.matchingHeardCase(word, heard: heard)
        case .fromInsertionPoint:
            guard state == .midSentence, !Self.keepsCapital(word),
                !Self.looksLikeName(word, in: [text] + onScreen)
            else { return WordShape.capitalised(word) }
            return WordShape.lowercased(word)
        }
    }

    /// "i" and "i'll" become "I" and "I'll"; nothing else changes.
    static func pronounCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard shape.key == "i" || shape.key.hasPrefix("i'") || shape.key.hasPrefix("i\u{2019}") else {
            return text
        }
        return shape.replacingCore(with: "I" + shape.core.dropFirst())
    }

    /// Whether a word keeps its capital mid-sentence: "I" and its contractions, or an acronym.
    static func keepsCapital(_ word: String) -> Bool {
        let core = WordShape(word).core
        if core == "I" || core.hasPrefix("I'") || core.hasPrefix("I\u{2019}") { return true }
        let letters = core.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }

    /// Copies the case the word was heard in, skipping any filler heard before it; a changed word is left alone.
    static func matchingHeardCase(_ word: String, heard: [String]) -> String {
        let letters = WordShape(word).core.filter(\.isLetter).lowercased()
        guard !letters.isEmpty,
            let spoken = heard.first(where: { $0.filter(\.isLetter).lowercased() == letters }),
            let lead = spoken.first(where: \.isLetter)
        else { return word }
        return lead.isUppercase ? WordShape.capitalised(word) : WordShape.lowercased(word)
    }

    /// Whether a text holds the word capitalised off a sentence start; a title-cased text says nothing.
    static func looksLikeName(_ word: String, in texts: [String]) -> Bool {
        let wanted = bareWord(word[...]).lowercased()
        guard !wanted.isEmpty else { return false }
        return texts.contains { text in
            let lines = text.split(whereSeparator: \.isNewline)
                .map { $0.split(whereSeparator: \.isWhitespace) }
            guard lines.joined().contains(where: { bareWord($0).first?.isLowercase ?? false }) else {
                return false
            }
            return lines.contains { line in
                zip(line, line.dropFirst()).contains { previous, token in
                    let candidate = bareWord(token)
                    let startsSentence = previous.last.map(sentenceEnds.contains) ?? false
                    return (candidate.first?.isUppercase ?? false) && candidate.lowercased() == wanted
                        && !startsSentence
                }
            }
        }
    }

    /// The token without the quotes, brackets and marks around it.
    private static func bareWord(_ token: Substring) -> Substring {
        guard let start = token.firstIndex(where: { $0.isLetter || $0.isNumber }),
            let end = token.lastIndex(where: { $0.isLetter || $0.isNumber })
        else { return "" }
        return token[start...end]
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}
