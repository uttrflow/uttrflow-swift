import UttrflowAI
import UttrflowCore

extension PieceJoiner {
    /// One piece ended at a seam, unless the words on either side of the cut say the sentence ran through it. See `Docs/cleanup-design.md` §7.
    static func endedAtSeam(
        _ text: String, before next: String, runsOn: Bool, under formatter: DestinationFormatter
    ) -> String {
        if endsWithSpokenLineCommand(text, before: next) { return withoutSentenceStop(text) }
        if formatter.terminalStop == .never { return withoutSentenceStop(text) }
        if WordTokens.words(next, .display).isEmpty { return text }
        let piece = Draft(keepingLineBreaks: text)
        guard let last = text.last, !last.isNewline, !piece.endsInListItem,
            !(formatter.layout.contains(.preserveNewlines) && text.contains(where: \.isNewline))
        else { return text }
        return runsOn ? withoutSentenceStop(text) : WordShape.finished(text)
    }

    /// Whether a piece ends with the spoken command that opens a new line, read with the piece after it.
    private static func endsWithSpokenLineCommand(_ text: String, before next: String) -> Bool {
        let count = Draft(keepingLineBreaks: text).presentIndices.count
        return count >= 2 && isLineCommand(at: count - 2, in: Draft(keepingLineBreaks: text + " " + next))
    }

    /// Whether the live words at `position` ask for a new line, rather than naming one as in "a new line of shoes".
    static func isLineCommand(at position: Int, in draft: Draft) -> Bool {
        let live = draft.presentIndices
        guard position >= 0, position + 1 < live.count else { return false }
        return draft.shape(at: live[position]).key == "new"
            && draft.shape(at: live[position + 1]).key == "line"
            && !MentionGuard.namesLayout(at: position, spanning: 2, in: draft)
    }

    /// Removes a sentence stop while retaining a final dot owned by the abbreviation itself.
    private static func withoutSentenceStop(_ text: String) -> String {
        if let last = WordTokens.words(text, .display).last {
            let shape = WordShape(last)
            if shape.suffix.first == ".", Abbreviations.ownsRegisteredStop(shape.core) { return text }
        }
        return WordShape.withoutTrailingStop(text)
    }

}
