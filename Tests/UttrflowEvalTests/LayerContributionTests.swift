// Tests the per-layer ablation verdict: a layer is kept only when the paired change it makes excludes zero.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Each layer's marginal contribution")
struct LayerContributionTests {
    private static let cases = (0..<40).map {
        EvaluationCase(id: "case-\($0)", category: .everyday, spoken: "send it now", expected: "Send it now.")
    }

    private static func scores(failing: Set<Int>) -> [CaseScore] {
        cases.indices.map { index in
            Scorer.score(failing.contains(index) ? "send." : cases[index].expected, against: cases[index])
        }
    }

    private static func contribution(
        _ layer: QualityLayer, off: [CaseScore], full: [CaseScore]
    ) -> LayerContribution {
        LayerContribution(
            off: [layer], scores: off, reference: full, cases: cases, latency: .zero)
    }

    @Test("flags a layer that changes nothing for removal")
    func uselessLayerIsRemoved() {
        let same = Self.scores(failing: [3])
        let result = Self.contribution(.scoring, off: same, full: same)
        #expect(result.verdict == .remove)
        #expect(result.failedCases?.interval == 0...0)
        #expect(result.brokeCases == 0)
    }

    @Test("keeps a layer whose removal fails cases by more than the noise")
    func usefulLayerIsKept() throws {
        let result = Self.contribution(
            .formatting, off: Self.scores(failing: Set(0..<20)), full: Self.scores(failing: []))
        #expect(result.verdict == .keep)
        let failed = try #require(result.failedCases)
        #expect(failed.interval.lowerBound > 0)
        #expect(result.failedDelta == 0.5)
    }

    @Test("removes a layer whose one rescued case is inside the noise")
    func oneCaseIsNoise() {
        let result = Self.contribution(
            .candidateGeneration, off: Self.scores(failing: [7]), full: Self.scores(failing: []))
        #expect(result.verdict == .remove)
    }

    @Test("removes a layer that fails more cases with it on, and counts each one it broke")
    func harmfulLayerIsRemoved() {
        let result = Self.contribution(
            .recogniserBias, off: Self.scores(failing: []), full: Self.scores(failing: Set(0..<20)))
        #expect(result.verdict == .remove)
        #expect(result.brokeCases == 20)
        #expect(result.falseOverrideRate == 0.5)
    }

    @Test("judges the override gate only by the meaning-changing errors it prevents")
    func safetyLayerIsJudgedByHarm() {
        #expect(LayerContribution.preventsHarm([.overrideGate]))
        #expect(!LayerContribution.preventsHarm([.formatting]))
        let result = Self.contribution(
            .overrideGate, off: Self.scores(failing: Set(0..<20)), full: Self.scores(failing: []))
        #expect(result.verdict == .keep)
        #expect(result.meaningDelta > 0)
    }

    @Test("names every layer it measured in the table, with its verdict")
    func tableNamesLayers() {
        let rows = [
            Self.contribution(
                .formatting, off: Self.scores(failing: Set(0..<20)), full: Self.scores(failing: [])),
            Self.contribution(.scoring, off: Self.scores(failing: []), full: Self.scores(failing: [])),
        ]
        let table = LayerContribution.table(rows, latency: true)
        #expect(table.contains("| formatting |") && table.contains("| keep |"))
        #expect(table.contains("| scoring |") && table.contains("| remove |"))
        #expect(table.contains("Added latency"))
        #expect(!LayerContribution.table(rows, latency: false).contains("Added latency"))
    }
}
