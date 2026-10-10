import Foundation
import Testing
import UttrflowEval

struct DoubtDetectorTests {
    private func judged(
        _ certainty: Double, wrong: Bool, _ cluster: String, surely: Bool = false, offered: Bool = false
    ) -> DoubtDetector.Judged {
        .init(
            scored: .init(certainty: certainty, isWrong: wrong, cluster: cluster), heardSurely: surely,
            offered: offered)
    }

    @Test func thresholdIsTheLastCertaintyOfTheWidestFlagThatKeepsPrecision() {
        let words = [
            judged(0.1, wrong: true, "a"), judged(0.2, wrong: false, "a"), judged(0.3, wrong: true, "a"),
            judged(0.8, wrong: false, "a"), judged(0.9, wrong: false, "a"),
        ].map(\.scored)
        #expect(WordDoubtEvaluation.threshold(words, atPrecision: 0.6) == 0.3)
        #expect(WordDoubtEvaluation.threshold(words, atPrecision: 1) == 0.1)
        #expect(
            WordDoubtEvaluation.threshold([judged(0.4, wrong: false, "a").scored], atPrecision: 0.5) == nil)
    }

    @Test func aVoiceIsFlaggedOnlyByAThresholdChosenOnTheOtherVoices() {
        let words = [
            judged(0.1, wrong: true, "a"), judged(0.6, wrong: false, "a"),
            judged(0.5, wrong: true, "b"), judged(0.55, wrong: false, "b"),
        ].map(\.scored)
        // "a" is graded by b's flag (0.5), "b" by a's flag (0.1): b's wrong word at 0.5 is missed.
        #expect(DoubtDetector.heldOutFlags(words, atPrecision: 1) == [true, false, false, false])
        #expect(DoubtDetector.heldOutFlags([judged(0.1, wrong: true, "a").scored], atPrecision: 1) == [false])
    }

    @Test func resultSeparatesConfidentErrorsAndTheCandidateCeiling() {
        let words = [
            judged(0.1, wrong: true, "a", offered: true), judged(0.9, wrong: true, "a", surely: true),
            judged(0.95, wrong: false, "a", surely: true),
            judged(0.2, wrong: true, "b"), judged(0.92, wrong: true, "b", surely: true, offered: true),
            judged(0.97, wrong: false, "b", surely: true),
        ]
        let result = DoubtDetector.evaluate(words, atPrecision: 1)
        // Chosen on both voices the flag sits at 0.92, but a's flag (0.9) misses b's confident error at 0.92.
        #expect(result.threshold == 0.92)
        #expect(result.recall == .init(count: 3, total: 4))
        #expect(result.precision == .init(count: 3, total: 3))
        #expect(result.confidentRecall == .init(count: 1, total: 2))
        #expect(result.ceiling == .init(count: 2, total: 4))
        #expect(result.reachable == .init(count: 1, total: 4))
    }

    @Test func aWordIsMeasuredAgainstTheMedianOfItsSentence() {
        let odd = DoubtDetector.relativeToSentence([0.9, 0.5, 0.7])
        for (value, expected) in zip(odd, [0.2, -0.2, 0]) { #expect(abs(value - expected) < 1e-9) }
        let even = DoubtDetector.relativeToSentence([0.2, 0.4, 0.6, 1.0])
        for (value, expected) in zip(even, [-0.3, -0.1, 0.1, 0.5]) { #expect(abs(value - expected) < 1e-9) }
        #expect(DoubtDetector.relativeToSentence([]) == [])
    }
}
