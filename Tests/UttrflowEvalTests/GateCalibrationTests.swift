import Testing

@testable import UttrflowEval

/// The override gate's threshold is certified only where its counts bound the false-override rate.
@Suite("Gate calibration")
struct GateCalibrationTests {
    /// A gate whose score separates: `count` decisions, the `wrongCount` lowest-scored wrong.
    static func simulated(count: Int, wrongCount: Int) -> (scores: [Double], wrong: [Bool]) {
        ((0..<count).map { Double($0) }, (0..<count).map { $0 < wrongCount })
    }

    @Test(
        "The bound matches published one-sided Clopper-Pearson values",
        arguments: [
            (0, 10, 0.95, 0.258866), (1, 10, 0.95, 0.394163), (2, 20, 0.95, 0.282619),
            (5, 100, 0.95, 0.102253), (10, 100, 0.975, 0.176223), (0, 2_995, 0.95, 0.000999744),
        ])
    func publishedValues(failures: Int, trials: Int, confidence: Double, expected: Double) {
        let bound = RiskBound.upperBound(failures: failures, trials: trials, confidence: confidence)
        #expect(abs(bound - expected) < expected * 1e-4)
    }

    @Test("A rate with every trial failed, or no trial at all, is bounded by one")
    func degenerate() {
        #expect(RiskBound.upperBound(failures: 3, trials: 3, confidence: 0.95) == 1)
        #expect(RiskBound.upperBound(failures: 0, trials: 0, confidence: 0.95) == 1)
        #expect(RiskBound.atMost(0, of: 5, rate: 0) == 1)
        #expect(RiskBound.atMost(2, of: 5, rate: 1) == 0)
        #expect(RiskBound.atMost(5, of: 5, rate: 1) == 1)
    }

    @Test("Certifying 1 in 1,000 with none wrong takes 2,995 overrides; 1 in 100 takes 299")
    func trialsToCertify() {
        #expect(RiskBound.trialsToCertify(0.001, confidence: 0.95) == 2_995)
        #expect(RiskBound.trialsToCertify(0.01, confidence: 0.95) == 299)
        #expect(RiskBound.trialsToCertify(1, confidence: 0.95) == 1)
        #expect(RiskBound.trialsToCertify(0, confidence: 0.95) == Int.max)
    }

    @Test("A gate with a 0.2% false rate is certified at 1% on 1,000 decisions")
    func certifiedAtOnePercent() throws {
        let gate = Self.simulated(count: 1_000, wrongCount: 2)
        let calibration = GateCalibration(scores: gate.scores, wrong: gate.wrong, target: 0.01)
        let certified = try #require(calibration.certified)
        #expect(certified.overrides == 1_000)
        #expect(certified.wrong == 2)
        #expect(certified.upperBound <= 0.01)
        #expect(calibration.shipped == certified)
        #expect(calibration.certifiedRate == 0.01)
        #expect(calibration.report.last?.hasPrefix("certified at 1.00%: threshold 0, 2 of 1000") == true)
    }

    @Test("The same gate is not certified at 0.1%, and ships its strictest threshold at that one's own bound")
    func notCertifiedAtOneInAThousand() throws {
        let gate = Self.simulated(count: 1_000, wrongCount: 2)
        let calibration = GateCalibration(scores: gate.scores, wrong: gate.wrong, target: 0.001)
        #expect(calibration.certified == nil)
        let shipped = try #require(calibration.shipped)
        #expect(shipped.threshold == 999)
        #expect(shipped.overrides == 1)
        #expect(calibration.certifiedRate == shipped.upperBound)
        #expect(calibration.smallestCertifiableTarget > 0.001)
        let last = try #require(calibration.report.last)
        #expect(last.hasPrefix("not certified at 0.10%; ships the strictest threshold 999"))
    }

    @Test("Testing stops at the first threshold that fails; a looser one that passes again is never chosen")
    func fixedSequenceStops() throws {
        var scores = [Double](repeating: 3, count: 400) + [Double](repeating: 2, count: 400)
        var wrong = [Bool](repeating: false, count: 800)
        scores += [Double](repeating: 1, count: 2_000)
        wrong[400] = true
        wrong[401] = true
        wrong[402] = true
        wrong[403] = true
        wrong += [Bool](repeating: false, count: 2_000)
        let calibration = GateCalibration(scores: scores, wrong: wrong, target: 0.01)
        #expect(calibration.steps.map(\.threshold) == [3, 2, 1])
        #expect(calibration.steps[1].upperBound > 0.01)
        #expect(calibration.steps[2].upperBound <= 0.01)
        #expect(try #require(calibration.certified).threshold == 3)
    }

    @Test("Every report names the decisions, every bound and the smallest certifiable target")
    func reportCarriesIntervals() {
        let calibration = GateCalibration(scores: [2, 2, 3], wrong: [false, true, false], target: 0.01)
        let report = calibration.report
        #expect(report[0] == "decisions weighed: 3; target 1.00% false overrides at 95.00% confidence")
        #expect(report[1].hasPrefix("smallest target this split can certify: 63.16%"))
        #expect(calibration.steps.map(\.overrides) == [1, 3])
        for line in report where line.contains("overrides wrong") { #expect(line.contains("at most")) }
        let empty = GateCalibration(scores: [], wrong: [], target: 0.01)
        #expect(empty.report.last == "no decisions: nothing to certify")
    }
}
