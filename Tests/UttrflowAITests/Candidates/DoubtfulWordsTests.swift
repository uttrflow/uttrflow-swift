import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Doubtful words: what the recogniser half-heard")
struct DoubtfulWordsTests {
    private let source = ScriptedCandidates(["apple": ["Apple", "apples"]])

    @Test("says nothing when the confidences are a stand-in rather than the recogniser's")
    func needsRealConfidences() async {
        var draft = Draft.heard("i ate an ?apple")
        draft = Draft(words: draft.words, confidencesAreReal: false)
        #expect(await DoubtfulWords(sources: [source]).spans(in: draft, for: .unknown).isEmpty)
    }

    @Test("says nothing when no source was wired to it")
    func needsSources() async {
        #expect(await DoubtfulWords(sources: []).spans(in: .heard("i ate an ?apple"), for: .unknown).isEmpty)
    }

    @Test("says nothing when the recogniser was sure of every word")
    func needsADoubtfulWord() async {
        #expect(
            await DoubtfulWords(sources: [source]).spans(in: .heard("i ate an apple"), for: .unknown).isEmpty)
    }

    @Test("offers the readings for the run the recogniser was unsure of")
    func offersReadings() async {
        let spans = await DoubtfulWords(sources: [source]).spans(in: .heard("i ate an ?apple"), for: .unknown)
        #expect(spans == [DoubtfulSpan(heard: "apple", confidence: 0.3, candidates: ["Apple", "apples"])])
    }

    @Test("keeps a source's readings in the order it was asked, each once, and never the words as heard")
    func merges() {
        let merged = DoubtfulWords.merged(
            [["Apple", "apple"], ["apples", "APPLE", ""], ["Apple"]], heard: "apple")
        #expect(merged == ["Apple", "apples"])
    }

    @Test("offers the longest doubtful run and drops the runs inside it")
    func prefersTheLongestRun() async {
        let sources = [ScriptedCandidates(["payment sheet": ["PaymentSheet"], "sheet": ["Sheet"]])]
        let spans = await DoubtfulWords(sources: sources)
            .spans(in: .heard("in ?payment ?sheet today"), for: .unknown)
        #expect(spans.map(\.heard) == ["payment sheet"])
    }

    @Test("stops at five spans, however many the recogniser doubted")
    func capsTheSpans() async {
        let words = (1...8).map { "?word\($0)" }.joined(separator: " sure ")
        let answers = Dictionary(uniqueKeysWithValues: (1...8).map { ("word\($0)", ["Word\($0)"]) })
        let spans = await DoubtfulWords(sources: [ScriptedCandidates(answers)])
            .spans(in: .heard(words), for: .unknown)
        #expect(spans.count == DoubtfulWords.maximumSpans)
    }

    @Test("stops at three readings for one span, however many the sources found")
    func capsTheReadings() async {
        let sources = [ScriptedCandidates(["apple": ["a", "b", "c", "d", "e"]])]
        let spans = await DoubtfulWords(sources: sources).spans(in: .heard("?apple"), for: .unknown)
        #expect(spans.first?.candidates == ["a", "b", "c"])
    }

    @Test("asks every source at the same time rather than one after another")
    func asksConcurrently() async {
        let line = StartLine(expected: 3)
        let sources = ["one", "two", "three"].map { BarrierCandidates(line: line, answer: $0) }
        let spans = await DoubtfulWords(sources: sources).spans(in: .heard("?apple"), for: .unknown)
        #expect(spans.first?.candidates == ["one", "two", "three"])
    }

    @Test("answers inside the ten milliseconds the design budgets for the whole step")
    func answersInsideTheBudget() async {
        let draft = Draft.heard(
            "the ?order ?totals ?view is ?stale after ?midnight and the ?cash ?report ?failed")
        let situation = Situation.showing(
            title: "revenue.sql — orderTotals", selection: String(repeating: "orderTotals ", count: 40),
            preceding: String(repeating: "select from ", count: 20))
        // Warmed once, because the first call builds the vocabulary's index and the design budgets a dictation.
        _ = await DoubtfulWords.standard.spans(in: draft, for: situation)

        var best = Duration.seconds(1)
        for _ in 0..<5 {
            let taken = await ContinuousClock().measure {
                _ = await DoubtfulWords.standard.spans(in: draft, for: situation)
            }
            best = min(best, taken)
        }
        #expect(best < .milliseconds(10), "the candidate step took \(best)")
    }

    @Test("asks the user's own dictionary before the screen and the general vocabulary")
    func dictionaryComesFirst() async {
        let doubtful = DoubtfulWords.including(dictionary: { CorrectionFixtures.index })
        #expect(doubtful.sources.count == 3)
        #expect(doubtful.sources.first is DictionaryCandidates)
    }
}
