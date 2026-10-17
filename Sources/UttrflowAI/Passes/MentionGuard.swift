import NaturalLanguage
public import UttrflowCore

/// Words that mean the word after them is being talked about rather than dictated.
public enum MentionGuard {
    /// Whether the spoken layout phrase at live `position` names the thing rather than asking for it.
    public static func namesLayout(at position: Int, spanning length: Int, in draft: Draft) -> Bool {
        isMentioned(at: position, spanning: length, in: draft.presentIndices, of: draft, reach: phraseReach)
    }

    /// Whether a prose casing phrase names the style rather than asking for it: "the all caps rule", "in all caps".
    static func namesCasing(at position: Int, spanning length: Int, in live: [Int], of draft: Draft) -> Bool {
        // A casing phrase goes on the words after it, as an opening mark does.
        if isMentioned(
            at: position, spanning: length, in: live, of: draft, reach: phraseReach, kind: .opening)
        {
            return true
        }
        let words = live.map { draft.shape(at: $0).key }
        if position > 0, LexicalClass.tag(ofWordAt: position - 1, in: words) == .preposition { return true }
        // A form of "be" after the phrase makes it the subject of a sentence about the style.
        let next = position + length
        return next < live.count && LexicalClass.lemma(ofWordAt: next, in: words) == "be"
    }

    /// Words whose object is always a spelling: "the word ah", "spell um".
    private static let namingWords: Set<String> = ["word", "letter", "sound", "spell"]
    /// Verbs that name a spelling only through a determiner, since a hesitation often follows them: "he said um".
    private static let namingVerbs: Set<String> = ["say", "said", "write", "type"]
    private static let finalPeriodCompoundModifiers: Set<String> = [
        "cooling", "following", "grace", "holding", "notice", "time", "trial", "victorian", "waiting",
    ]
    /// Units that name a period only when a number counts them: "a six month period", not "a nice day period".
    private static let countedPeriodUnits: Set<String> = ["day", "week", "month", "year"]
    /// Particles that name a period only after the -ing word they complete: "cooling off", not "the light off".
    private static let gerundPeriodParticles: Set<String> = ["off"]

    /// Whether a hesitation spelling is named by a naming noun, a naming verb and determiner, or an opening quote.
    static func namesToken(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let shape = draft.shape(at: live[position])
        if shape.prefix.contains(where: WordShape.openingQuotes.contains) { return true }
        guard position > 0 else { return false }
        let previous = draft.shape(at: live[position - 1]).key
        if namingWords.contains(previous) { return true }
        guard position > 1, phraseOpeners.contains(previous) else { return false }
        return namingVerbs.contains(draft.shape(at: live[position - 2]).key)
    }

    /// Verbs and naming nouns that name the mark or layout phrase which follows them.
    private static let mentionVerbs: Set<String> = [
        "type", "say", "make", "write", "use", "press", "phrase", "term", "symbol",
        "labelled", "labeled", "called", "named",
    ]

    /// Reporting verbs that name a closing or joining mark after them but introduce an opening quote.
    private static let reportingVerbs: Set<String> = ["said", "says"]

    /// Mark names that are also nouns a number or another noun may modify: "a waiting period", "the hundred metre dash".
    private static let nounHeads: Set<String> = ["period", "dash"]

