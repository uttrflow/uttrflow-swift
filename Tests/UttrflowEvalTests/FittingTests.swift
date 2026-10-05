import Testing

@testable import UttrflowEval

/// The fits dictation layers ship recover a known rule and stay deterministic.
@Suite("Fitting")
struct FittingTests {
    static let rows: [FitRow] = (0..<200).map { index in
        let value = Double(index % 20) / 10 - 1
        return FitRow(features: [value, 0.5], label: value > 0)
    }

    @Test("A linear fit ranks a separable feature the right way round")
    func linearSeparates() {
        let scorer = LinearScorer.fit(Self.rows)
        #expect(scorer.weights[0] > 1)
        #expect(scorer.probability([0.9, 0.5]) > 0.8)
        #expect(scorer.probability([-0.9, 0.5]) < 0.2)
        #expect(LinearScorer.fit(Self.rows) == scorer)
    }

    @Test("A fit with no rows is the zero scorer")
    func emptyFit() {
        let scorer = LinearScorer.fit([])
        #expect(scorer == LinearScorer(weights: [], bias: 0))
        #expect(scorer.probability([]) == 0.5)
    }

    @Test("A monotone calibration pools violators and never decreases")
    func calibrationPools() {
        let calibration = MonotoneCalibration.fit(
            scores: [1, 2, 3, 4, 5, 6], labels: [false, true, false, false, true, true])
        #expect(calibration.probabilities == calibration.probabilities.sorted())
        #expect(calibration.probability(1) == 0)
        #expect(calibration.probability(3) == 1.0 / 3)
        #expect(calibration.probability(9) == 1)
        #expect(MonotoneCalibration.fit(scores: [], labels: []).probability(1) == 0)
    }
}
