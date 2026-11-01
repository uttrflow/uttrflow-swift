import Testing
import UttrflowCore
import UttrflowEval

struct SpeakerRhythmTests {
    private func rhythm(_ gaps: [Double]) -> SpeakerRhythm {
        var rhythm = SpeakerRhythm()
        for gap in gaps { rhythm.add(gap) }
        return rhythm
    }

    private func heard(_ gaps: [(Double, Bool)]) -> [GapObservation] {
        gaps.map { GapObservation(milliseconds: $0.0, isBreak: $0.1) }
    }

    @Test func gapsHaveTheDetectorFloorTakenOffAndNeverGoBelowZero() {
        let floor = SpeakerRhythm.detectorFloor
        let estimate = rhythm([floor + 100, floor + 100, floor + 100, 0, 0])
        #expect(estimate.median == 100)
        #expect(estimate.spread == 20)
    }

    @Test func noRankIsGivenUntilTheWarmUpCountOfGapsIsHeard() {
        #expect(rhythm([100, 100, 100, 100]).rank(of: 900) == nil)
        #expect(rhythm([100, 100, 100, 100, 100]).rank(of: 900) != nil)
    }

    @Test func aRankCountsSpreadsAboveTheMedianAfterTheFloor() throws {
        let floor = SpeakerRhythm.detectorFloor
        let estimate = rhythm([floor + 100, floor + 100, floor + 100, floor + 100, floor + 100])
        let rank = try #require(estimate.rank(of: floor + 100 + 200))
        #expect(rank == 10)
        #expect(try #require(estimate.rank(of: floor + 100)) == 0)
    }

    @Test func spreadFollowsTheMedianAbsoluteDeviationOfTheGaps() {
        let floor = SpeakerRhythm.detectorFloor
        let estimate = rhythm([0, 100, 200, 300, 400].map { $0 + floor })
        #expect(abs(estimate.spread - 1.4826 * 100) < 0.001)
    }

    @Test func aFixedRuleCallsEveryGapAtOrOverItsLength() {
        let gaps = heard([(100, false), (700, true), (699, true), (900, false)])
        let score = PauseRule.fixed(milliseconds: 700).score(gaps)
        #expect(score.truePositives == 1)
        #expect(score.falseNegatives == 1)
        #expect(score.falsePositives == 1)
    }

    @Test func aRankRuleFindsABreakShorterThanAFixedLengthAmongShortGaps() {
        let gaps = heard(Array(repeating: (60.0, false), count: 6) + [(500, true), (60, false)])
        #expect(PauseRule.fixed(milliseconds: 700).score(gaps).recall == 0)
        let score = PauseRule.relative(spreads: 3).score(gaps)
        #expect(score.truePositives == 1)
        #expect(score.falsePositives == 0)
    }

    @Test func aRankRuleCallsNothingBeforeTheWarmUp() {
        let score = PauseRule.relative(spreads: 3).score(heard([(900, true), (900, true)]))
        #expect(score.truePositives == 0)
        #expect(score.falseNegatives == 2)
    }

    @Test func scoresAreRatiosOfCountsAndSumAcrossDictations() throws {
        var one = PauseRule.fixed(milliseconds: 100).score(heard([(200, true), (200, false)]))
        let two = PauseRule.fixed(milliseconds: 100).score(heard([(50, true)]))
        one = one + two
        #expect(one.precision == 0.5)
        #expect(one.recall == 0.5)
        #expect(abs(one.f1 - 0.5) < 1e-9)
        #expect(BreakScore().precision == nil)
        #expect(BreakScore().recall == nil)
        #expect(BreakScore().f1 == 0)
    }

    @Test func aPairedChangeIsAGainOnlyPastItsBound() {
        let steady = PairedChange(before: [0.5, 0.5, 0.5, 0.5], after: [0.9, 0.9, 0.9, 0.9])
        #expect(abs(steady.mean - 0.4) < 1e-9)
        #expect(steady.bound == 0)
        #expect(steady.isGain)
        let noisy = PairedChange(before: [0.5, 0.5, 0.5, 0.5], after: [0.9, 0.1, 0.9, 0.1])
        #expect(noisy.mean == 0)
        #expect(!noisy.isGain)
        #expect(PairedChange(before: [0.1], after: [0.9]).bound == .infinity)
        #expect(PairedChange(before: [], after: []).mean == 0)
    }
}
