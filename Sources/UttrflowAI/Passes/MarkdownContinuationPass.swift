import UttrflowCore

/// Writes the next list mark or heading mark of the Markdown already written when the speaker says "next item", "new item" or "new heading".
struct MarkdownContinuationPass: PieceCleaningPass {
    static let id: PassID = .markdownContinuation
    static let laws: Set<PassLaw> = [.idempotent, .addsNoWords, .latinOnly]

    let position: MarkdownPosition

    /// The phrases that ask for a continuation, each opening a sentence.
    private static let itemPhrases = [["next", "item"], ["new", "item"]]
    private static let headingPhrase = ["new", "heading"]

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var written = 0
        var at = 0
        while at < live.count {
            guard at == 0 || draft.shape(at: live[at - 1]).endsSentence,
                let found = phrase(at: at, in: live, of: draft),
                let mark = mark(for: found.isHeading, at: at, skipping: written)
            else {
                at += 1
                continue
            }
            if !found.isHeading { written += 1 }
            draft.replace(at: live[at], with: mark, by: Self.id)
            for index in live[at + 1..<at + found.length] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange(at + 1..<at + found.length)
            at += 1
        }
        return draft
    }

    /// The phrase spoken at `at`, whole and inside its sentence.
    private func phrase(at: Int, in live: [Int], of draft: Draft) -> (length: Int, isHeading: Bool)? {
        if Self.itemPhrases.contains(where: { draft.spells($0, at: at, in: live) }) { return (2, false) }
        return draft.spells(Self.headingPhrase, at: at, in: live) ? (2, true) : nil
    }

    /// The mark to write, or `nil` where the position gives none and the words stay words.
    private func mark(for isHeading: Bool, at: Int, skipping written: Int) -> String? {
        guard isHeading else { return position.continuation(skipping: written).map { "\n" + $0 } }
        guard let heading = position.nextHeading else { return nil }
        // A heading stands on a line of its own, so a line with words on it is broken first; the joiner spaces a bare mark.
        return position.isOnBlankLine && at == 0 ? heading : "\n\n" + heading + " "
    }
}
