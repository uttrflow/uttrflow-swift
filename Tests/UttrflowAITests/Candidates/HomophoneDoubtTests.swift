import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// Reproduces uttrflow-swift#2041: an ordinary word with an ordinary homophone is doubtful regardless of confidence.
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
            ("please write the answer today", "write", "right"),
            ("we hear the music", "hear", "here"),
            ("they buy the tickets", "buy", "by"),
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
        let draft = sureDraft("please write the answer soon")
        let runs = UncertainSpan.spans(in: draft)
        let writeSpans = runs.filter { $0.text == "write" }
        #expect(writeSpans.count == 1)
        #expect(writeSpans.first?.range.count == 1)
    }

    @Test("a homophone span is offered with its partner as a reading")
    func homophoneSpanOffersItsPartner() async {
        let draft = sureDraft("please write the answer at the meeting")
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        let write = spans.first(where: { $0.heard == "write" })
        #expect(write != nil, "expected a doubtful span for `write`, got \(spans.map(\.heard))")
        #expect(
            write?.candidates.map(\.spelling).contains("right") == true,
            "expected `right` among candidates, got \(String(describing: write?.candidates))")
    }

    @Test("a non-homophone word at 0.8 produces no doubtful spans")
    func nonHomophoneProducesNoSpans() async {
        let draft = sureDraft("asked the apple at the meeting")
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        #expect(spans.isEmpty, "no spans expected, got \(spans.map(\.heard))")
    }

    @Test("a homophone word already below threshold is not duplicated")
    func homophoneBelowThresholdIsNotDuplicated() {
        let draft = Draft.heard("please ?write the answer", unsure: 0.2)
        let runs = UncertainSpan.spans(in: draft)
        let writeRuns = runs.filter { $0.text == "write" }
        #expect(
            writeRuns.count == 1, "expected one run for `write`, got \(writeRuns.count)")
    }

    @Test("the Utterance path also doubts a homophone word at 0.8")
    func homophoneSpanFromUtterance() {
        let utterance = Utterance(words: [
            SpokenWord(text: "please", confidence: 0.8),
            SpokenWord(text: "write", confidence: 0.8),
            SpokenWord(text: "soon", confidence: 0.8),
        ])
        let runs = UncertainSpan.spans(in: utterance)
        #expect(
            runs.contains(where: { $0.text == "write" }),
            "expected a span for `write`, got \(runs.map(\.text))")
    }

    @Test("HomophoneCandidates returns the ordinary partner of an ordinary word")
    func homophoneCandidatesReturnsPartner() async {
        let source = HomophoneCandidates()
        let word = Draft.Word("write", evidence: .score(0.8))
        let candidates = await source.candidates(for: word, in: .unknown)
        #expect(candidates.map(\.spelling) == ["right"])
    }

    @Test("HomophoneCandidates returns nothing for a word with no ordinary homophone")
    func homophoneCandidatesReturnsNothingForUnlistedWord() async {
        let source = HomophoneCandidates()
        let word = Draft.Word("apple", evidence: .score(0.8))
        let candidates = await source.candidates(for: word, in: .unknown)
        #expect(candidates.isEmpty)
    }
}
