import UttrflowCore

/// Writes a spoken quotation in a query editor as the statement writes it: a value in single quotes, a name in the field's own mark.
struct SQLQuotingPass: PieceCleaningPass {
    static let id: PassID = "sqlQuoting"
    // It writes quote marks, so it adds a word the draft never held.
    static let laws: Set<PassLaw> = [.idempotent, .keepsDigits, .latinOnly]
    static let orderIndependentWith: Set<PassID> = []

    /// The mark the statement before the caret puts round names; `nil` when it shows none.
    var style: SQLQuoting.IdentifierStyle?
    /// The last word before the caret, which decides whether a quotation opening the piece is a value.
    var precedingWord: String?

    /// The most words one quotation spans.
    private static let reach = 12

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let end = closing(of: position, in: live, of: draft) else {
                position += 1
                continue
            }
            let previous = position > 0 ? draft.words[live[position - 1]].text : precedingWord
            rewrite(live[position...end], after: previous, in: &draft)
            position = end + 1
        }
        return draft
    }

    /// Where the quotation opened at `position` closes; `nil` when no word there opens one or none closes it in reach.
    private func closing(of position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard draft.words[live[position]].text.hasPrefix("\"") else { return nil }
        let limit = min(live.count, position + Self.reach)
        for candidate in position..<limit {
            let text = draft.words[live[candidate]].text
            let from = candidate == position ? text.index(after: text.startIndex) : text.startIndex
            if text[from...].contains("\"") { return candidate }
        }
        return nil
    }

    private func rewrite(_ span: ArraySlice<Int>, after previous: String?, in draft: inout Draft) {
        let isValue = SQLQuoting.isValuePosition(after: previous)
        guard isValue || (style != nil && style != .double) else { return }
        var texts = span.map { draft.words[$0].text }
        texts[0].removeFirst()
        let last = texts.count - 1
        guard let closer = texts[last].lastIndex(of: "\"") else { return }
        let tail = String(texts[last][texts[last].index(after: closer)...])
        texts[last] = String(texts[last][..<closer])
        let marks = isValue ? ("'", "'") : SQLQuoting.marks(for: style ?? .double)
        if isValue { texts = texts.map { $0.replacingOccurrences(of: "'", with: "''") } }
        texts[0] = marks.0 + texts[0]
        texts[last] += marks.1 + tail
        for (index, text) in zip(span, texts) { draft.replace(at: index, with: text, by: Self.id) }
    }
}
