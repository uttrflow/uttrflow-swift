import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Hypothesis set: every source's readings of one span, scored through one seam")
struct HypothesisSetTests {
    /// Prefers the reading the most sources agree on, so a test can tell a scorer from the sources' order.
    private struct AgreementScorer: SpanScorer {
        let cost = SpanScorerCost.lookup
        func scores(for set: HypothesisSet) -> [Double] {
            set.hypotheses.map { Double($0.features.agreement) }
        }
    }

    /// Prefers the reading the sources offered last, so a test can see the span's limit is applied after scoring.
    private struct LastFirstScorer: SpanScorer {
        let cost = SpanScorerCost.lookup
        func scores(for set: HypothesisSet) -> [Double] { set.hypotheses.indices.map(Double.init) }
    }

    @Test("records which source offered a reading first and how many sources offered it")
    func recordsFeatures() {
        let set = HypothesisSet(
            heard: "apple", confidence: 0.3,
            answers: [["Apple", "apple"], ["apples", "APPLE", ""], ["Apple"]])
        #expect(set.hypotheses.map(\.reading.spelling) == ["Apple", "apples"])
        #expect(set.hypotheses.map(\.features.firstSource) == [0, 1])
        #expect(set.hypotheses.map(\.features.agreement) == [3, 1])
    }

    @Test("the source-order scorer keeps the readings in the order the sources were asked")
    func sourceOrderKeepsOrder() {
        let set = HypothesisSet(heard: "apple", confidence: 0.3, answers: [["Apple"], ["apples", "Apple"]])
        #expect(set.ranked(by: SourceOrderScorer()).map(\.spelling) == ["Apple", "apples"])
    }

    @Test("a scorer that answers for the wrong number of readings changes nothing")
    func mismatchedScoresKeepOrder() {
        struct Short: SpanScorer {
            let cost = SpanScorerCost.lookup
            func scores(for set: HypothesisSet) -> [Double] { [1] }
        }
        let set = HypothesisSet(heard: "apple", confidence: 0.3, answers: [["Apple", "apples"]])
        #expect(set.ranked(by: Short()).map(\.spelling) == ["Apple", "apples"])
    }

    @Test("the doubtful words offer a span's readings in the order its scorer ranks them")
    func doubtfulWordsUseTheScorer() async {
        let sources = [
            ScriptedCandidates(["apple": ["Apple", "apples"]]), ScriptedCandidates(["apple": ["apples"]]),
        ]
        let spans = await DoubtfulWords(sources: sources, scorer: AgreementScorer())
            .spans(in: .heard("i ate an ?apple"), for: .unknown)
        #expect(spans.first?.candidates.map(\.spelling) == ["apples", "Apple"])
    }

    @Test("a span keeps the readings its scorer ranks best, not the first the sources offered")
    func limitFollowsTheScorer() async {
        let source = ScriptedCandidates(["apple": ["Apple", "apples", "appeal", "chapel"]])
        let spans = await DoubtfulWords(sources: [source], scorer: LastFirstScorer())
            .spans(in: .heard("i ate an ?apple"), for: .unknown)
        #expect(spans.first?.candidates.first?.spelling == "chapel")
        #expect(spans.first?.candidates.count == DoubtfulWords.maximumCandidatesPerSpan)
    }
}
