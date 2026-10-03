import NaturalLanguage
import UttrflowCore

/// Words that mean the word after them is being talked about rather than dictated.
enum MentionGuard {
    private static let namingWords: Set<String> = ["word", "say", "write", "type", "spell", "said"]
    private static let finalPeriodCompoundModifiers: Set<String> = [
        "cooling", "day", "following", "grace", "holding", "month", "notice", "off", "time", "trial",
        "victorian", "waiting", "week", "year",
    ]

    /// Whether a hesitation spelling is named by the immediately preceding word or an opening quote.
    static func namesToken(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let shape = draft.shape(at: live[position])
        if shape.prefix.contains(where: WordShape.openingQuotes.contains) { return true }
        guard position > 0 else { return false }
        return namingWords.contains(draft.shape(at: live[position - 1]).key)
    }

    /// Verbs and naming nouns that name the mark or layout phrase which follows them.
    private static let mentionVerbs: Set<String> = [
        "type", "say", "make", "write", "use", "press", "phrase", "term", "symbol",
    ]

    /// Reporting verbs that name a closing or joining mark after them but introduce an opening quote.
    private static let reportingVerbs: Set<String> = ["said", "says"]

    /// Mark names that are also nouns a number or another noun may modify: "a waiting period", "the hundred metre dash".
    private static let nounHeads: Set<String> = ["period", "dash"]

    static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "these", "those", "each",
        "every",
        "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// The ones a modifier may stand between and the mark; a verb takes its object with nothing in between.
    static let phraseOpeners: Set<String> = [
        "a", "an", "the", "with", "no", "this", "that", "these", "those", "each", "every", "one", "my",
        "your",
        "his",
        "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// How far back the word that opens a noun phrase may stand: "the hundred metre dash".
    static let phraseReach = 3

    /// The spoken names of marks and layout, which close the phrase an opener began rather than heading it.
    static let markNames: Set<String> = Set(
        SpokenPunctuationPass.marks.flatMap(\.words) + LayoutWordsPass.marks.flatMap(\.words))

    /// Whether the mark word at `position` is mentioned; `reach` is how far the phrase's own opener may stand.
    static func isMentioned(
        at position: Int, spanning length: Int, in live: [Int], of draft: Draft, reach: Int = 1,
        kind: SpokenMarkKind = .trailing, bridgedBy bridging: Set<String>? = nil,
        corroboratedByLayout: Bool = false
    ) -> Bool {
        // An opening mark goes on the word after it, so a text beginning with one is using it, not naming it.
        guard position > 0 else { return kind != .opening }
        if opensThePhrase(
            ending: position, reaching: reach, in: live, of: draft, bridgedBy: bridging,
            finalMark: kind == .trailing && position + length == live.count, opening: kind == .opening,
            corroboratedByLayout: corroboratedByLayout
        ) {
            return true
        }
        let next = position + length
        return next < live.count && draft.shape(at: live[next]).key == "of"
    }

    /// Whether a determiner opens the phrase the mark word heads; given `bridging`, only those words may stand between.
    private static func opensThePhrase(
        ending position: Int, reaching reach: Int, in live: [Int], of draft: Draft,
        bridgedBy bridging: Set<String>?, finalMark: Bool, opening: Bool, corroboratedByLayout: Bool
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
            if !corroboratedByLayout,
                back == 1 ? determiners.contains(shape.key) : phraseOpeners.contains(shape.key)
            {
                return true
            }
            if let bridging {
                if !bridging.contains(shape.key) || markNames.contains(shape.key) { return false }
            } else if !isModifier(
                shape.key, before: draft.shape(at: live[position]).key, finalMark: finalMark
            ) {
                return false
            }
        }
        return false
    }

    /// Recognizes local modifiers, ordinal numbers and cardinal numbers before a period.
    private static func isModifier(_ word: String, before head: String, finalMark: Bool) -> Bool {
        if NumberFormsPass.ordinalUnits[word] != nil
            || (nounHeads.contains(head) && NumberWords.isNumber(word))
        {
            return true
        }
        let phrase = "the \(word) \(head)"
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = phrase
        guard let wordRange = phrase.range(of: word) else { return false }
        let lexicalClass = tagger.tag(at: wordRange.lowerBound, unit: .word, scheme: .lexicalClass).0
        // Adverbs can modify adjectives, and attributive -ing participles can be tagged as nouns.
        if lexicalClass == .adjective || lexicalClass == .adverb { return true }

        // Known period compounds stay words at a final spoken stop regardless of their lexical tag.
        if head == "period" && finalMark && finalPeriodCompoundModifiers.contains(word) { return true }
        if lexicalClass == .noun && nounHeads.contains(head) && !finalMark {
            return true
        }

        return lexicalClass == .noun && word.hasSuffix("ing")
    }
}
