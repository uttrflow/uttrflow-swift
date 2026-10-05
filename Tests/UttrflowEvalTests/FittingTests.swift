import Foundation
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

    // The digest of `rows`' fit, recorded on an Apple M5 Pro; any process or Mac must reproduce it.
    static let scorerDigest = "5e056c9abb1343a431d0bf6d29e7f17c65eaddcfd61916c757f4599088edffec"

    @Test("A fit's digest is the recorded one in every process, without deterministic hashing")
    func digestIsPinned() {
        #expect(ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == nil)
        #expect(LinearScorer.fit(Self.rows).digest == Self.scorerDigest)
    }

    @Test("Fits on eight threads at once give one digest")
    func threadsAgree() async {
        let digests = await withTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { LinearScorer.fit(Self.rows).digest } }
            return await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(digests == [LinearScorer.fit(Self.rows).digest])
    }

    @Test("Equal scores calibrate the same whatever order their labels arrive in")
    func calibrationTiesAreOrdered() {
        let forward = MonotoneCalibration.fit(scores: [1, 1, 2, 2], labels: [true, false, false, true])
        let reverse = MonotoneCalibration.fit(scores: [2, 2, 1, 1], labels: [true, false, false, true])
        #expect(forward.digest == reverse.digest)
    }

    @Test("A stored float drops last-bit noise and signed zero")
    func storedFormRounds() {
        #expect(FitArtifact.stored(0.1 + 0.2) == FitArtifact.stored(0.3))
        #expect(FitArtifact.stored(-0.0) == FitArtifact.stored(0))
    }
}
