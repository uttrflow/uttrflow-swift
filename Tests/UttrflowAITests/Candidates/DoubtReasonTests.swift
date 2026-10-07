import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Doubt carries its measured score and its reason apart")
struct DoubtReasonTests {
    /// Thirty words heard surely, four of them homophone-group words, and one word scored 0.2.
    private func crowdedDraft() -> Draft {
        let text =
            "we will sail to the sale and see the whole hole near the principal office before the "
            + "meeting where everyone agreed that the zebra plan was fine for now today"
        let words = text.split(separator: " ").map { word in
            Draft.Word(String(word), evidence: .score(word == "zebra" ? 0.2 : 0.95))
        }
        return Draft(words: words)
    }

    @Test("the measured-low word is offered first, ahead of every surely heard group word")
    func lowScoredWordComesFirst() async {
        let draft = crowdedDraft()
        #expect(draft.words.count == 30)
        let source = FixedSource(readings: [
            "zebra": ["Zebra"], "sail": ["sale"], "sale": ["sail"],
            "whole": ["hole"], "hole": ["whole"], "principal": ["principle"],
        ])
        let spans = await DoubtfulWords(sources: [source]).spans(in: draft, for: .unknown)
        #expect(spans.first?.heard == "zebra")
        #expect(spans.first?.reason == .lowScore)
        #expect(spans.first?.confidence == 0.2)
        #expect(spans.dropFirst().allSatisfy { $0.reason == .homophoneClass && $0.confidence == 0.95 })
    }

    @Test("a group word's prompt line shows its true score and why it is doubted")
    func promptLineShowsTrueScore() {
        let span = DoubtfulSpan(
            heard: "principal", confidence: 0.95, reason: .homophoneClass, candidates: ["principle"])
        #expect(
            PromptBuilder.doubtfulText([span])
                == "\"principal\" (heard at 0.95, sounds like another word) — could be: principle")
    }

    @Test("a run with any low-scored word is a low-score run measured at its weakest word")
    func mixedRunIsLowScore() {
        let runs = UncertainSpan.spans(
            in: [("the", 0.3, false), ("principal", 0.9, false)])
        let both = runs.first { $0.text == "the principal" }
        #expect(both?.reason == .lowScore)
        #expect(both?.confidence == 0.3)
        #expect(runs.first { $0.text == "principal" }?.reason == .homophoneClass)
    }
}

/// A source answering from a fixed table, so the test measures ordering and nothing else.
private struct FixedSource: CandidateSource {
    let readings: [String: [String]]

    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        (readings[word.text] ?? []).map { Reading($0) }
    }
}
