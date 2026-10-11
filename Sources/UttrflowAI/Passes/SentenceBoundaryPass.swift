import UttrflowCore

/// Takes back a comma that splits a closed phrase and a full stop when the same boundary evidence used at piece seams shows a sentence continuing.
struct SentenceBoundaryPass: WholeTextCleaningPass {
    static let id: PassID = "sentenceBoundary"
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    static let orderIndependentWith: Set<PassID> = [.firstWord]

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        guard live.count > 1 else { return draft }
        for position in live.indices.dropLast() {
            let index = live[position]
            let nextIndex = live[position + 1]
            let shape = draft.shape(at: index)
            if shape.suffix == ",",
                SentenceBoundaryEvidence.commaSplitsClosedPhrase(
                    draft.words[index].text, into: Self.sentenceAfter(position, in: live, of: draft))
            {
                draft.replace(at: index, with: String(draft.words[index].text.dropLast()), by: Self.id)
                continue
            }
            guard shape.suffix == ".", !draft.words[nextIndex].isLayoutMark else { continue }
            guard !Abbreviations.ownsStop(shape.core) else { continue }
            let following = Self.sentenceAfter(position, in: live, of: draft)
            guard
                !SentenceBoundaryEvidence.endsInNounLook(
                    Self.sentenceBefore(position, in: live, of: draft))
            else { continue }
            guard
                SentenceBoundaryEvidence.sentenceRunsOn(
                    WordShape.withoutTrailingStop(draft.words[index].text), into: following
                )
                    || SentenceBoundaryEvidence.modalAwaitsVerb(
                        Self.sentenceBefore(position, in: live, of: draft), into: following)
            else { continue }

            let conjunction = draft.shape(at: nextIndex).key
            let mark = conjunction == "but" || conjunction == "so" ? "," : ""
            let repaired = WordShape.withoutTrailingStop(draft.words[index].text)
            draft.replace(
                at: index, with: mark.isEmpty ? repaired : WordShape.marked(repaired, with: mark), by: Self.id
            )

            let next = draft.shape(at: nextIndex)
            guard next.key != "i", !FirstWordPass.keepsCapital(next.core),
                !FirstWordPass.isProperName(next.core, in: draft.text),
                !FirstWordPass.isCalendarWord(next.core)
            else { continue }
            draft.replace(at: nextIndex, with: WordShape.lowercased(draft.words[nextIndex].text), by: Self.id)
        }
        return draft
    }

    /// The up to three words ending at `position`, the stop taken off the last: the subject a modal or "be" needs.
    private static func sentenceBefore(_ position: Int, in live: [Int], of draft: Draft) -> String {
        let start = max(0, position - 2)
        let words = live[start...position].map { draft.words[$0].text }
        return words.dropLast().joined(separator: " ")
            + (words.count > 1 ? " " : "") + WordShape.withoutTrailingStop(words[words.count - 1])
    }

    /// The words after `position` through the next sentence end, at least two: all the boundary evidence reads.
    private static func sentenceAfter(_ position: Int, in live: [Int], of draft: Draft) -> String {
        var words: [String] = []
        var tokens = 0
        var ended = false
        for index in live[(position + 1)...] {
            let text = draft.words[index].text
            let written = WordTokens.words(text, .display)
            words.append(text)
            tokens += written.count
            ended = ended || written.contains { WordShape($0).endsSentence }
            if ended, tokens > 1 { break }
        }
        return words.joined(separator: " ")
    }
}
