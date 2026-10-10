// Tests the paired bootstrap that turns a change in error rate into an interval and a verdict.
import Testing

@testable import UttrflowEval

@Suite("The paired bootstrap")
struct PairedBootstrapTests {
    private func pair(_ before: Int, _ after: Int, words: Int = 100) -> PairedBootstrap.Pair {
        PairedBootstrap.Pair(errorsBefore: before, wordsBefore: words, errorsAfter: after, wordsAfter: words)
    }

    @Test("gives no interval under two utterances")
    func needsTwoUtterances() {
        #expect(PairedBootstrap.standard.estimate([]) == nil)
        #expect(PairedBootstrap.standard.estimate([pair(1, 9)]) == nil)
        #expect(PairedBootstrap(resamples: 0).estimate([pair(1, 2), pair(1, 2)]) == nil)
    }

    @Test("gives the same interval for the same runs every time")
    func deterministic() {
        let pairs = [pair(5, 3), pair(5, 7), pair(5, 4), pair(5, 8), pair(2, 2)]
        #expect(PairedBootstrap.standard.estimate(pairs) == PairedBootstrap.standard.estimate(pairs))
    }

    @Test("an identical change in every utterance has a zero-width interval at that change")
    func identicalChanges() throws {
        let estimate = try #require(PairedBootstrap.standard.estimate([pair(1, 3), pair(1, 3), pair(1, 3)]))
        #expect(abs(estimate.interval.lowerBound - 0.02) < 1e-12)
        #expect(abs(estimate.interval.upperBound - 0.02) < 1e-12)
        #expect(estimate.minimumDetectableChange < 1e-12)
    }

    @Test("more utterances resolve a smaller change")
    func moreUtterancesResolveMore() throws {
        let few = Array(repeating: [pair(5, 3), pair(5, 7)], count: 3).flatMap(\.self)
        let many = Array(repeating: [pair(5, 3), pair(5, 7)], count: 30).flatMap(\.self)
        let small = try #require(PairedBootstrap.standard.estimate(few))
        let large = try #require(PairedBootstrap.standard.estimate(many))
        #expect(large.minimumDetectableChange < small.minimumDetectableChange)
        #expect(small.interval.contains(0))
        #expect(large.interval.contains(0))
    }

    @Test("the inverse normal matches its tabulated values")
    func normalQuantile() {
        #expect(abs(PairedBootstrap.standardNormalQuantile(0.975) - 1.959_964) < 1e-6)
        #expect(abs(PairedBootstrap.standardNormalQuantile(0.8) - 0.841_621) < 1e-6)
        #expect(abs(PairedBootstrap.standardNormalQuantile(0.01) + 2.326_348) < 1e-6)
        #expect(abs(PairedBootstrap.standardNormalQuantile(0.5)) < 1e-9)
    }
}
