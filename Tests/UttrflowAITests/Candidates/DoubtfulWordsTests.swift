import Foundation
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

    /// Asked first, the dictionary's copy of a spelling is the one kept, so the screen repeating it cannot strip its entry.
    @Test("keeps the first source's reading of a spelling two sources offer, entry and all")
    func mergesKeepingTheEntry() {
        let entry = UUID()
        let merged = DoubtfulWords.merged(
            [[Reading("PaymentSheet", entryID: entry)], ["PaymentSheet", "paymentSheet"]],
            heard: "payment sheet")

        #expect(merged == [Reading("PaymentSheet", entryID: entry)])
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

    @Test("reads the screen once a piece, so ten times the words on it costs one encoding each")
    func encodesTheScreenOnce() async {
        let draft = Self.budgetDraft
        let runs = UncertainSpan.spans(in: draft, below: WordCorrectionEngine.certaintyThreshold).count
        let few = await Self.encodings(for: draft, screenWords: 50)
        let many = await Self.encodings(for: draft, screenWords: 500)

        #expect(runs >= 10, "the draft must doubt enough runs that a per-run read of the screen shows")
        #expect(many - few <= 450 + 45, "450 more words cost \(many - few) encodings over \(runs) runs")
    }

    @Test("costs a few encodings per doubtful run, never a pass over the screen or the vocabulary")
    func encodesEachRunCheaply() async {
        let one = Draft.heard("the ?order is late")
        let manyRuns = Self.budgetDraft
        let added =
            UncertainSpan.spans(in: manyRuns, below: WordCorrectionEngine.certaintyThreshold).count
            - UncertainSpan.spans(in: one, below: WordCorrectionEngine.certaintyThreshold).count
        let few = await Self.encodings(for: one, screenWords: 200)
        let many = await Self.encodings(for: manyRuns, screenWords: 200)

        #expect(added >= 10)
        #expect(many - few <= 4 * added, "\(added) more runs cost \(many - few) encodings")
    }

    /// Eight doubted words making fourteen runs of up to three, the shape the step was first measured against.
    private static let budgetDraft = Draft.heard(
        "the ?order ?totals ?view is ?stale after ?midnight and the ?cash ?report ?failed")

    /// The Double Metaphone encodings one candidate step makes over a selection of distinct screen words.
    private static func encodings(for draft: Draft, screenWords: Int) async -> Int {
        let selection = (0..<screenWords).map { "orderTotal\($0)" }.joined(separator: " ")
        let situation = Situation.showing(title: "revenue.sql", selection: selection)
        // Warmed first, because the vocabulary's sound index is built once on first use and is not the step's cost.
        _ = await DoubtfulWords.standard.spans(in: draft, for: situation)
        let tally = EncodingTally()
        await DoubleMetaphone.$tally.withValue(tally) {
            _ = await DoubtfulWords.standard.spans(in: draft, for: situation)
        }
        return tally.count
    }

    @Test("asks the user's own dictionary before the screen and the general vocabulary")
    func dictionaryComesFirst() async {
        let doubtful = DoubtfulWords.including(dictionary: { CorrectionFixtures.index })
        #expect(doubtful.sources.count == 3)
        #expect(doubtful.sources.first is DictionaryCandidates)
    }
}
