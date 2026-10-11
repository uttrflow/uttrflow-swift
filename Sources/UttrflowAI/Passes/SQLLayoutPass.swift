import UttrflowCore

/// Lays a spoken SQL statement out on clause lines, or keeps it on one line where the field shows that convention; adds whitespace only.
struct SQLLayoutPass: PieceCleaningPass {
    static let id: PassID = "sqlLayout"
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    static let orderIndependentWith: Set<PassID> = []

    /// The layout of the statement before the caret, which the lines follow.
    var layout = SQLLayout.unknown

    /// A clause keyword the notation wrote, and where its line starts in the live words.
    private struct Target {
        let position: Int
        let opening: SQLLayout.Opening
    }

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        let openings = self.openings(in: live, of: draft)
        guard linesApply(count: openings.count) else { return draft }
        var draft = draft
        // Last first, so an inserted break never moves a position still to be handled.
        for target in openings.reversed() where target.opening != .start {
            lay(target, in: live, of: &draft)
        }
        return draft
    }

    /// Clause lines follow the field's convention, or the speech's own when the field shows none: two or more clauses.
    private func linesApply(count: Int) -> Bool {
        switch layout.convention {
        case .clauseLines: count > 0
        case .oneLine: false
        case .unknown: count >= 2
        }
    }

    /// The statement keywords the notation wrote, in order; a join is placed at the first word of its name.
    private func openings(in live: [Int], of draft: Draft) -> [Target] {
        let keys = live.map { Self.key(of: draft.words[$0]) }
        var found: [Target] = []
        for position in live.indices {
            guard let key = keys[position], draft.words[live[position]].isWrittenByNotation else { continue }
            let next = position + 1 < keys.count ? keys[position + 1] : nil
            let previous = position > 0 ? keys[position - 1] : nil
            guard let opening = SQLLayout.opening(key, next: next, previous: previous) else { continue }
            var start = position
            while opening == .join, start > 0, SQLLayout.isJoinModifier(keys[start - 1] ?? "") {
                start -= 1
            }
            found.append(Target(position: start, opening: opening))
        }
        return found
    }

    private static func key(of word: Draft.Word) -> String? {
        let key = CodeEditorCommandsPass.bare(word.text)
        return key.isEmpty ? nil : key
    }

    /// Puts a line break and indent before the target, unless the speaker already broke the line there or a parenthesis is open.
    private func lay(_ target: Target, in live: [Int], of draft: inout Draft) {
        let indent = layout.indent(for: target.opening)
        let index = live[target.position]
        if target.position == 0 {
            layAtCaret(indent: indent, at: index, of: &draft)
            return
        }
        guard !draft.words[live[target.position - 1]].isLayoutMark,
            Self.depth(before: target.position, in: live, of: draft) + layout.depth == 0
        else { return }
        draft.insert("\n" + indent, at: index, by: Self.id)
    }

    /// The first word of the piece breaks away from the text before the caret, or takes the indent a blank line lacks.
    private func layAtCaret(indent: String, at index: Int, of draft: inout Draft) {
        guard layout.isMidStatement, layout.depth == 0, let line = layout.caretLine else { return }
        guard line.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            draft.insert("\n" + indent, at: index, by: Self.id)
            return
        }
        guard indent.hasPrefix(line), indent.count > line.count else { return }
        let rest = String(indent.dropFirst(line.count))
        draft.replace(at: index, with: rest + draft.words[index].text, by: Self.id)
    }

    /// Parentheses the piece opened before `position` and did not close.
    private static func depth(before position: Int, in live: [Int], of draft: Draft) -> Int {
        let text = live[..<position].map { draft.words[$0].text }.joined()
        return text.reduce(0) { $1 == "(" ? $0 + 1 : ($1 == ")" ? max(0, $0 - 1) : $0) }
    }
}

extension Draft.Word {
    /// Whether a spoken-command pass wrote the word's current text.
    fileprivate var isWrittenByNotation: Bool {
        if case .replaced(by: .codeEditorCommands, _) = state { return true }
        return false
    }
}
