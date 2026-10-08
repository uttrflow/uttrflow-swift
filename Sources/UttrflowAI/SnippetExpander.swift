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
            // A trigger that says a command, imported or saved before the command existed, never fires: the command wins.
            guard snippet.collidingCommand == nil else { continue }
            usable.append(Candidate(snippet: snippet, words: words))
        }
        candidates = usable.sorted(by: Candidate.outranks)
    }

    /// Replaces every trigger the transcript says, returning the new text and every snippet that fired.
    public func expand(_ transcript: String) -> SnippetExpansion {
        // Most people have no snippets, so the transcript is not tokenised to discover that.
        guard !candidates.isEmpty else { return .unchanged(transcript) }

        // Normalised once, so the quoting check does not re-tidy the transcript per snippet.
        let spoken = WordTokens.words(transcript, .comparison).map { $0.lowercased() }
        let eligible = candidates.filter { !Self.contains($0.quoted, in: spoken) }

        let runs = WordTokens.tokens(transcript, .comparison)
        var applied: [AppliedSnippet] = []
        var text = ""
        var caret: Int?
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
            let prefix = transcript[copiedUpTo..<span.lowerBound]
            let sentenceStart =
                prefix.reversed().first(where: { !$0.isWhitespace }).map {
                    ".!?\n\r".contains($0)
                } ?? true
            let body = hit.body
            var written = Self.expansion(body.text, sentenceStart: sentenceStart)
            if caret == nil, let marked = body.caret {
                // Capitalising can change the first letter's length, which shifts a caret that sits after it.
                let shift = marked == 0 ? 0 : written.utf16.count - body.text.utf16.count
                caret = text.utf16.count + marked + shift
            }
            var after = span.upperBound
            if let next = transcript[after...].first,
                let terminal = Self.terminalMark(in: body.text),
                Self.sameTerminalClass(next, terminal)
            {
                // A full stop after the trigger is the tidier's; any other mark is the speaker's and replaces the expansion's.
                if next != ".", let index = written.lastIndex(where: { !$0.isWhitespace }) {
                    written.remove(at: index)
                } else {
                    after = transcript.index(after: after)
                }
            }
            text += written
            applied.append(
                AppliedSnippet(
                    snippetID: hit.snippet.id, matched: String(transcript[span]),
                    expansion: body.text))
            copiedUpTo = after
            position += hit.words.count
        }
        text += transcript[copiedUpTo...]
        return SnippetExpansion(original: transcript, text: text, applied: applied, caret: caret)
    }

    /// Carries sentence-start casing into a replacement while leaving every other saved character alone.
    private static func expansion(_ expansion: String, sentenceStart: Bool) -> String {
        let leading = String(expansion.prefix(while: { !$0.isWhitespace }))
        guard sentenceStart, let first = expansion.first, first.isLetter, first.isLowercase,
            !FirstWordPass.keepsCapital(leading)
        else {
            return expansion
        }
        return WordShape.capitalised(expansion)
    }

    /// The last punctuation mark that can be duplicated by tidying immediately after a trigger.
    private static func terminalMark(in expansion: String) -> Character? {
        guard let last = expansion.last(where: { !$0.isWhitespace }), ".!?;:,".contains(last)
        else { return nil }
        return last
    }

    /// Whether an adjacent tidy mark is already represented by the expansion's ending punctuation class.
    private static func sameTerminalClass(_ first: Character, _ second: Character) -> Bool {
        WordShape.clauseMarks.contains(first) && WordShape.clauseMarks.contains(second)
    }

    // MARK: - Whether a trigger really was said

    /// Whether every expansion word appears as a consecutive word run in the transcript.
    private static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard phrase.count <= words.count else { return false }
        return words.indices.contains { start in
            start + phrase.count <= words.count
                && Array(words[start..<(start + phrase.count)]) == phrase
        }
    }

    /// Whether the trigger's words sit at `position` as one phrase, with neither end glued to a neighbour.
    private func fits(
        _ candidate: Candidate, at position: Int, of runs: [WordToken], in transcript: String
    ) -> Bool {
        let length = candidate.words.count
        guard position + length <= runs.count else { return false }

        for (run, word) in zip(runs[position..<(position + length)], candidate.words)
        where run.text.lowercased() != word {
            return false
        }

        for offset in 1..<length {
            let between = Self.gap(runs[position + offset - 1], runs[position + offset], transcript)
            if !Self.separatesWords(between) && between != candidate.marks[offset - 1] {
                return false
            }
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
        _ first: WordToken, _ second: WordToken, _ transcript: String
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
        /// The expansion as written, markers removed.
        let body: SnippetBody
        /// The trigger's words, lower-cased.
        let words: [String]
        /// What the trigger spells between its words, such as "-" or ": ", which the transcript may repeat exactly.
        let marks: [Substring]
        /// The expansion's lower-cased word runs, used to recognize a quotation as a phrase.
        let quoted: [String]
        /// The trigger rejoined; breaks ties so two equally long triggers cannot swap places between runs.
        let key: String

        /// Precomputes the quoting text and the tie-break key for one snippet.
        init(snippet: Snippet, words: [String]) {
            self.snippet = snippet
            self.words = words
            body = snippet.body
            let runs = WordTokens.tokens(snippet.trigger, .comparison)
            marks = zip(runs, runs.dropFirst()).map { first, second in
                snippet.trigger[first.range.upperBound..<second.range.lowerBound]
            }
            quoted = WordTokens.words(body.text, .comparison).map { $0.lowercased() }
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
