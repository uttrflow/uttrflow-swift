import Foundation
import Testing
import UttrflowCore
import UttrflowEval

struct WordDoubtFeaturesTests {
    private let word = [
        TokenEvidence(logProb: log(0.4), alternatives: [log(0.35), log(0.1)]),
        TokenEvidence(logProb: log(0.99)),
    ]

    @Test func meanHidesADoubtfulFirstTokenThatMinimumAndFirstTokenKeep() throws {
        let mean = try #require(WordDoubtFeature.mean.certainty(of: word))
        #expect(abs(mean - (0.4 * 0.99).squareRoot()) < 1e-9)
        #expect(abs(try #require(WordDoubtFeature.minimum.certainty(of: word)) - 0.4) < 1e-9)
        #expect(abs(try #require(WordDoubtFeature.firstToken.certainty(of: word)) - 0.4) < 1e-9)
        #expect(abs(try #require(WordDoubtFeature.firstMargin.certainty(of: word)) - 0.05) < 1e-9)
    }

    @Test func entropyIsHigherWhenTheRunnerUpIsClose() throws {
        let close = [TokenEvidence(logProb: log(0.5), alternatives: [log(0.5)])]
        let clear = [TokenEvidence(logProb: log(0.99), alternatives: [log(0.01)])]
        let closeCertainty = try #require(WordDoubtFeature.negatedEntropy.certainty(of: close))
        let clearCertainty = try #require(WordDoubtFeature.negatedEntropy.certainty(of: clear))
        #expect(closeCertainty < clearCertainty)
        #expect(abs(closeCertainty + log(2)) < 1e-9)
    }

    @Test func aWordWithoutTokensHasNoCertainty() {
        for feature in WordDoubtFeature.allCases { #expect(feature.certainty(of: []) == nil) }
    }

    @Test func aFirstTokenWithoutRunnersUpHasItsWholeProbabilityAsMargin() throws {
        let alone = [TokenEvidence(logProb: log(0.7))]
        #expect(abs(try #require(WordDoubtFeature.firstMargin.certainty(of: alone)) - 0.7) < 1e-9)
    }

    private func scored(
        _ certainty: Double, wrong: Bool, _ cluster: String = "a"
    ) -> WordDoubtEvaluation.Scored {
        .init(certainty: certainty, isWrong: wrong, cluster: cluster)
    }

    @Test func aurocAndRecallAtPrecision() {
        let words = [
            scored(0.1, wrong: true), scored(0.2, wrong: false), scored(0.3, wrong: true),
            scored(0.8, wrong: false), scored(0.9, wrong: false), scored(0.95, wrong: true),
        ]
        #expect(WordDoubtEvaluation.auroc(words) == 5.0 / 9.0)
        #expect(WordDoubtEvaluation.recall(words, atPrecision: 1) == 1.0 / 3.0)
        #expect(WordDoubtEvaluation.recall(words, atPrecision: 0.6) == 2.0 / 3.0)
        #expect(WordDoubtEvaluation.recall(words, atPrecision: 0.5) == 1)
        #expect(WordDoubtEvaluation.recall([scored(0.5, wrong: false)], atPrecision: 0.5) == 0)
        #expect(WordDoubtEvaluation.auroc([scored(0.5, wrong: false)]) == nil)
    }

    @Test func clusteredIntervalBracketsTheEstimateAndIsRepeatable() throws {
        let words = (0..<40).map { index in
            scored(Double(index % 10) / 10, wrong: index % 10 < 3, "voice\(index % 4)")
        }
        let first = try #require(
            WordDoubtEvaluation.clustered(words, resamples: 200) { WordDoubtEvaluation.auroc($0) })
        let again = try #require(
            WordDoubtEvaluation.clustered(words, resamples: 200) { WordDoubtEvaluation.auroc($0) })
        #expect(first == again)
        #expect(first.low <= first.value && first.value <= first.high)
        #expect(
            WordDoubtEvaluation.clustered([scored(0.5, wrong: false)]) { WordDoubtEvaluation.auroc($0) }
                == nil)
        var calls = 0
        let onlyWhole = WordDoubtEvaluation.clustered(words, resamples: 5) { _ -> Double? in
            calls += 1
            return calls == 1 ? 0.7 : nil
        }
        #expect(onlyWhole?.low == 0.7 && onlyWhole?.high == 0.7)
    }

    @Test func alignmentMarksOnlyTheWordsThatDifferFromTheReading() {
        let reference = ["meet", "me", "at", "noon"]
        #expect(WordDoubtAlignment.wrong(reference: reference, heard: ["meat", "me", "at", "noon"]) == [true, false, false, false])
        #expect(WordDoubtAlignment.wrong(reference: reference, heard: ["meet", "at", "noon"]) == [false, false, false])
        #expect(
            WordDoubtAlignment.wrong(reference: reference, heard: ["meet", "me", "uh", "at", "noon"])
                == [false, false, true, false, false])
        #expect(WordDoubtAlignment.wrong(reference: [], heard: ["so"]) == [true])
    }
}
