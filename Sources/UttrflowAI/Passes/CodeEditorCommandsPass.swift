import UttrflowCore

/// Writes spoken symbol commands in executable code.
struct CodeEditorCommandsPass: PieceCleaningPass {
    static let id: PassID = .codeEditorCommands

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var position = 0
        while position < draft.presentIndices.count {
            let live = draft.presentIndices
            guard position < live.count else { break }
            if let symbol = Self.symbol(at: position, in: live, of: draft) {
                apply(symbol, at: position, in: live, to: &draft)
            }
            position += 1
        }
        return draft
    }

    private static func symbol(at position: Int, in live: [Int], of draft: Draft) -> SpokenCommand? {
        SpokenCommands.codeSymbols.first {
            $0.isEnabled(in: .codeEditor)
                && draft.spells($0.words, at: position, in: live, acrossSentences: true)
        }
    }

    private func apply(_ command: SpokenCommand, at position: Int, in live: [Int], to draft: inout Draft) {
        let consumed = command.words.count
        let text = command.text
        let suffix = draft.shape(at: live[position + consumed - 1]).suffix
        if text == ")", position > 0, draft.words[live[position - 1]].text == "(" {
            draft.replace(at: live[position - 1], with: "()" + suffix, by: Self.id)
            for offset in 0..<consumed { draft.remove(at: live[position + offset], by: Self.id) }
            return
        }
        draft.replace(at: live[position], with: text + suffix, by: Self.id)
        for offset in 1..<consumed { draft.remove(at: live[position + offset], by: Self.id) }
    }
}
