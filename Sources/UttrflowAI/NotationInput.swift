import UttrflowCore

/// The recogniser's text read for a grammar: its marks and capitals are pauses, never notation the speaker said.
enum NotationInput {
    /// The marks a recogniser writes at a pause; a mark said aloud is a word of its own and is not touched.
    private static let pauseMarks = WordShape.clauseMarks

    /// The draft with each pause mark taken off its word and each capital that only opened a clause lowered.
    static func settled(_ draft: Draft, by pass: PassID) -> Draft {
        var draft = draft
        var opensClause = true
        let live = draft.presentIndices
        for (position, index) in live.enumerated() {
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
            let keepsColon = registryTagColon(at: position, in: live, of: draft)
            let suffix = shape.suffix.filter { !pauseMarks.contains($0) || keepsColon && $0 == ":" }
            let written = shape.prefix + core + suffix
            if written != text { draft.replace(at: index, with: written, by: pass) }
            opensClause = !keepsColon && shape.suffix.contains(where: pauseMarks.contains)
        }
        return draft
    }

    /// A host-qualified image path's colon before a literal version is notation rather than a clause pause.
    private static func registryTagColon(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let shape = draft.shape(at: live[position])
        guard shape.suffix == ":", let slash = shape.core.firstIndex(of: "/"),
            TechnicalToken.classify(String(shape.core[..<slash])) == .hostname,
            TechnicalToken.classify(shape.core) == .path,
            position + 1 < live.count,
            TechnicalToken.classify(draft.words[live[position + 1]].text) == .version
        else { return false }
        return true
    }

    /// A word whose first letter is a capital and whose others are not, as a recogniser capitalises a clause's first word.
    private static func isTitleCase(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        let rest = word.dropFirst()
        return !rest.isEmpty && rest.allSatisfy { $0.isLowercase || !$0.isLetter }
    }
}
