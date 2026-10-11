import Testing

@testable import UttrflowEval

struct AutoLearnReplayTests {
    private typealias Replay = AutoLearnReplay

    private func fix(_ day: Int, _ heard: String = "knew", _ meant: String = "new") -> Replay.Edit {
        Replay.Edit(day: day, heard: heard, meant: meant, kind: .trueFix)
    }

    @Test func aFixSeenOnSeparateDaysIsLearntAndScoredAsTrue() {
        let report = Replay.replay([fix(1), fix(2), fix(3)], heldOut: ["printer"])
        #expect(report.learntPairs == 1)
        #expect(report.learntTrueFixes == 1)
        #expect(report.precision == 1)
        #expect(report.recall == 1)
        #expect(report.meetsBounds)
    }

    @Test func aBurstOnOneDayAndAOneOffTypoLearnNothing() {
        let burst = (0..<6).map { _ in
            Replay.Edit(day: 1, heard: "teh", meant: "the", kind: .decoy(.autocorrect))
        }
        let typo = Replay.Edit(day: 2, heard: "printre", meant: "printer", kind: .decoy(.typo))
        let report = Replay.replay(burst + [typo], heldOut: [])
        #expect(report.learntPairs == 0)
        #expect(report.learntFromDecoys == 0)
    }

    @Test func aDecoyThatRecursOnSeparateDaysIsCountedAgainstTheBound() {
        let recurring = (1...3).map {
            Replay.Edit(day: $0, heard: "teh", meant: "the", kind: .decoy(.autocorrect))
        }
        let report = Replay.replay(recurring, heldOut: [])
        #expect(report.learntFromDecoys == 1)
        #expect(report.falseLearnRate == 1)
        #expect(!report.meetsBounds)
    }

    @Test func aLearntPairRewritesHeldOutWordsThatReferenceKeeps() {
        let report = Replay.replay(
            [fix(1, "no", "know"), fix(2, "no", "know"), fix(3, "no", "know")],
            heldOut: ["no", "answer", "no", "the"])
        #expect(report.falseOverrides == 2)
        #expect(report.falseOverrideRate == 0.5)
        #expect(!report.meetsBounds)
    }

    @Test func theCorpusScenarioLearnsNothingFromDecoysAndKeepsPrecision() {
        let scenario = Replay.scenario(from: EvaluationCorpus.all)
        let report = Replay.replay(scenario.edits, heldOut: scenario.heldOut)
        #expect(report.trueFixPairs > 0)
        #expect(report.learntTrueFixes > 0)
        #expect(report.learntFromDecoys == Replay.maximumDecoyPairs)
        #expect(report.falseLearnRate <= Replay.maximumFalseLearnRate)
        #expect(report.falseOverrideRate > 0, "common-word pairs such as to and too rewrite held-out words")
    }
}
