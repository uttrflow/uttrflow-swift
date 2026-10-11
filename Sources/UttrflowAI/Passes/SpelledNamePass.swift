import UttrflowCore

/// Writes a listed name said as letters and number words as the lexicon writes it, "e c two" as "EC2", before the number and initialism passes split it.
struct SpelledNamePass: PieceCleaningPass {
    static let id: PassID = .spelledName
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    private let destination: Destination

    init(destination: Destination = .plain) {
        self.destination = destination
    }

    /// The lexicon's spelled names with each spoken form's words, the longest first.
    private static let names: [(term: TechnicalTerm, words: [String])] = TechnicalLexicon.terms
        .filter { $0.category == .spelledName }
        .flatMap { term in term.spoken.map { (term, $0.split(separator: " ").map(String.init)) } }
        .sorted { $0.words.count > $1.words.count }

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard
                let found = Self.names.first(where: { name in
                    name.term.applies(in: destination)
                        && isSaid(name.words, at: position, in: live, of: draft)
                })
            else {
                position += 1
                continue
            }
            let first = live[position]
            let last = live[position + found.words.count - 1]
            let written =
                WordShape(draft.words[first].text).prefix + found.term.id
                + WordShape(draft.words[last].text).suffix
            draft.replace(at: first, with: written, by: Self.id)
            for index in live[(position + 1)..<(position + found.words.count)] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange((position + 1)..<(position + found.words.count))
            position += 1
        }
        return draft
    }

    /// Whether the live words from `position` are exactly `words`, unbroken by a mark, a cut-off or a layout word.
    private func isSaid(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard draft.spells(words, at: position, in: live) else { return false }
        for offset in 0..<words.count {
            let index = live[position + offset]
            let shape = draft.shape(at: index)
            guard !shape.isCutOff, !draft.words[index].isLayoutMark else { return false }
            if offset > 0, index != live[position + offset - 1] + 1 { return false }
            if offset < words.count - 1, shape.endsClause { return false }
        }
        return true
    }
}
