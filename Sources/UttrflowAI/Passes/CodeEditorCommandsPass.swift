import Foundation
import UttrflowCore

/// Writes spoken symbol commands in code or at a command line, abstaining where words read as prose.
struct CodeEditorCommandsPass: PieceCleaningPass {
    static let id: PassID = .codeEditorCommands
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// A word that, just before a notation word, makes it a noun ("a dot") rather than a command.
    static let nounMarker = "a"

    /// Where the words go; a command line takes only the rows that name it, so its brackets stay marks.
    var destination: Destination = .codeEditor

    func apply(_ draft: Draft) -> Draft {
        if Self.readsAsProse(draft) { return draft }
        var draft = draft
        var position = 0
        while position < draft.presentIndices.count {
            let live = draft.presentIndices
            guard position < live.count else { break }
            if let symbol = symbol(at: position, in: live, of: draft) {
                apply(symbol, at: position, in: live, to: &draft)
            }
            position += 1
        }
        return draft
    }

    private func symbol(at position: Int, in live: [Int], of draft: Draft) -> SpokenCommand? {
        if position > 0, Self.bare(draft.words[live[position - 1]].text) == Self.nounMarker { return nil }
        return SpokenCommands.codeSymbols.first {
            ($0.destinations?.contains(destination) ?? (destination == .codeEditor))
                && draft.spells($0.words, at: position, in: live, acrossSentences: true)
        }
    }

    /// Whether a present word is prose evidence: an article, or a determiner before a longer non-notation word ("our costs", not "this dot").
    static func readsAsProse(_ draft: Draft) -> Bool {
        let words = draft.presentIndices.map { bare(draft.words[$0].text) }
        return words.indices.contains { index in
            if FunctionWords.prose.contains(words[index]) { return true }
            guard FunctionWords.determiners.contains(words[index]), index + 1 < words.count else {
                return false
            }
            let next = words[index + 1]
            return next.count > 1 && FunctionWords.isContent(next) && !notationWords.contains(next)
        }
    }

    /// Every word that begins a spoken notation command.
    private static let notationWords: Set<String> = Set(SpokenCommands.codeSymbols.compactMap(\.words.first))

    private static func bare(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .letters.inverted)
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
