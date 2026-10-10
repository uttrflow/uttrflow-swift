import Foundation
import UttrflowCore

/// Writes spoken symbol commands in code or at a command line, abstaining where words read as prose.
struct CodeEditorCommandsPass: PieceCleaningPass {
    static let id: PassID = .codeEditorCommands
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// Where the words go; a command line takes only the rows that name it, so its brackets stay marks.
    var destination: Destination = .codeEditor

    /// What the screen said for the notation, to which the speech's own cues are added.
    var evidence = Applicability(cues: [.caretInCode])

    func apply(_ draft: Draft) -> Draft {
        let words = draft.presentIndices.map { Self.bare(draft.words[$0].text) }
        let evidence = NotationEvidence.applicability(of: words, given: evidence)
        guard evidence.activates(at: NotationEvidence.activationThreshold) else { return draft }
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
        if position > 0, Self.bare(draft.words[live[position - 1]].text) == NotationEvidence.nounMarker {
            return nil
        }
        return SpokenCommands.codeSymbols.first {
            ($0.destinations?.contains(destination) ?? (destination == .codeEditor))
                && draft.spells($0.words, at: position, in: live, acrossSentences: true)
        }
    }

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
