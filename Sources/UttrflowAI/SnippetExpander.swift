public import UttrflowCore
/// Finds spoken triggers in a transcript and puts the stored text in their place.
///
/// Deterministic and pure — no clock, no disk, no model. It runs on the dictation path
/// between the tidier and the insertion, where anything that can be slow or can vary
/// between two runs of the same words would be felt immediately.
///
/// The whole design is one left-to-right pass over the *original* transcript, with the
/// expansions written into a separate string that is never read back. That single
/// choice is what makes the depth cap of one free rather than something to enforce: a
/// snippet whose text contains its own trigger cannot re-enter, because nothing ever
/// looks at what was written out. A recursive design would have needed a counter, and a
/// counter is a thing that can be wrong.
public struct SnippetExpander: Sendable {
    /// The snippets that could fire, longest trigger first.
    ///
    /// Sorted once here rather than at each position in the transcript, because the
    /// order is a property of the snippets and not of what was said. Taking the first
    /// candidate that fits at a position is then exactly "the longest trigger wins".
    private let candidates: [Candidate]

    /// - Parameter snippets: The user's snippets, in any order.
    public init(snippets: [Snippet]) {
        var claimed: Set<[String]> = []
        var usable: [Candidate] = []
        for snippet in snippets where snippet.isUsable {
            let words = snippet.triggerWords
            // Two snippets with one trigger is a question with no right answer, and the
            // store refuses to create it. Should one arrive anyway — a hand-edited file
            // — the first wins, so the matcher stays a function of its input.
            guard claimed.insert(words).inserted else { continue }
            usable.append(Candidate(snippet: snippet, words: words))
        }
        candidates = usable.sorted(by: Candidate.outranks)
    }

    /// Expands every trigger the transcript actually says.
    ///
    /// - Parameter transcript: The tidied text, as it would otherwise be inserted.
    /// - Returns: The text to insert, and a record of every snippet that fired.
    public func expand(_ transcript: String) -> SnippetExpansion {
        // Most people have no snippets, and tokenising a paragraph to discover that
        // would be a cost the feature imposes on everyone who does not use it.
        guard !candidates.isEmpty else { return .unchanged(transcript) }

        // Normalised once. The alternative — tidying the transcript again inside each
        // snippet's quoting check — makes the pass cost grow with the snippet count for
        // no gain, since the answer is the same string every time.
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

    /// Whether `candidate`'s trigger occupies the word runs starting at `position`.
    ///
    /// Three questions, and the last two are the ones that stop a near-miss. The words
    /// have to be the same words; they have to be spoken as one phrase rather than
    /// collected across the end of a sentence or read out of one written word; and
    /// neither end may be glued to a word outside the match, which is what keeps
    /// "address" out of "address's" once the apostrophe has split it into two runs.
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

    /// Everything written between two word runs. Never empty: runs are maximal, so
    /// there is at least one character that is neither a letter nor a digit between any
    /// two of them.
    private static func gap(
        _ first: SnippetWordRun, _ second: SnippetWordRun, _ transcript: String
    ) -> Substring {
        transcript[first.range.upperBound..<second.range.lowerBound]
    }

    /// Whether a gap is the ordinary space between two words of one spoken phrase.
    ///
    /// The two ways it can fail are the two ways a trigger gets found where it was not
    /// said. It can be glue, in which case the words either side are halves of one
    /// written word — "sign_off" is not somebody saying "sign off". Or it can end a
    /// sentence, in which case the trigger has been assembled out of two different
    /// thoughts — "Please sign. Off we go" does not say "sign off" either.
    private static func separatesWords(_ gap: Substring) -> Bool {
        !joinsWords(gap) && !gap.contains(where: endsAPhrase)
    }

    /// Punctuation after which the next word belongs to a different thought.
    ///
    /// Commas and brackets are deliberately absent: a speaker pausing in the middle of
    /// their own trigger, and a recogniser writing that pause down, is exactly the case
    /// punctuation tolerance exists for.
    private static func endsAPhrase(_ character: Character) -> Bool {
        character.isNewline || ".!?;:".contains(character)
    }

    /// Characters that, with no space anywhere near them, make two runs one written
    /// word: hyphens, underscores, apostrophes, full stops in a domain, slashes, and
    /// the at sign in an address.
    ///
    /// Spelt out rather than "anything that is not a space", so that an unspaced em
    /// dash — which separates clauses and joins nothing — does not silently stop a
    /// legitimate trigger from firing.
    private static let wordJoiners: Set<Character> = ["-", "_", "'", "\u{2019}", ".", "/", "@"]

    /// Whether the runs either side of this gap are two halves of one written word.
    private static func joinsWords(_ gap: Substring) -> Bool {
        gap.allSatisfy(wordJoiners.contains)
    }
}

// MARK: - A snippet, prepared for matching

extension SnippetExpander {
    /// One snippet with everything the pass needs precomputed.
    ///
    /// Built in the initialiser and not per dictation, because none of it depends on
    /// what was said and all of it would otherwise be redone on the hot path.
    private struct Candidate: Sendable {
        let snippet: Snippet
        /// The trigger's words, lower-cased.
        let words: [String]
        /// The expansion in the same shape a transcript is reduced to, so that "is the
        /// user already quoting this?" is one substring search.
        let quoted: String
        /// The trigger rejoined. Used only to break ties, and only so that two
        /// equally long triggers cannot swap places between runs.
        let key: String

        init(snippet: Snippet, words: [String]) {
            self.snippet = snippet
            self.words = words
            quoted = TextTidy.collapseWhitespace(snippet.expansion).lowercased()
            key = words.joined(separator: " ")
        }

        /// A total order with the longest trigger at the front.
        ///
        /// Word count first, because "my work address" beating "my address" is about
        /// how much of the sentence a trigger claims and not how many letters it has.
        /// The rest is only there to make the order total: any two candidates compare
        /// the same way every time, so the same snippets and the same words always give
        /// the same expansion.
        static func outranks(_ first: Candidate, _ second: Candidate) -> Bool {
            if first.words.count != second.words.count {
                return first.words.count > second.words.count
            }
            if first.key.count != second.key.count { return first.key.count > second.key.count }
            return first.key < second.key
        }
    }
}
