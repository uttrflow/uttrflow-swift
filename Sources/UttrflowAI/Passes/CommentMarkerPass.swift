import UttrflowCore

/// Writes a comment's opening annotation word the way the lexicon writes it, when a spoken colon follows it.
struct CommentMarkerPass: WholeTextCleaningPass {
    static let id: PassID = "commentMarker"
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// Whether the caret stands where a comment's first word goes in a code editor.
    let opensComment: Bool

    private static let annotations = TechnicalLexicon.terms.filter {
        $0.category == .annotation && $0.applies(in: .codeEditor)
    }

    func apply(_ draft: Draft) -> Draft {
        guard opensComment else { return draft }
        var draft = draft
        let live = draft.presentIndices
        for term in Self.annotations {
            guard let said = Self.length(of: term, in: live, of: draft), said > 0 else { continue }
            let last = draft.shape(at: live[said - 1])
            let spokenColon =
                last.suffix.isEmpty && said < live.count && draft.shape(at: live[said]).key == "colon"
                && draft.shape(at: live[said]).suffix.isEmpty
            guard last.suffix == ":" || spokenColon else { return draft }
            let opening = draft.shape(at: live[0]).prefix
            draft.replace(at: live[0], with: opening + term.id + ":", by: Self.id)
            for index in live[1..<(spokenColon ? said + 1 : said)] { draft.remove(at: index, by: Self.id) }
            return draft
        }
        return draft
    }

    /// How many opening words say `term`, by its written form or one of its spoken forms, or nil.
    private static func length(of term: TechnicalTerm, in live: [Int], of draft: Draft) -> Int? {
        guard let first = live.first else { return nil }
        if draft.shape(at: first).key == term.id.lowercased() { return 1 }
        return term.spoken.map { $0.split(separator: " ").map(String.init) }
            .first { draft.spells($0, at: 0, in: live) }?.count
    }
}
