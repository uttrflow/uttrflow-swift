import Testing
import UttrflowEval

struct CandidateSeparationTests {
    private typealias Slot = CandidateSeparation.Slot

    private let separated = Slot(forcedDifference: 1, meantMargin: 0.5, otherMargin: 1, cluster: "a")
    private let clear = Slot(forcedDifference: 2, meantMargin: 2, otherMargin: -1, cluster: "b")

    @Test func theGreedyStepGivesItsLeaderTheTopTwoGapAndAnyOtherTokenItsDistanceBehind() throws {
        let step = try #require(CandidateSeparation.GreedyStep(logProbabilities: [-3, -0.5, -1, -2]))
        #expect(step.leader == 1)
        #expect(step.margin(of: 1, logProbability: -0.5) == 0.5)
        #expect(step.margin(of: 3, logProbability: -2) == -1.5)
        #expect(CandidateSeparation.GreedyStep(logProbabilities: [-1]) == nil)
    }

    @Test func candidatesDifferAtTheirFirstUnequalTokenOrNotAtAllWhenOneBeginsTheOther() {
        #expect(CandidateSeparation.firstDifference([5], [6]) == 0)
        #expect(CandidateSeparation.firstDifference([1, 2, 3], [1, 4]) == 1)
        #expect(CandidateSeparation.firstDifference([1, 2], [1, 2, 3]) == nil)
    }

    @Test func eachSlotGivesTheMeantWordAsRightAndItsRivalAsWrongUnderEveryFeature() {
        let slot = Slot(forcedDifference: 2, meantMargin: 1, otherMargin: -1, cluster: "a")
        let certainties = { (feature: CandidateSeparation.Feature) in
            CandidateSeparation.candidates([slot], by: feature).map(\.certainty)
        }
        #expect(certainties(.forced) == [2, -2])
        #expect(certainties(.greedyMargin) == [1, -1])
        #expect(certainties(.both) == [2, -2])
        #expect(CandidateSeparation.candidates([slot], by: .forced).map(\.isWrong) == [false, true])
        let flat = Slot(forcedDifference: 0, meantMargin: 0, otherMargin: 0, cluster: "a")
        #expect(CandidateSeparation.candidates([flat], by: .both).map(\.certainty) == [0, 0])
    }

    @Test func theForcedScoreBeatsAMarginThatRanksOneRivalAboveAMeantWord() throws {
        let slots = [separated, clear]
        #expect(try #require(CandidateSeparation.auroc(slots, by: .forced)).value == 1)
        #expect(try #require(CandidateSeparation.auroc(slots, by: .greedyMargin)).value == 0.75)
        let advantage = try #require(
            CandidateSeparation.advantage(of: .forced, over: .greedyMargin, in: slots))
        #expect(advantage.value == 0.25)
        #expect(advantage.low <= advantage.value && advantage.value <= advantage.high)
        #expect(CandidateSeparation.advantage(of: .forced, over: .greedyMargin, in: []) == nil)
    }

    @Test func aConfidentErrorIsOneWhereBothTheForcedScoreAndTheGreedyStepPreferTheRival() {
        let slots = [
            Slot(forcedDifference: -1, meantMargin: -0.5, otherMargin: 0.5, cluster: "a"),
            Slot(forcedDifference: -1, meantMargin: 0.2, otherMargin: -0.2, cluster: "a"),
            Slot(forcedDifference: 1, meantMargin: -0.5, otherMargin: 0.5, cluster: "a"),
        ]
        #expect(CandidateSeparation.confidentErrors(slots) == 1)
    }

    @Test func theReportPrintsEachFeatureTheDifferenceAndTheConfidentErrors() {
        let report = CandidateSeparation.markdown([separated, clear])
        #expect(report.contains("slots 2 in 2 clusters; 95% intervals resample whole clusters"))
        #expect(report.contains("| forced score | 1.000 | [1.000, 1.000] |"))
        #expect(report.contains("| greedy-step margin | 0.750 |"))
        #expect(report.contains("forced minus greedy-step margin: +0.250, 95% interval ["))
        #expect(report.contains("confident errors (forced and greedy step both prefer the rival): 0"))
        #expect(CandidateSeparation.markdown([]).contains("| forced score | - | - |"))
    }
}
