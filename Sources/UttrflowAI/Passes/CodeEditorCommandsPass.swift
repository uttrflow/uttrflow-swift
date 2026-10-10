import Foundation
import UttrflowCore

/// Writes spoken symbol commands and statement keywords in code, a query or a command line, abstaining where words read as prose.
struct CodeEditorCommandsPass: PieceCleaningPass {
    static let id: PassID = .codeEditorCommands
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// Where the words go; a command line takes only the rows that name it, so its brackets stay marks.
    var destination: Destination = .codeEditor

    /// What the screen said for the notation, to which the speech's own cues are added.
    var evidence = Applicability(cues: [.caretInCode])

    func apply(_ draft: Draft) -> Draft {
        let words = draft.presentIndices.map { Self.bare(draft.words[$0].text) }
        let screen = NotationEvidence.applicability(destination: destination, opening: words.first, given: evidence)
        let evidence = NotationEvidence.applicability(of: words, given: screen)
        guard evidence.activates(at: NotationEvidence.activationThreshold) else { return draft }
        var draft = draft
        var position = 0
        while position < draft.presentIndices.count {
            let live = draft.presentIndices
            guard position < live.count else { break }
            if let symbol = symbol(at: position, in: live, of: draft) {
                // A joined name stands where its first part stood, so the next dot is read from there.
                if join(symbol, at: position, in: live, of: &draft) { continue }
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
        return Self.rows.first {
            ($0.destinations?.contains(destination) ?? (destination == .codeEditor))
                && draft.spells($0.words, at: position, in: live, acrossSentences: true)
        }
    }

    /// The code symbol rows, then the statement keywords, so a symbol phrase opening on a keyword is tried first.
    private static let rows = SpokenCommands.codeSymbols + SpokenCommands.keywords

    private static func bare(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .letters.inverted)
    }

    /// Writes a joining symbol between the names on both sides of it, as "orders dot id" is `orders.id`; false when either side is no name.
    private func join(_ command: SpokenCommand, at position: Int, in live: [Int], of draft: inout Draft) -> Bool {
        let after = position + command.words.count
        guard command.placement == .joining, position > 0, after < live.count else { return false }
        let left = draft.words[live[position - 1]].text
        let right = draft.words[live[after]].text
        guard Self.isName(left), Self.isName(right.trimmingCharacters(in: .punctuationCharacters)) else {
            return false
        }
        draft.replace(at: live[position - 1], with: left + command.text + right, by: Self.id)
        for offset in position...after { draft.remove(at: live[offset], by: Self.id) }
        return true
    }

    /// A word an identifier can be: letters, digits and underscores, with a letter or underscore first.
    private static func isName(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
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
