import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// Reproduces uttrflow-swift#2041: a word in `Homophones.groups` is doubtful regardless of confidence.
@Suite("Homophone-uncertain words", .bug(id: 2041))
struct HomophoneDoubtTests {
    /// A draft over the *sent* line, where every word is at high confidence.
    private func sureDraft(_ text: String, confidence: Double = 0.8) -> Draft {
        Draft(
            words: text.split(whereSeparator: \.isWhitespace).map {
                Draft.Word(String($0), evidence: .score(confidence))
            })
    }

    @Test(
        "a homophone word is in `UncertainSpan.spans` even at confidence 0.8, so downstream sources are asked",
        arguments: [
            ("asked the principal question today", "principal", "principle"),
            ("we will sail to the sale by noon", "sail", "sale"),
            ("she told the whole hole story", "whole", "hole"),
        ])
    func homophoneWordBecomesASpan(text: String, heard: String, partner: String) {
        let draft = sureDraft(text)
        let runs = UncertainSpan.spans(in: draft)
        #expect(
            runs.contains(where: { $0.text == heard }),
            "expected an uncertain span for `\(heard)` in \(text), got \(runs.map(\.text))")
    }

    @Test("a non-homophone word at 0.8 still produces no spans")
    func nonHomophoneWordIsNotASpan() {
        let draft = sureDraft("i peeled an apple yesterday")
        let runs = UncertainSpan.spans(in: draft)
        #expect(runs.isEmpty)
    }

    @Test("a homophone word at 0.8 appears as a single-word span, not a multi-word run")
    func homophoneSpanIsSingleWord() {
        let draft = sureDraft("the principal of the school is here")
        let runs = UncertainSpan.spans(in: draft)
        let principalSpans = runs.filter { $0.text == "principal" }
        #expect(principalSpans.count == 1)
        #expect(principalSpans.first?.range.count == 1)
    }

    @Test("a homophone span is offered with its partner as a reading")
    func homophoneSpanOffersItsPartner() async {
        let draft = sureDraft("asked the principal question at the meeting")
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        let principal = spans.first(where: { $0.heard == "principal" })
        #expect(principal != nil, "expected a doubtful span for `principal`, got \(spans.map(\.heard))")
        #expect(
            principal?.candidates.map(\.spelling).contains("principle") == true,
            "expected `principle` among candidates, got \(String(describing: principal?.candidates))")
    }

    @Test("a non-homophone word at 0.8 produces no doubtful spans")
    func nonHomophoneProducesNoSpans() async {
        let draft = sureDraft("asked the apple at the meeting")
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        #expect(spans.isEmpty, "no spans expected, got \(spans.map(\.heard))")
    }

    @Test("a homophone word already below threshold is not duplicated")
    func homophoneBelowThresholdIsNotDuplicated() {
        let draft = Draft.heard("the ?principal is here", unsure: 0.2)
        let runs = UncertainSpan.spans(in: draft)
        let principalRuns = runs.filter { $0.text == "principal" }
        #expect(
            principalRuns.count == 1, "expected one run for `principal`, got \(principalRuns.count)")
    }

    @Test("the Utterance path also doubts a homophone word at 0.8")
    func homophoneSpanFromUtterance() {
        let utterance = Utterance(words: [
            SpokenWord(text: "the", confidence: 0.8),
            SpokenWord(text: "principal", confidence: 0.8),
            SpokenWord(text: "spoke", confidence: 0.8),
        ])
        let runs = UncertainSpan.spans(in: utterance)
        #expect(
            runs.contains(where: { $0.text == "principal" }),
            "expected a span for `principal`, got \(runs.map(\.text))")
    }

    @Test("HomophoneCandidates returns the partner for a word in the homophones list")
    func homophoneCandidatesReturnsPartner() async {
        let source = HomophoneCandidates()
        let word = Draft.Word("principal", evidence: .score(0.8))
        let candidates = await source.candidates(for: word, in: .unknown)
        #expect(candidates.map(\.spelling) == ["principle"])
    }

    @Test("HomophoneCandidates returns nothing for a word not in the homophones list")
    func homophoneCandidatesReturnsNothingForUnlistedWord() async {
        let source = HomophoneCandidates()
        let word = Draft.Word("apple", evidence: .score(0.8))
        let candidates = await source.candidates(for: word, in: .unknown)
        #expect(candidates.isEmpty)
    }
}
