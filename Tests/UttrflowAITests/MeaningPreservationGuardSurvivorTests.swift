import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Verdicts that fail when one comparison in the guard is flipped, for the checks no other test pins down.
@Suite("MeaningPreservationGuard survivors")
struct MeaningPreservationGuardSurvivorTests {
    private let sut = MeaningPreservationGuard()

    /// Words heard at the given scores, in order.
    private func scored(_ words: [(String, Double)]) -> Draft {
        Draft(words: words.map { Draft.Word($0.0, evidence: .score($0.1)) })
    }

    /// A removed word is not in the text, so counting it shifts every later word onto its neighbour's score.
    @Test("reads a kept word's score as its own after a filler before it was taken out")
    func confidenceSkipsRemovedWords() {
        let draft = FillersPass().apply(
            scored([("um", 0.95), ("i", 0.95), ("can", 0.3), ("hear", 0.95), ("you", 0.95)]))

        #expect(draft.text == "i can hear you")
        #expect(
            sut.verdict(draft: draft, rewritten: "I can here you.")
                == .rejected(
                    reason: "the rewrite replaced high-confidence 'hear' with a sound-alike", kind: .lostWord)
        )
    }

    /// The guard's one caller filters to function words first, so only the count itself can show the filter.
    @Test("counts only function words as churn, however many content words the runs hold")
    func churnCountsFunctionWordsOnly() {
        let churn = { (kept: String, rewritten: String) in
            MeaningPreservationGuard.functionWordChurn(
                MeaningPreservationGuard.grammarTokens(kept),
                MeaningPreservationGuard.grammarTokens(rewritten))
        }

        #expect(churn("the report sat on the desk", "the letter sat on the table") == 0)
        #expect(churn("the report sat on the desk", "a report sat in the desk") == 4)
    }

    /// Three words may grow to twice their count plus four, and not one word more.
    @Test("refuses growth one word past twice what was said plus four, and allows it at the limit")
    func growthLimitIsExact() {
        let said = "send the report"
        let atLimit = "Please send the report to the board before Friday afternoon."
        let pastLimit = "Please send the report to the board before Friday afternoon today."

        #expect(MeaningPreservationGuard.lengthVerdict(original: said, rewritten: atLimit) == .accepted)
        #expect(
            MeaningPreservationGuard.lengthVerdict(original: said, rewritten: pastLimit)
                == .rejected(reason: "the rewrite is far longer than what was said", kind: .tooLong))
    }

    /// Three words are short enough to keep one; at four the retention floor applies.
    @Test("skips the retention floor at three words and applies it from four")
    func retentionFloorStartsAfterThreeWords() {
        #expect(
            MeaningPreservationGuard.lengthVerdict(original: "yes I will", rewritten: "Yes.") == .accepted)
        #expect(
            MeaningPreservationGuard.lengthVerdict(original: "yes I will go", rewritten: "Yes.")
                == .rejected(reason: "the rewrite dropped most of what was said", kind: .tooShort))
    }

    /// A mark the recogniser wrote inside a kept word answers only for that mark, never for a spoken one after it.
    @Test("counts a spoken comma after a hyphenated word as written")
    func inheritedMarksCountOnlyTheirOwnMark() {
        let draft = SpokenPunctuationPass().apply(Draft(text: "it is well-known comma right"))

        #expect(draft.text == "it is well-known, right")
        #expect(
            MeaningPreservationGuard.spokenPunctuationVerdict(
                draft: draft, rewritten: "It is well-known, right.")
                == .accepted)
    }

    /// Only a content word or a negation a pass took out without its grant must come back; a small word need not.
    @Test("asks back only content words and negations among unauthorised removals")
    func restoredKeepsContentAndNegationsOnly() {
        let restored = { (text: String) in
            MeaningPreservationGuard.restored([UnauthorisedRemoval(pass: .stammers, text: text)]).map(
                \.token.text)
        }

        #expect(restored("the") == [])
        #expect(restored("report") == ["report"])
        #expect(restored("not") == ["not"])
    }

    /// A one-letter reading is written only as a whole word, never as the first letter of a longer one.
    @Test("finds a one-letter reading only where it stands as a word")
    func oneLetterReadingIsAWholeWord() {
        #expect(!MeaningPreservationGuard.isWritten("a", in: "apple pie"))
        #expect(MeaningPreservationGuard.isWritten("a", in: "a pie"))
    }

    /// Unpunctuated dictation counts one sentence per forty words, rounded up.
    @Test("allows one sentence of churn per forty unpunctuated words, rounding up")
    func churnSentencesRoundUpPerFortyWords() {
        let sentences = { (count: Int) in
            let text = Array(repeating: "word", count: count).joined(separator: " ")
            return MeaningPreservationGuard.churnSentences(RewriteAlignment(kept: text, rewritten: text))
        }

        #expect(sentences(40) == 1)
        #expect(sentences(41) == 2)
    }

    /// Each line holding words counts them from nothing, one per word.
    @Test("counts the words on each line, one per word")
    func wordsPerLineCountsEachWordOnce() {
        #expect(MeaningPreservationGuard.wordsPerLine("one two\nthree") == [2, 1])
    }
}
