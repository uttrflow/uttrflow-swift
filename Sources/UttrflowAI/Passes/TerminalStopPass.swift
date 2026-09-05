public import UttrflowCore

/// Adds or takes back the final full stop the way the formatter's policy says; a line break means no stop.
public struct TerminalStopPass: CleaningPass {
    public static let id: PassID = "terminalStop"

    public let policy: TerminalStopPolicy

    public init(policy: TerminalStopPolicy = .always) {
        self.policy = policy
    }

    public func apply(_ draft: Draft) -> Draft {
        guard let last = draft.presentIndices.last, !draft.words[last].isLayoutMark else { return draft }
        let word = draft.words[last].text
        let finished: String
        switch policy {
        case .always:
            finished = Self.finished(word, in: draft.text)
        case .never:
            finished = Self.withoutTrailingStop(word)
        case .offForShortMessages(let sentences):
            let stopped = Self.finished(word, in: draft.text)
            finished =
                Self.sentenceCount(draft.text) <= sentences ? Self.withoutTrailingStop(stopped) : stopped
        }
        var draft = draft
        draft.replace(at: last, with: finished, by: Self.id)
        return draft
    }

    /// The last word with a full stop when the whole text wants one: not after code, a mark, or a line break.
    static func finished(_ word: String, in text: String) -> String {
        TextTidy.ensureTerminalPunctuation(text) == text ? word : word + "."
    }

    /// Takes back one trailing full stop; a question or exclamation mark, or an ellipsis, stays.
    static func withoutTrailingStop(_ word: String) -> String {
        guard word.hasSuffix("."), !word.hasSuffix("..") else { return word }
        return String(word.dropLast())
    }

    /// How many sentences the text holds, counting a last one that has no mark yet.
    static func sentenceCount(_ text: String) -> Int {
        var count = 0
        var openSentence = false
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if sentenceEnds.contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // A stop between two digits is a decimal point, not the end of a sentence.
                let insideNumber = character == "." && (next?.isNumber ?? false)
                let endsHere = next == nil || (next?.isWhitespace ?? false)
                if openSentence, endsHere, !insideNumber {
                    count += 1
                    openSentence = false
                }
            } else if !character.isWhitespace {
                openSentence = true
            }
        }
        return count + (openSentence ? 1 : 0)
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}
