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
}
