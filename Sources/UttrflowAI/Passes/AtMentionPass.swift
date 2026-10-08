import Foundation
import UttrflowCore

/// Writes "at Sam" as "@Sam" when a chat message or one of its clauses opens with it; registered for messaging only. See `Docs/cleanup.md`.
struct AtMentionPass: WholeTextCleaningPass {
    static let id: PassID = .atMention
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// The text before the caret, which says whether the message's first word opens a clause.
    let precedingText: String?

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        for position in live.indices.dropLast() {
            let at = live[position]
            let name = live[position + 1]
            let atShape = draft.shape(at: at)
            guard atShape.key == "at", atShape.suffix.isEmpty, !draft.words[name].isLayoutMark,
                opensClause(at: position, in: live, of: draft),
                Self.isName(draft.shape(at: name).core)
            else { continue }
            draft.replace(at: name, with: atShape.prefix + "@" + draft.words[name].text, by: Self.id)
            draft.remove(at: at, by: Self.id)
        }
        return draft
    }

    /// Whether the word at `position` starts the message or follows a mark that ends a clause.
    private func opensClause(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let before =
            position == 0
            ? (precedingText ?? "").trimmingCharacters(in: .whitespaces)
            : draft.shape(at: live[position - 1]).suffix
        guard let last = before.last else { return position == 0 }
        return last.isNewline || WordShape.clauseMarks.contains(last)
    }

    /// A capitalised name of letters alone: "Sam's", "SAM" read as a word and calendar words stay as spoken.
    static func isName(_ core: String) -> Bool {
        guard let first = core.first, first.isUppercase, core.allSatisfy(\.isLetter),
            core.dropFirst().contains(where: \.isLowercase)
        else { return false }
        return !FirstWordPass.isCalendarWord(core)
    }
}
