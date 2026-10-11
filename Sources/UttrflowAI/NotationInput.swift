import UttrflowCore

/// The recogniser's text read for a grammar: its marks and capitals are pauses, never notation the speaker said.
enum NotationInput {
    /// The marks a recogniser writes at a pause; a mark said aloud is a word of its own and is not touched.
    private static let pauseMarks = WordShape.clauseMarks

    /// The draft with each pause mark taken off its word and each capital that only opened a clause lowered.
    static func settled(_ draft: Draft, by pass: PassID) -> Draft {
        var draft = draft
        var opensClause = true
        for index in draft.presentIndices {
            let text = draft.words[index].text
            // A word a pass has already written, such as a comma from the spoken word "comma", is not the recogniser's.
            guard text == draft.words[index].heard else {
                opensClause = false
                continue
            }
            let shape = WordShape(text)
            guard !shape.core.isEmpty else { continue }
            var core = shape.core
            if opensClause, isTitleCase(core) { core = core.prefix(1).lowercased() + core.dropFirst() }
            let suffix = shape.suffix.filter { !pauseMarks.contains($0) }
            let written = shape.prefix + core + suffix
            if written != text { draft.replace(at: index, with: written, by: pass) }
            opensClause = shape.suffix.contains(where: pauseMarks.contains)
        }
        return draft
    }

    /// A word whose first letter is a capital and whose others are not, as a recogniser capitalises a clause's first word.
    private static func isTitleCase(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        let rest = word.dropFirst()
        return !rest.isEmpty && rest.allSatisfy { $0.isLowercase || !$0.isLetter }
    }
}
