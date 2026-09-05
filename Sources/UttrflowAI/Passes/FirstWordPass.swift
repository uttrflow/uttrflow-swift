public import UttrflowCore

/// How the first word is cased: for a fresh sentence, or for a caret that sits mid-sentence.
public enum FirstWordPolicy: Sendable, Equatable {
    case capitalise
    case lowercase
}

/// Capitalises the first word, each sentence after a stop, a paragraph or a bullet, and the pronoun "I".
public struct FirstWordPass: CleaningPass {
    public static let id: PassID = "firstWord"

    public let policy: FirstWordPolicy

    public init(policy: FirstWordPolicy = .capitalise) {
        self.policy = policy
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var startOfSentence = true
        var isFirst = true
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard !word.isLayoutMark else {
                startOfSentence = word.text != "\n"
                continue
            }
            var text = Self.pronounCapitalised(word.text)
            if startOfSentence {
                text = isFirst && policy == .lowercase ? Self.lowercased(text) : Self.capitalised(text)
            }
            draft.replace(at: index, with: text, by: Self.id)
            startOfSentence = WordShape(text).endsSentence
            isFirst = false
        }
        return draft
    }

    /// "i" and "i'll" become "I" and "I'll"; nothing else changes.
    static func pronounCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard shape.key == "i" || shape.key.hasPrefix("i'") else { return text }
        return shape.replacingCore(with: "I" + shape.core.dropFirst())
    }

    /// Uppercases the first letter; a leading digit counts as the start and stays as it is.
    static func capitalised(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return text }
        return String(text[..<start]) + text[start].uppercased() + String(text[text.index(after: start)...])
    }

    /// Lowercases the first letter, leaving the pronoun "I" and an all-capitals word alone.
    static func lowercased(_ text: String) -> String {
        let shape = WordShape(text)
        guard shape.core != "I", !shape.core.hasPrefix("I'"), shape.core != shape.core.uppercased(),
            let start = text.firstIndex(where: \.isLetter)
        else { return text }
        return String(text[..<start]) + text[start].lowercased() + String(text[text.index(after: start)...])
    }
}
