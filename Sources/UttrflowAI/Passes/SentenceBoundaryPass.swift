import UttrflowCore

/// Takes back a comma that splits a closed phrase and a full stop when the same boundary evidence used at piece seams shows a sentence continuing, and ends the item that runs into the next numbered marker of a run the recogniser numbered.
struct SentenceBoundaryPass: WholeTextCleaningPass {
    static let id: PassID = "sentenceBoundary"
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    static let orderIndependentWith: Set<PassID> = [.firstWord]

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        Self.endItemsBeforeMarkers(&draft)
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
            // "the" closing a Hindi clause is थे, which ends a sentence; the evidence reads only the English word.
            guard !draft.isHindi(at: index) else { continue }
            let clause = Self.clause(endingAt: position, in: live, of: draft)
            // "Hi all." and "the one we spoke of." end their sentences though their last word could lead on.
            guard !TerminalStopPass.isGreetingAddress(clause, in: draft),
                !SentenceBoundaryEvidence.endsOnStrandedPreposition(
                    clause.dropLast().map { draft.words[$0].text } + [
                        WordShape.withoutTrailingStop(draft.words[index].text)
                    ])
            else { continue }
            let following = Self.sentenceAfter(position, in: live, of: draft)
            guard
                SentenceBoundaryEvidence.sentenceRunsOn(
                    WordShape.withoutTrailingStop(draft.words[index].text), into: following,
                    after: Self.wordsBeforeLast(position, in: live, of: draft)
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

    /// The word indices of the sentence ending at `position`, back to the last sentence end or layout mark.
    private static func clause(endingAt position: Int, in live: [Int], of draft: Draft) -> [Int] {
        var start = position
        while start > 0, !draft.words[live[start - 1]].isLayoutMark,
            !draft.shape(at: live[start - 1]).endsSentence
        {
            start -= 1
        }
        return Array(live[start...position])
    }

    /// The up to two words before the one at `position`, the context a noun "look" needs.
    private static func wordsBeforeLast(_ position: Int, in live: [Int], of draft: Draft) -> String {
        live[max(0, position - 2)..<position].map { draft.words[$0].text }.joined(separator: " ")
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

    /// The number a word such as "2." marks, or nil for any other word.
    private static func markerValue(_ text: String) -> Int? {
        guard text.hasSuffix("."), text.count <= 3 else { return nil }
        let digits = text.dropLast()
        return digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) ? Int(digits) : nil
    }

    /// Ends the item before a numbered marker the recogniser left without a stop, when the markers on both sides open sentences.
    private static func endItemsBeforeMarkers(_ draft: inout Draft) {
        let live = draft.presentIndices
        let values = live.map { markerValue(draft.words[$0].text) }
        func opensSentence(_ position: Int) -> Bool {
            position == 0 || draft.shape(at: live[position - 1]).endsSentence
                || draft.words[live[position - 1]].isLayoutMark
        }
        for position in live.indices where position > 0 && position + 1 < live.count {
            guard let value = values[position], value >= 2, !opensSentence(position),
                draft.shape(at: live[position - 1]).suffix.isEmpty,
                !draft.words[live[position - 1]].isLayoutMark,
                draft.shape(at: live[position + 1]).core.first?.isUppercase == true,
                let before = values[..<position].lastIndex(where: { $0 != nil }),
                values[before] == value - 1, opensSentence(before),
                let after = values[(position + 1)...].firstIndex(where: { $0 != nil }),
                values[after] == value + 1, opensSentence(after)
            else { continue }
            draft.replace(
                at: live[position - 1], with: WordShape.finished(draft.words[live[position - 1]].text),
                by: Self.id)
        }
    }
}
