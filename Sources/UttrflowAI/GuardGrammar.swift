import UttrflowCore
import UttrflowDictionary

// The guard's grammar checks: removals restored, invention, placement, case and negation.
extension MeaningPreservationGuard {
    /// A repair may change a word's form, never which content words are there, either way round, or the order they came in. See `Docs/cleanup.md`.
    static func grammarVerdict(
        kept: String, rewritten: String, allowing doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        let alignment = RewriteAlignment(kept: kept, rewritten: rewritten)
        return grammarVerdict(
            alignment, excusing: readingVerdict(doubtful, in: alignment).excused, echoed: echoed,
            allowing: doubtful)
    }

    /// The same check over an alignment already in hand, each word judged against what stands in its own place.
    static func grammarVerdict(
        _ alignment: RewriteAlignment, excusing excused: Set<Int>, echoed: String,
        allowing doubtful: [DoubtfulSpan], restoring restored: [GrammarToken] = [],
        policy: GrammarPolicy = .repair, styled: Set<String> = []
    ) -> GuardVerdict {
        if policy == .asSpoken, case .rejected(let reason, let kind) = asSpokenFormVerdict(alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        let keptTokens = alignment.kept
        let rewrittenTokens = alignment.rewritten
        let echoTokens = grammarTokens(echoed)
        // The echo the caret pass took back opened the model's answer, so its words count as survivors ahead of the rest.
        let written = (echoTokens + rewrittenTokens).filter(\.isPlain)
        let romanisedHindiContext = hasRomanisedHindiContext(keptTokens + rewrittenTokens + echoTokens)
        // A number spoken over several words answers to the one numeral the rewrite wrote for it.
        let composed = composedNumbers(keptTokens, in: Set(written.map(\.matching)))
        let removable = removableSpeechArtifacts(in: alignment)
        // A symbol named aloud and written as its mark, or a list prefix given way to its label, is accounted for.
        let marked = writtenAsMarks(keptTokens, in: echoed + "\n" + alignment.rewrittenText)
        // A destination that repairs grammar lets a kept word change its form; one that keeps it as spoken refused that above.
        let repairs = policy == .repair
        let carried = keptTokens.indices.filter { index in
            let token = keptTokens[index]
            return token.isPlain
                && (isContent(token) || FunctionWords.isMeaningBearing(token.lookup)
                    || isAcronymLetter(at: index, in: keptTokens))
                && !composed.contains(index) && !excused.contains(index) && !removable.contains(index)
                && !marked.contains(index)
        }
        if case .rejected(let reason, let kind) = survivalVerdict(
            carried.map { keptTokens[$0] }, in: written,
            allowingRomanisedHindiSpellings: romanisedHindiContext, allowingFormRepairs: repairs)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = placeVerdict(
            Set(carried), in: alignment, echo: echoTokens,
            allowingRomanisedHindiSpellings: romanisedHindiContext, allowingFormRepairs: repairs)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = casePreservationVerdict(alignment, styling: styled) {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = apostropheVerdict(alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        let dropped = negators(in: keptTokens) - negators(in: rewrittenTokens + echoTokens)
        if dropped > 0 {
            return .rejected(reason: "the rewrite dropped a negation", kind: .negationDropped)
        }
        if case .rejected(let reason, let kind) = negationPlacementVerdict(
            alignment, echo: echoTokens, removable: removable, allowingFormRepairs: repairs)
        {
            return .rejected(reason: reason, kind: kind)
        }
        // Last of the order checks, so a moved content word or negation is refused by the check that can name it.
        if case .rejected(let reason, let kind) = wordOrderVerdict(
            kept: keptTokens, written: written, allowingFormRepairs: repairs)
        {
            return .rejected(reason: reason, kind: kind)
        }
        // The echo is the field's text before the caret, so it is an origin a negation may come from, never a total.
        let added =
            negators(in: rewrittenTokens) - negators(in: keptTokens) - negators(in: echoTokens + restored)
        if added > 0 {
            return .rejected(reason: "the rewrite added a negation", kind: .negationAdded)
        }
        // A line break ends a line as a stop ends a sentence, so a list or notes laid out by line are not one run-on.
        let long = alignment.rewrittenText.split(whereSeparator: \.isNewline)
            .contains { words(in: String($0)) > wordsPerSentenceEnd }
        if long, sentenceEnds(alignment.rewrittenText) == 0 {
            return .rejected(reason: "the rewrite of a long text ends no sentence", kind: .unpunctuated)
        }
        let churn = alignedFunctionWordChurn(alignment)
        if churn > 3 * churnSentences(alignment) {
            return .rejected(reason: "the rewrite changed \(churn) small words", kind: .smallWordChurn)
        }
        // A word put back where a pass took it without the grant to is the speaker's, not the model's.
        return inventionVerdict(
            alignment, echo: echoTokens + restored, allowing: doubtful,
            allowingRomanisedHindiSpellings: romanisedHindiContext, allowingFormRepairs: repairs)
    }

    /// Refuses a kept word whose regular or listed irregular form changed in an as-spoken destination.
    private static func asSpokenFormVerdict(_ alignment: RewriteAlignment) -> GuardVerdict {
        for change in alignment.changes {
            for kept in alignment.kept[change.kept] {
                for rewritten in alignment.rewritten[change.rewritten]
                where kept.matching != rewritten.matching
                    && WordForms.sameForm(kept.matching, rewritten.matching)
                {
                    return .rejected(reason: "the rewrite changed a kept word's form", kind: .lostWord)
                }
            }
        }
        return .accepted
    }

    /// Finds words a cleanup pass could remove or turn into punctuation in a changed run.
    private static func removableSpeechArtifacts(in alignment: RewriteAlignment) -> Set<Int> {
        let kept = alignment.kept
        var removable = Set(kept.indices.filter { FillersPass.fillerWords.contains(kept[$0].matching) })
        let keptGaps = grammarTokenGaps(alignment.keptText)
        let rewrittenGaps = grammarTokenGaps(alignment.rewrittenText)
        guard keptGaps.count == kept.count + 1, rewrittenGaps.count == alignment.rewritten.count + 1
        else { return removable }
        // The draft the passes read, so a name the spoken-punctuation pass judged a mention is judged the same here.
        let draft = Draft(
            words: kept.indices.map { Draft.Word(kept[$0].text + keptGaps[$0 + 1], evidence: .unknown) })
        for mark in Set(SpokenCommands.marks.map(\.text)) {
            guard let character = mark.first, String(character) == mark else { continue }
            let names = SpokenCommands.marks.filter { $0.text == mark }
                .sorted { $0.words.count > $1.words.count }
            for change in alignment.changes {
                var remaining =
                    addedMarks(character, in: change, keptGaps: keptGaps, rewrittenGaps: rewrittenGaps)
                for command in names where remaining > 0 {
                    let name = command.words
                    guard name.count <= change.kept.count else { continue }
                    for start in change.kept where remaining > 0 {
                        let end = start + name.count
                        guard end <= change.kept.upperBound,
                            zip(name, kept[start..<end]).allSatisfy({ $0 == $1.matching }),
                            !removable.contains(where: { start..<end ~= $0 }),
                            // A name whose whole run the rewrite replaced with its mark, between two words, is that mark.
                            start == change.kept.lowerBound && end == change.kept.upperBound
                                && change.rewritten.lowerBound < rewrittenGaps.count - 1
                                && rewrittenGaps[change.rewritten.lowerBound].contains(character)
                                || !MentionGuard.isMentioned(
                                    at: start, spanning: name.count, in: Array(kept.indices), of: draft,
                                    reach: MentionGuard.phraseReach, kind: command.placement)
                        else { continue }
                        removable.formUnion(start..<end)
                        remaining -= 1
                    }
                }
            }
        }
        return removable
    }

    /// Marks a changed run's rewrite has beyond its draft, counted at its edges and between its words, the text's closing stop only for a name that closed the draft.
    private static func addedMarks(
        _ character: Character, in change: RewriteAlignment.Change, keptGaps: [String],
        rewrittenGaps: [String]
    ) -> Int {
        let count: (ArraySlice<String>) -> Int = { $0.joined().filter { $0 == character }.count }
        var written = count(rewrittenGaps[change.rewritten.lowerBound...change.rewritten.upperBound])
        // A closing mark at the very end answers a spoken name only when that name ended the draft too.
        if change.rewritten.upperBound == rewrittenGaps.count - 1,
            change.kept.upperBound < keptGaps.count - 1, ".!?".contains(character),
            rewrittenGaps[rewrittenGaps.count - 1].contains(character)
        {
            written -= 1
        }
        return written - count(keptGaps[change.kept.lowerBound...change.kept.upperBound])
    }

    /// Refuses a carried word that a changed run lost, judging it only against the words standing in that run's place.
    static func placeVerdict(
        _ carried: Set<Int>, in alignment: RewriteAlignment, echo: [GrammarToken],
        allowingRomanisedHindiSpellings: Bool = false, allowingFormRepairs: Bool = false
    ) -> GuardVerdict {
        for change in alignment.changes {
            let here = (alignment.rewritten[change.rewritten] + echo).filter(\.isPlain)
            let tokens = change.kept.compactMap { index in
                carried.contains(index) ? alignment.kept[index] : nil
            }
            if case .rejected(let reason, let kind) = survivalVerdict(
                tokens, in: here, allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings,
                allowingFormRepairs: allowingFormRepairs)
            {
                return .rejected(reason: reason, kind: kind)
            }
        }
        return .accepted
    }

    /// Refuses a content word the model brought in, an addition being the same fault as a loss read the other way.
    static func inventionVerdict(
        kept: [GrammarToken], rewritten: [GrammarToken], echo: [GrammarToken],
        allowing doubtful: [DoubtfulSpan]
    ) -> GuardVerdict {
        inventionVerdict(
            RewriteAlignment(
                kept: kept.map(\.text).joined(separator: " "),
                rewritten: rewritten.map(\.text).joined(separator: " ")),
            echo: echo, allowing: doubtful)
    }

    /// Refuses a content or meaning-bearing word with no origin in the same aligned run or an offered reading for it.
    static func inventionVerdict(
        _ alignment: RewriteAlignment, echo: [GrammarToken], allowing doubtful: [DoubtfulSpan],
        allowingRomanisedHindiSpellings: Bool? = nil, allowingFormRepairs: Bool = false
    ) -> GuardVerdict {
        // A draft the checks cannot read romanises into words with no counterpart here, so the base checks keep it.
        guard alignment.kept.allSatisfy(\.isPlain) else { return .accepted }
        let romanisedHindiContext =
            allowingRomanisedHindiSpellings
            ?? hasRomanisedHindiContext(alignment.kept + alignment.rewritten + echo)
        let origins = (alignment.kept + echo).filter(\.isPlain)
        let originIndex = WordOccurrenceIndex(origins)
        var usedOrigins = Set<Int>()
        var usedReadings = Set<Int>()
        for index in alignment.rewritten.indices
        where alignment.rewritten[index].isPlain
            && (isContent(alignment.rewritten[index])
                || FunctionWords.isMeaningBearing(alignment.rewritten[index].lookup))
        {
            let token = alignment.rewritten[index]
            if let origins = originIndex.matchingOrigins(
                token, allowingRomanisedHindiSpellings: romanisedHindiContext,
                allowingFormRepairs: allowingFormRepairs, excluding: usedOrigins)
            {
                usedOrigins.formUnion(origins)
                continue
            }
            let offeredReading = doubtful.enumerated().first { entry in
                let (spanIndex, span) = entry
                guard !usedReadings.contains(spanIndex) else { return false }
                return alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard)).enumerated()
                    .filter { span.isDoubted(at: $0.offset) }.map(\.element).contains { source in
                        alignment.changes.contains { change in
                            change.kept.overlaps(source) && change.rewritten.contains(index)
                                && span.candidates.contains {
                                    survivesCandidate(token, candidate: $0.spelling)
                                }
                        }
                    }
            }
            if let offeredReading {
                usedReadings.insert(offeredReading.offset)
            } else {
                return .rejected(reason: "the rewrite invented '\(token.text)'", kind: .inventedWord)
            }
        }
        return .accepted
    }

    /// Matches one offered spelling without treating a substring or unrelated occurrence as provenance.
    private static func survivesCandidate(_ token: GrammarToken, candidate: String) -> Bool {
        let parts = grammarTokens(candidate)
        return parts.count == 1 && survives(parts[0].matching, as: token)
    }

    /// Counts changed function words inside aligned runs, so a swap cannot cancel against another sentence.
    static func alignedFunctionWordChurn(_ alignment: RewriteAlignment) -> Int {
        alignment.changes.reduce(0) { total, change in
            // A word in another script is read as its romanisation, the spelling the rewrite writes it in.
            let before = alignment.kept[change.kept]
                .flatMap { $0.isPlain ? [$0] : grammarTokens(Romaniser.romanised($0.text)) }
                .filter { $0.isPlain && !isContent($0) }
            let after = alignment.rewritten[change.rewritten].filter { $0.isPlain && !isContent($0) }
            return total + functionWordChurn(before, after)
        }
    }

    /// Refuses to erase capitals that distinguish a mid-sentence name or acronym from an ordinary word, except capitals a pass styled onto lowercase speech.
    static func casePreservationVerdict(
        _ alignment: RewriteAlignment, styling styled: Set<String> = []
    ) -> GuardVerdict {
        let capitalised = alignment.kept.filter {
            !$0.startsSentence && $0.text.contains(where: \.isUppercase) && !styled.contains($0.text)
        }
        var required: [String: [String: Int]] = [:]
        for token in capitalised {
            required[token.matching, default: [:]][token.text, default: 0] += 1
        }
        var written: [String: [String: Int]] = [:]
        for token in alignment.rewritten {
            written[token.matching, default: [:]][token.text, default: 0] += 1
        }
        // Walked in text order, so the refusal names the first word the rewrite lowered on every run.
        for token in capitalised {
            let spellings = required[token.matching, default: [:]]
            let rewrites = written[token.matching, default: [:]]
            guard rewrites.values.reduce(0, +) >= spellings.values.reduce(0, +),
                rewrites[token.text, default: 0] < spellings[token.text, default: 0]
            else { continue }
            return .rejected(
                reason: "the rewrite changed the capitalization of '\(token.text)'", kind: .lostWord)
        }
        return .accepted
    }

    /// Spellings whose capitals a pass wrote over words the recogniser heard in lowercase, such as "URL" for "url"; acronym style, not the speaker's.
    static func styledCapitals(in draft: Draft) -> Set<String> {
        Set(
            draft.words
                .filter { $0.isPresent && !$0.heard.isEmpty && !$0.heard.contains(where: \.isUppercase) }
                .flatMap { grammarTokens($0.text) }
                .map(\.text)
                // Only acronym styling: a name's capital stays protected, and so does "I".
                .filter {
                    $0.count > 1 && $0.contains(where: \.isUppercase) && !$0.contains(where: \.isLowercase)
                })
    }

    /// Refuses a kept word written again without its apostrophe, which turns "it's" into "its" and "don't" into a misspelling.
    static func apostropheVerdict(_ alignment: RewriteAlignment) -> GuardVerdict {
        for change in alignment.changes {
            for kept in alignment.kept[change.kept] where kept.isPlain && kept.matching.contains("'") {
                let bare = kept.matching.replacingOccurrences(of: "'", with: "")
                if alignment.rewritten[change.rewritten].contains(where: { $0.matching == bare }) {
                    return .rejected(
                        reason: "the rewrite dropped the apostrophe in '\(kept.text)'", kind: .lostWord)
                }
            }
        }
        return .accepted
    }

    /// Refuses a negator that moved to a different content-word neighbourhood, while allowing contractions and punctuation changes.
    static func negationPlacementVerdict(
        _ alignment: RewriteAlignment, echo: [GrammarToken], removable: Set<Int> = [],
        allowingFormRepairs: Bool = false
    ) -> GuardVerdict {
        let kept = alignment.kept
        let rewritten = alignment.rewritten
        // Non-Latin negations are commonly romanised by the cleanup model; their existing count check remains authoritative.
        let keptNegations = kept.indices.filter {
            kept[$0].isPlain && isNegation(kept[$0].matching)
        }
        guard !keptNegations.isEmpty else { return .accepted }
        let written = rewritten + echo
        let writtenNegations = written.indices.filter {
            written[$0].isPlain && isNegation(written[$0].matching)
        }
        guard keptNegations.count == writtenNegations.count else { return .accepted }

        // A word a pass could take out, as a filler or a mark's name, locates nothing the rewrite must keep beside it.
        let keptPlaces = negationPlaces(in: kept, skipping: removable)
        let rewrittenPlaces = negationPlaces(in: rewritten)
        guard keptPlaces.count == rewrittenPlaces.count else { return .accepted }
        guard
            zip(keptPlaces, rewrittenPlaces).allSatisfy({ original, answer in
                original.clause == answer.clause
                    && sameAnchor(original.before, answer.before, allowingFormRepairs: allowingFormRepairs)
                    && sameAnchor(original.after, answer.after, allowingFormRepairs: allowingFormRepairs)
            })
        else {
            return .rejected(reason: "the rewrite moved a negation", kind: .negationMoved)
        }
        return .accepted
    }

    /// The clause and its nearest content words around one negation.
    private struct NegationPlace {
        let clause: Int
        let before: GrammarToken?
        let after: GrammarToken?
    }

    /// Whether a neighbouring word survived as the same word, another form of it where repairs are allowed, or inside an identifier.
    private static func sameAnchor(
        _ first: GrammarToken?, _ second: GrammarToken?, allowingFormRepairs: Bool
    ) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case (let first?, let second?):
            return survives(first.matching, as: second, allowingFormRepairs: allowingFormRepairs)
                || survives(second.matching, as: first, allowingFormRepairs: allowingFormRepairs)
        default: return false
        }
    }

    /// Coordinators bound clauses; the content words beside a negation locate its scope.
    private static func negationPlaces(
        in tokens: [GrammarToken], skipping removable: Set<Int> = []
    ) -> [NegationPlace] {
        let anchors: (Int) -> Bool = { isAnchor(tokens[$0]) && !removable.contains($0) }
        var clause = 0
        var clauseStart = 0
        var result: [NegationPlace] = []
        for index in tokens.indices where tokens[index].isPlain {
            let token = tokens[index]
            if ["but", "and", "or"].contains(token.matching) {
                clause += 1
                clauseStart = index
            }
            if isNegation(token.matching) {
                let clauseEnd =
                    tokens[(index + 1)...].firstIndex {
                        ["but", "and", "or"].contains($0.matching)
                    } ?? tokens.endIndex
                let before = (clauseStart..<index).last(where: anchors).map { tokens[$0] }
                let after = ((index + 1)..<clauseEnd).first(where: anchors).map { tokens[$0] }
                result.append(NegationPlace(clause: clause, before: before, after: after))
            }
        }
        return result
    }

    /// Negations and function words do not identify the proposition a negation belongs to.
    private static func isAnchor(_ token: GrammarToken) -> Bool {
        token.isPlain && !isNegation(token.matching) && !FunctionWords.holds(token.lookup)
    }
}
