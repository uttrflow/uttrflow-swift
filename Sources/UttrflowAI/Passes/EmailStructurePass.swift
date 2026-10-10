import UttrflowCore

extension PassID {
    /// An email body's greeting and sign-off set on lines of their own.
    static let emailStructure: PassID = "emailStructure"
}

/// Sets an email body's leading greeting and trailing sign-off on their own paragraphs: "Hi Sam, can you send it. Thanks, Ana" → three. See `Docs/cleanup.md`.
struct EmailStructurePass: WholeTextCleaningPass {
    static let id: PassID = .emailStructure
    /// A paragraph mark is layout, not a word, so the pass adds none; it is not repeated on its own output.
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// The most words a greeting's name takes: "Hi Sam", "Dear Dr Jones", "Hello Mary Ann Smith".
    private static let longestName = 3

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        // The sign-off first, so the greeting's insertion does not move the index it was found at.
        separateSignOff(in: &draft)
        separateGreeting(in: &draft)
        return draft
    }

    /// Starts the closing on its own paragraph when a sentence of the body ends just before it.
    private func separateSignOff(in draft: inout Draft) {
        guard let start = TerminalStopPass.emailSignOffStart(in: draft) else { return }
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: start), position > 0,
            !draft.words[live[position - 1]].isLayoutMark
        else { return }
        draft.insert("\n\n", at: start, by: Self.id)
    }

    /// Ends the greeting's paragraph after its comma-closed name when body text carries on in the same one.
    private func separateGreeting(in draft: inout Draft) {
        let live = draft.presentIndices
        let paragraph = Array(live.prefix { !draft.words[$0].isLayoutMark })
        guard paragraph.count < live.count,
            let opener = TerminalStopPass.greetingOpenerLength(paragraph, in: draft)
        else { return }
        for nameLength in 1...Self.longestName where opener + nameLength < paragraph.count {
            let name = paragraph[opener..<(opener + nameLength)]
            let closing = draft.shape(at: name.last ?? 0).suffix
            guard closing.contains(",") else { continue }
            let open = paragraph[..<(opener + nameLength - 1)]
            guard open.allSatisfy({ !draft.shape(at: $0).suffix.contains(where: { ",.;:!?".contains($0) }) })
            else { return }
            draft.insert("\n\n", at: paragraph[opener + nameLength], by: Self.id)
            return
        }
    }
}
