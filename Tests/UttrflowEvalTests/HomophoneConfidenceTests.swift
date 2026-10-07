// Tests how a decode of a homophone sentence is read and summarised.
import Testing
import UttrflowEval

@Suite("HomophoneConfidence")
struct HomophoneConfidenceTests {
    @Test func everySentenceHoldsItsMeantWordOnceInNormalisedForm() {
        for pair in HomophoneConfidence.programmerPairs + HomophoneConfidence.ordinaryPairs {
            let words = TextNormaliser.standard.words(pair.sentence)
            #expect(words.count { $0 == pair.meant } == 1, "\(pair.sentence)")
            #expect(!words.contains(pair.other), "\(pair.sentence)")
        }
        #expect(HomophoneConfidence.programmerPairs.count == 14)
        #expect(HomophoneConfidence.ordinaryPairs.count == 20)
    }

    @Test func aMatchedWordIsRightWithItsScore() {
        let outcome = HomophoneConfidence.outcome(
            reference: ["clear", "the", "cache"], index: 2,
            heard: [("clear", 0.9), ("the", 0.9), ("cache", 0.7)])
        #expect(outcome == .right(score: 0.7))
        #expect(!outcome.isError)
        #expect(outcome.score == 0.7)
    }

    @Test func aSubstitutedWordIsWrongWithTheScoreOfWhatWasWritten() {
        let outcome = HomophoneConfidence.outcome(
            reference: ["clear", "the", "cache"], index: 2,
            heard: [("so", 0.4), ("clear", 0.9), ("the", 0.9), ("cash", 0.8)])
        #expect(outcome == .wrong(heard: "cash", score: 0.8))
        #expect(outcome.isError)
    }

    @Test func aMissingWordIsDropped() {
        let outcome = HomophoneConfidence.outcome(
            reference: ["clear", "the", "cache"], index: 2, heard: [("clear", 0.9), ("the", 0.9)])
        #expect(outcome == .dropped)
        #expect(outcome.score == nil)
        #expect(outcome.isError)
        #expect(HomophoneConfidence.outcome(reference: ["a", "b"], index: 0, heard: [("b", 1)]) == .dropped)
        #expect(HomophoneConfidence.outcome(reference: ["a"], index: 3, heard: [("a", 1)]) == .dropped)
    }

    @Test func theSummaryCountsErrorsTheGateAndTheCurve() {
        let summary = HomophoneConfidence.summary([
            .right(score: 0.9), .right(score: 0.3), .wrong(heard: "cash", score: 0.8),
            .wrong(heard: "cash", score: 0.2), .dropped,
        ])
        #expect(summary.decodes == 5)
        #expect(summary.errors == 3)
        #expect(abs(summary.errorRate - 0.6) < 1e-9)
        #expect(summary.medianWrongScore == 0.5)
        #expect(summary.wrongBelowGate == 1.0 / 3.0)
        #expect(summary.rightBelowGate == 0.5)
        #expect(summary.auc == 0.75)
    }

    @Test func anEmptySummaryHasNoStatistics() {
        let summary = HomophoneConfidence.summary([])
        #expect(summary.errorRate == 0)
        #expect(summary.medianWrongScore == nil)
        #expect(summary.wrongBelowGate == nil)
        #expect(summary.rightBelowGate == nil)
        #expect(summary.auc == nil)
    }

    @Test func medianAndCurveHandleOddCountsAndTies() {
        #expect(HomophoneConfidence.median([0.3, 0.1, 0.2]) == 0.2)
        #expect(HomophoneConfidence.auc(wrong: [0.5], right: [0.5]) == 0.5)
        #expect(HomophoneConfidence.auc(wrong: [0.1], right: [0.9]) == 1)
        #expect(HomophoneConfidence.auc(wrong: [], right: [0.9]) == nil)
    }
}
