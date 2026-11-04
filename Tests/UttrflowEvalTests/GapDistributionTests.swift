import Testing
import UttrflowEval

struct GapDistributionTests {
    private func gaps(_ values: [(Double, Bool)]) -> [GapObservation] {
        values.map { GapObservation(milliseconds: $0.0, isBreak: $0.1) }
    }

    private func speaker(_ pace: String, _ dictations: [[GapObservation]]) -> SpeakerGaps {
        SpeakerGaps(
            profile: SpeakerProfile(voice: "V", rate: nil, name: pace, hesitation: 0, breakLength: 0),
            dictations: dictations)
    }

    private let fastDictation = [
        (60.0, false), (60, false), (60, false), (60, false), (60, false), (500, true),
    ]
    private let slowDictation = [
        (60.0, false), (60, false), (60, false), (60, false), (60, false), (1800, true),
    ]

    @Test func theDistributionTableGivesEachSpeakersOtherGapsAndBreaks() {
        let table = GapDistribution.distributionMarkdown([
            speaker("fast", [gaps(fastDictation)]), speaker("slow", [gaps(slowDictation)]),
        ])
        #expect(table.contains("| V fast | 1 | 5 | 60 | 60 | 60 | 1 | 500 | 500 |"))
        #expect(table.contains("| V slow | 1 | 5 | 60 | 60 | 60 | 1 | 1800 | 1800 |"))
    }

    @Test func theScoreTableHasOneRowPerRuleAndOneColumnPerPace() {
        let table = GapDistribution.scoreMarkdown([
            speaker("fast", [gaps(fastDictation)]), speaker("slow", [gaps(slowDictation)]),
        ])
        #expect(table.contains("| Rule | fast | slow | All |"))
        #expect(table.contains("| fixed 700 ms | 0.00 | 1.00 | 0.67 |"))
        #expect(table.contains("| rank 3 spreads | 1.00 | 1.00 | 1.00 |"))
    }

    @Test func theChangeFromFixedToRankIsPairedPerDictation() {
        let change = GapDistribution.change([
            speaker("fast", [gaps(fastDictation), gaps(fastDictation)]),
            speaker("slow", [gaps(slowDictation)]),
        ])
        #expect(abs(change.mean - 2.0 / 3.0) < 1e-9)
    }

    @Test func aPercentileOfNothingIsZeroAndOfAListIsTheNearestRank() {
        #expect(GapDistribution.percentile([], 0.9) == 0)
        #expect(GapDistribution.percentile([1, 2, 3, 4, 5], 0.9) == 5)
        #expect(GapDistribution.percentile([5, 1, 3], 0.5) == 3)
    }
}