    package static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "these", "those", "each",
        "every",
        "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
        "which", "whose",
    ]

    /// The ones a modifier may stand between and the mark; a verb takes its object with nothing in between.
    static let phraseOpeners: Set<String> = [
        "a", "an", "the", "with", "no", "this", "that", "these", "those", "each", "every", "one", "my",
        "your",
        "his",
        "her", "its", "their", "our", "another", "any", "some", "same", "which", "whose",
    ]

    /// How far back the word that opens a noun phrase may stand: "the hundred metre dash".
    static let phraseReach = 3

    /// The spoken names of marks and layout, which close the phrase an opener began rather than heading it.
    static let markNames: Set<String> = Set(
        SpokenCommands.marks.flatMap(\.words) + SpokenCommands.layout.flatMap(\.words))

    /// Whether the mark word at `position` is mentioned; `reach` is how far the phrase's own opener may stand.
    static func isMentioned(
        at position: Int, spanning length: Int, in live: [Int], of draft: Draft, reach: Int = 1,
        kind: SpokenMarkKind = .trailing, bridgedBy bridging: Set<String>? = nil,
        corroboratedByLayout: Bool = false
    ) -> Bool {
        // An opening mark goes on the word after it, so a text beginning with one is using it, not naming it.
        guard position > 0 else { return !kind.attachesAfter }
        if namesChordKey(at: position, in: live, of: draft) { return true }
        if coordinatesMarkNames(at: position, spanning: length, in: live, of: draft, kind: kind) { return true }
        if kind == .closing, isOpenQuotation(before: position, in: live, of: draft) { return false }
        let next = position + length
        if opensThePhrase(
            ending: position, reaching: reach, in: live, of: draft, bridgedBy: bridging,
            finalMark: kind == .trailing && next == live.count, opening: kind.attachesAfter,
            corroboratedByLayout: corroboratedByLayout,
            clauseFollows: opensClause(at: next, in: live, of: draft),
            predicateFollows: opensPredicate(at: next, in: live, of: draft)
        ) {
            return true
        }
        guard next < live.count, draft.shape(at: live[next]).key == "of" else { return false }
        // Only the words up to `of` can end the sentence first, so only they are read.
        guard !(position..<next).contains(where: { draft.shape(at: live[$0]).endsSentence }) else {
            return false
        }
        return !closesDashPair(at: position, in: live, of: draft)
    }

    /// Every punctuation mark that stands on the word before it or joins two words, as its name's words, filed under the word the name opens on.
    private static let markNamesByOpening: [String: [[String]]] = Dictionary(
        grouping: SpokenCommands.marks.filter { $0.placement == .trailing || $0.placement == .joining }
            .map(\.words).filter { !$0.isEmpty },
        by: { $0[0] })

    /// The words that join two names of marks into one list of marks.
    private static let coordinators: Set<String> = ["and", "or"]

    /// Whether the mark name at `position` is joined by "and" or "or" to another mark name, as a sentence lists the marks it is about.
    static func coordinatesMarkNames(
        at position: Int, spanning length: Int, in live: [Int], of draft: Draft, kind: SpokenMarkKind
    ) -> Bool {
        // A quotation or a bracket is opened and closed by names that a sentence legitimately joins with "and".
        guard kind == .trailing || kind == .joining else { return false }
        let next = position + length
        let last = draft.shape(at: live[next - 1])
        if !last.endsClause, next + 1 < live.count, coordinators.contains(draft.shape(at: live[next]).key),
            !draft.shape(at: live[next]).endsClause,
            (markNamesByOpening[draft.shape(at: live[next + 1]).key] ?? []).contains(where: {
                draft.spells($0, at: next + 1, in: live)
            })
        {
            return true
        }
        guard position >= 2, coordinators.contains(draft.shape(at: live[position - 1]).key),
            !draft.shape(at: live[position - 1]).endsClause,
            !draft.shape(at: live[position - 2]).endsClause
        else { return false }
        return markNamesByOpening.values.joined().contains { name in
            let start = position - 1 - name.count
            return start >= 0 && draft.spells(name, at: start, in: live)
        }
    }

    /// Verbs that press a key, so a mark name after the modifier keys they press is the chord's key.
    private static let keyVerbs: Set<String> = ["press", "hit", "tap", "hold"]

    /// The spoken names of the modifier keys a chord holds.
    private static let modifierNames = Set(HotkeyModifier.allCases.map(\.rawValue))

    /// Whether the mark name at `position` is the key of a chord a key verb presses: "press command comma".
    static func namesChordKey(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        var back = position - 1
        while back >= 0, modifierNames.contains(draft.shape(at: live[back]).key),
            !draft.shape(at: live[back]).endsClause
        {
            back -= 1
        }
        return back >= 0 && back < position - 1 && keyVerbs.contains(draft.shape(at: live[back]).key)
    }

    /// Whether a subject pronoun stands right after the mark or one word on, so the words before it end a clause rather than modify the mark.
    private static func opensClause(at next: Int, in live: [Int], of draft: Draft) -> Bool {
        let start = max(next - 1, 0)
        guard next < live.count else { return false }
        let end = min(next + 2, live.count)
        var boundedEnd = end
        for index in start..<end where draft.shape(at: live[index]).endsSentence {
            boundedEnd = index + 1
            break
        }
        guard boundedEnd > next else { return false }
        let words = live[start..<boundedEnd].map { draft.shape(at: $0).key }
        let tags = LexicalClass.tags(ofWords: words)
        return tags[(next - start)...].prefix(2).contains(.pronoun)
    }

    /// The words read before the mark to tell a verb after it, so the cost stays constant per mark.
    private static let predicateContext = 4

    /// Whether a verb stands right after the mark, so the words before it are the subject of that verb.
    private static func opensPredicate(at next: Int, in live: [Int], of draft: Draft) -> Bool {
        guard next < live.count else { return false }
        var start = next
        while start > 0, next - start < predicateContext, !draft.shape(at: live[start - 1]).endsSentence {
            start -= 1
        }
        let words = live[start...next].map { draft.shape(at: $0).key }
        return LexicalClass.tags(ofWords: words)[next - start] == .verb
    }

    /// Whether a dash written earlier in this sentence is still open, so the mark here closes the pair.
    private static func closesDashPair(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        var open = false
        for back in stride(from: position - 1, through: 0, by: -1) {
            let shape = draft.shape(at: live[back])
            if shape.endsSentence { break }
            if shape.suffix.contains("\u{2014}") { open.toggle() }
        }
        return open
    }

    /// Whether a quotation opened earlier in this sentence is still open, so a closing mark here closes it.
    private static func isOpenQuotation(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        for back in stride(from: position - 1, through: 0, by: -1) {
            let shape = draft.shape(at: live[back])
            if shape.suffix.contains(where: WordShape.openingQuotes.contains) || shape.endsSentence {
                return false
            }
            if shape.prefix.contains(where: WordShape.openingQuotes.contains) { return true }
        }
        return false
    }

    /// Whether a determiner opens the phrase the mark word heads; given `bridging`, only those words may stand between.
    private static func opensThePhrase(
        ending position: Int, reaching reach: Int, in live: [Int], of draft: Draft,
        bridgedBy bridging: Set<String>?, finalMark: Bool, opening: Bool, corroboratedByLayout: Bool,
        clauseFollows: Bool, predicateFollows: Bool
    ) -> Bool {
        // A hyphen joins the two words around it, so it heads no phrase and only the word before it speaks.
        let far = draft.shape(at: live[position]).key == "hyphen" ? 1 : reach
        for back in 1...min(far, position) {
            let shape = draft.shape(at: live[position - back])
            // A noun phrase cannot begin in the sentence before, so no opener stands on the far side of a stop.
            if shape.endsSentence { return false }
            if back == 1, mentionVerbs.contains(shape.key) || !opening && reportingVerbs.contains(shape.key) {
                return true
            }
            if back == 1, !opening, namesByNoun(at: position - back, in: live, of: draft) { return true }
            if !corroboratedByLayout,
                back == 1 ? determiners.contains(shape.key) : phraseOpeners.contains(shape.key)
            {
                return true
            }
            if let bridging {
                if !bridging.contains(shape.key) || markNames.contains(shape.key) { return false }
            } else if !isModifier(
                shape.key, before: draft.shape(at: live[position]).key, finalMark: finalMark,
                clauseFollows: clauseFollows, predicateFollows: predicateFollows,
                after: back < position ? draft.shape(at: live[position - back - 1]).key : nil
            ) {
                return false
            } else if back == 1, finalMark, nounHeads.contains(draft.shape(at: live[position]).key),
                finalPeriodCompoundModifiers.contains(shape.key)
            {
                return true
            }
        }
        return false
    }

    /// Whether the word at `position` is a naming noun a determiner introduces, so the mark name after it is the thing named: "the word comma".
    private static func namesByNoun(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard position > 0, namingWords.contains(draft.shape(at: live[position]).key) else { return false }
        return determiners.contains(draft.shape(at: live[position - 1]).key)
    }

    /// Recognizes local modifiers, ordinal numbers and cardinals before a period or dash.
    private static func isModifier(
        _ word: String, before head: String, finalMark: Bool, clauseFollows: Bool,
        predicateFollows: Bool, after preceding: String?
    ) -> Bool {
        if NumberFormsPass.ordinalUnits[word] != nil
            || (nounHeads.contains(head) && NumberWords.isNumber(word))
        {
            return true
        }
        // A clause opening after the mark says the word before it closes a clause: "the branch dash it fixes the bug".
        if clauseFollows && nounHeads.contains(head) { return false }
        let phrase = "the \(word) \(head)"
        guard let wordRange = phrase.range(of: word) else { return false }
        let lexicalClass = LexicalClass.tag(at: wordRange.lowerBound, in: phrase)
        // Adverbs can modify adjectives, and attributive -ing participles can be tagged as nouns.
        if lexicalClass == .adjective || lexicalClass == .adverb { return true }
        if lexicalClass == .noun, let preceding, isCardinal(preceding), nounHeads.contains(head) {
            return true
        }

        // Known period compounds stay words at a final spoken stop regardless of their lexical tag.
        if head == "period" && finalMark {
            if finalPeriodCompoundModifiers.contains(word) { return true }
            if countedPeriodUnits.contains(word) { return preceding.map(NumberWords.isNumber) ?? false }
            if gerundPeriodParticles.contains(word) { return preceding?.hasSuffix("ing") ?? false }
        }
        if lexicalClass == .noun && nounHeads.contains(head) && !finalMark {
            return true
        }

        // An -ing noun modifies a layout phrase only as a subject: "the opening new line got applause".
        let subject = nounHeads.contains(head) || predicateFollows
        return lexicalClass == .noun && word.hasSuffix("ing") && subject
    }

    /// Whether a word is a cardinal number, spelled or in digits.
    private static func isCardinal(_ word: String) -> Bool {
        NumberWords.digits(word) != nil || NumberWords.cardinal([word][...]) != nil
    }
}
