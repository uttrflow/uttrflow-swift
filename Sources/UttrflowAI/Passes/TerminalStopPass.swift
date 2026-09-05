public import UttrflowCore

/// Adds or takes back the final full stop the way the formatter's stop policy and layout say.
public struct TerminalStopPass: CleaningPass {
    public static let id: PassID = .terminalStop

    public let policy: TerminalStopPolicy
    public let layout: LayoutPolicy

    public init(policy: TerminalStopPolicy = .always, layout: LayoutPolicy = .paragraphs) {
        self.policy = policy
        self.layout = layout
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if layout.contains(.singleLine) { Self.flatten(&draft) }
        if layout.contains(.paragraphs), policy != .never { Self.stopParagraphs(&draft) }
        guard let last = draft.presentIndices.last, !draft.words[last].isLayoutMark else { return draft }
        let word = draft.words[last].text
        let finished: String
        switch policy {
        case .always:
            finished = finishedLast(word, in: draft)
        case .never:
            finished = WordShape.withoutTrailingStop(word)
        case .offForShortMessages(let sentences):
            let stopped = finishedLast(word, in: draft)
            finished =
                Self.sentenceCount(draft.text) <= sentences ? WordShape.withoutTrailingStop(stopped) : stopped
        }
        draft.replace(at: last, with: finished, by: Self.id)
        return draft
    }

    /// The last word with a stop unless it ends a list item, or the layout keeps newlines and the text holds one.
    private func finishedLast(_ word: String, in draft: Draft) -> String {
        if Self.lastSegmentIsListItem(draft) { return word }
        if layout.contains(.preserveNewlines), draft.text.contains(where: \.isNewline) { return word }
        return WordShape.finished(word)
    }

    /// Every layout mark taken out, so the words join on one line.
    private static func flatten(_ draft: inout Draft) {
        for index in draft.presentIndices where draft.words[index].isLayoutMark {
            draft.remove(at: index, by: id)
        }
    }

    /// Ends each paragraph of three or more words before a blank line with a full stop; a list item gets none.
    private static func stopParagraphs(_ draft: inout Draft) {
        var opening: Draft.Word?
        var paragraph: [Int] = []
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard word.isLayoutMark else {
                paragraph.append(index)
                continue
            }
            if word.text.hasPrefix("\n\n"), let last = paragraph.last, paragraph.count >= 3,
                !(opening?.isListMark ?? false)
            {
                draft.replace(at: last, with: WordShape.finished(draft.words[last].text), by: id)
            }
            if word.text.hasPrefix("\n\n") || word.isListMark {
                opening = word
                paragraph = []
            }
        }
    }

    /// Whether the words after the last paragraph or list mark are a list item.
    private static func lastSegmentIsListItem(_ draft: Draft) -> Bool {
        let marks = draft.presentIndices.map { draft.words[$0] }.filter { $0.isLayoutMark }
        return marks.last(where: { $0.text.hasPrefix("\n\n") || $0.isListMark })?.isListMark ?? false
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
