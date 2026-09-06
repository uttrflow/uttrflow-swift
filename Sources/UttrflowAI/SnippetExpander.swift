public import UttrflowCore
/// Replaces spoken triggers with snippet text in one pass over the original, so an expansion never re-enters.
public struct SnippetExpander: Sendable {
    /// The usable snippets, longest trigger first, so the first candidate that fits at a position wins.
    private let candidates: [Candidate]

    /// Keeps the usable snippets from `snippets`, in any order; of two sharing a trigger, the first wins.
    public init(snippets: [Snippet]) {
        var claimed: Set<[String]> = []
        var usable: [Candidate] = []
        for snippet in snippets where snippet.isUsable {
            let words = snippet.triggerWords
            // The store refuses two snippets with one trigger; a hand-edited file may hold them, first wins.
            guard claimed.insert(words).inserted else { continue }
            usable.append(Candidate(snippet: snippet, words: words))
        }
        candidates = usable.sorted(by: Candidate.outranks)
    }

    /// Replaces every trigger the transcript says, returning the new text and every snippet that fired.
    public func expand(_ transcript: String) -> SnippetExpansion {
        // Most people have no snippets, so the transcript is not tokenised to discover that.
        guard !candidates.isEmpty else { return .unchanged(transcript) }

        // Normalised once, so the quoting check does not re-tidy the transcript per snippet.
        let spoken = TextTidy.collapseWhitespace(transcript).lowercased()
        let eligible = candidates.filter { !spoken.contains($0.quoted) }

        let runs = transcript.snippetWordRuns()
        var applied: [AppliedSnippet] = []
        var text = ""
        var copiedUpTo = transcript.startIndex
        var position = 0
        while position < runs.count {
            guard let hit = eligible.first(where: { fits($0, at: position, of: runs, in: transcript) })
            else {
                position += 1
                continue
            }
            let last = position + hit.words.count - 1
            let span = runs[position].range.lowerBound..<runs[last].range.upperBound
            text += transcript[copiedUpTo..<span.lowerBound]
            text += hit.snippet.expansion
            applied.append(
                AppliedSnippet(
                    snippetID: hit.snippet.id, matched: String(transcript[span]),
                    expansion: hit.snippet.expansion))
            copiedUpTo = span.upperBound
            position += hit.words.count
        }
        text += transcript[copiedUpTo...]
        return SnippetExpansion(original: transcript, text: text, applied: applied)
    }

    // MARK: - Whether a trigger really was said

    /// Whether the trigger's words sit at `position` as one phrase, with neither end glued to a neighbour.
    private func fits(
        _ candidate: Candidate, at position: Int, of runs: [SnippetWordRun], in transcript: String
    ) -> Bool {
        let length = candidate.words.count
        guard position + length <= runs.count else { return false }

        for (run, word) in zip(runs[position..<(position + length)], candidate.words)
        where run.text.lowercased() != word {
            return false
        }

        for offset in 1..<length {
            let between = Self.gap(runs[position + offset - 1], runs[position + offset], transcript)
            if !Self.separatesWords(between) { return false }
        }

        if position > 0, Self.joinsWords(Self.gap(runs[position - 1], runs[position], transcript)) {
            return false
        }
        let after = position + length
        if after < runs.count, Self.joinsWords(Self.gap(runs[after - 1], runs[after], transcript)) {
            return false
        }
        return true
    }

    /// The text between two word runs; never empty, because runs are maximal.
    private static func gap(
        _ first: SnippetWordRun, _ second: SnippetWordRun, _ transcript: String
    ) -> Substring {
        transcript[first.range.upperBound..<second.range.lowerBound]
    }

    /// Whether a gap is plain spacing inside one phrase: not glue ("sign_off") and not a sentence end.
    private static func separatesWords(_ gap: Substring) -> Bool {
        !joinsWords(gap) && !gap.contains(where: endsAPhrase)
    }

    /// Punctuation after which the next word starts a new thought; commas and brackets are tolerated pauses.
    private static func endsAPhrase(_ character: Character) -> Bool {
        character.isNewline || ".!?;:".contains(character)
    }

    /// Characters that make two runs one written word; listed, so an unspaced em dash still separates.
    private static let wordJoiners: Set<Character> = ["-", "_", "'", "\u{2019}", ".", "/", "@"]

    /// Whether the runs either side of this gap are two halves of one written word.
    private static func joinsWords(_ gap: Substring) -> Bool {
        gap.allSatisfy(wordJoiners.contains)
    }
}

// MARK: - A snippet, prepared for matching

extension SnippetExpander {
    /// One snippet with everything the pass needs precomputed once, off the hot path.
    private struct Candidate: Sendable {
        /// The snippet this candidate stands for.
        let snippet: Snippet
        /// The trigger's words, lower-cased.
        let words: [String]
        /// The expansion tidied like a transcript, so "is the user quoting this?" is one substring search.
        let quoted: String
        /// The trigger rejoined; breaks ties so two equally long triggers cannot swap places between runs.
        let key: String

        /// Precomputes the quoting text and the tie-break key for one snippet.
        init(snippet: Snippet, words: [String]) {
            self.snippet = snippet
            self.words = words
            quoted = TextTidy.collapseWhitespace(snippet.expansion).lowercased()
            key = words.joined(separator: " ")
        }

        /// A total order: most words first, then longest text, then alphabetical, so results never vary.
        static func outranks(_ first: Candidate, _ second: Candidate) -> Bool {
            if first.words.count != second.words.count {
                return first.words.count > second.words.count
            }
            if first.key.count != second.key.count { return first.key.count > second.key.count }
            return first.key < second.key
        }
    }
}
