// Places the recogniser's doubted words on the written text, using the aligner the corrections use.
import UttrflowAI
import UttrflowCore

extension DoubtfulWords {
    /// Words that stop a doubted neighbour reading as a plain mishearing, since a lost negator flips the meaning.
    private static let negators: Set<String> = [
        "not", "no", "never", "don't", "doesn't", "didn't", "isn't", "can't", "won't",
    ]

    /// The doubted words of `spoken`, the transcript with the dictionary's spellings settled, placed on `written`.
    static func locating(_ spoken: Transcription, in written: String) -> DoubtfulWords {
        let draft = Draft(transcription: spoken)
        guard draft.confidencesAreReal else { return .notAvailable }
        let heard = draft.words.filter { !$0.text.hasPrefix("\n") }
        let writtenWords = written.spokenWords
        let landed = Self.landing(heard.map(\.text), on: writtenWords)
        var spans: [DoubtfulWordSpan] = []
        var unplaced = 0
        for (index, word) in heard.enumerated() {
            guard let kind = Self.kind(of: index, in: heard, landed: landed, written: writtenWords)
            else { continue }
            guard let column = landed[index] else {
                unplaced += 1
                continue
            }
            let evidence = UInt8(min(3, max(0, Int(word.confidence * 4))))
            if let last = spans.last, last.kind == kind, last.range.upperBound == column {
                spans[spans.count - 1] = DoubtfulWordSpan(
                    range: last.range.lowerBound..<(column + 1), kind: kind,
                    evidence: min(last.evidence, evidence))
            } else if spans.last?.range.contains(column) != true {
                spans.append(DoubtfulWordSpan(range: column..<(column + 1), kind: kind, evidence: evidence))
            }
        }
        return .placed(spans, unplaced: unplaced)
    }

    /// Why the heard word at `index` is doubtful, the most specific reason first, or `nil` when it is not.
    private static func kind(
        of index: Int, in heard: [Draft.Word], landed: [Int?], written: [Substring]
    ) -> DoubtKind? {
        let word = heard[index]
        if word.settled { return .overridden }
        guard DoubtPolicy.reason(text: word.text, confidence: word.confidence) != nil
        else { return nil }
        if let column = landed[index] {
            let shown = SpokenToken(written[column]).core
            if shown.contains(where: \.isNumber) { return .numberLike }
            if Self.isNameLike(shown, at: column, in: written) { return .nameLike }
        }
        let neighbours = [index - 1, index + 1].filter(heard.indices.contains)
        if neighbours.contains(where: { negators.contains(SpokenToken(heard[$0].text).scoreKey) }) {
            return .negatorAdjacent
        }
        return DoubtPolicy.isHeardSurely(word.confidence) ? .soundAlikeClass : .lowScore
    }

    /// Whether a written word is capitalised where a sentence does not begin, which is how a name reads.
    private static func isNameLike(_ shown: Substring, at column: Int, in written: [Substring]) -> Bool {
        guard column > 0, let first = shown.first, first.isUppercase,
            shown.dropFirst().contains(where: \.isLowercase)
        else { return false }
        return !SpokenToken(written[column - 1]).trailing.contains { ".?!".contains($0) }
    }

    /// Where each heard word landed among the written words: a match or a one-for-one rewrite lands, a dropped word does not.
    private static func landing(_ heard: [String], on written: [Substring]) -> [Int?] {
        let alignment = WordErrorRate.measure(
            reference: heard.map { SpokenToken($0).scoreKey },
            hypothesis: written.map { SpokenToken($0).scoreKey }
        ).alignment
        var landed: [Int?] = []
        var column = 0
        for operation in alignment {
            switch operation {
            case .match, .substitution:
                landed.append(column)
                column += 1
            case .deletion: landed.append(nil)
            case .insertion: column += 1
            }
        }
        return landed
    }
}
