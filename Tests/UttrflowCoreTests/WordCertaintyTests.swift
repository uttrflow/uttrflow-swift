// Tests for the typed word certainty and its one conversion to the doubt gate's scale.

import Foundation
import Testing
@testable import UttrflowCore

@Suite("A word's certainty is typed by its source and reaches the gate only by explicit conversion")
struct WordCertaintyTests {
    @Test func decoderWordIsScoredFromItsTokensUnrounded() throws {
        let tokens = [TokenEvidence(logProb: log(0.4)), TokenEvidence(logProb: log(0.99))]
        let word = TranscribedWord(text: "there", confidence: 0.63, tokens: tokens)

        let certainty = try #require(DecoderCertainty(tokens: tokens))
        #expect(word.certainty == .decoder(certainty))
        #expect(abs(word.confidence - (0.4 * 0.99).squareRoot()) < 1e-12)
        #expect(word.confidence != 0.63)
    }

    @Test func engineValueWithoutTokensStaysReported() {
        let word = TranscribedWord(text: "there", confidence: 0.63)

        #expect(word.certainty == .reported(ReportedCertainty(probability: 0.63)))
        #expect(word.confidence == 0.63)
    }

    @Test func twoEnginesScoresMeetOnlyThroughTheExplicitConversion() throws {
        let decoder = try #require(DecoderCertainty(tokens: [TokenEvidence(logProb: log(0.5))]))
        let fromDecoder = WordCertainty.decoder(decoder)
        let fromEngine = WordCertainty.reported(ReportedCertainty(probability: 0.5))

        #expect(fromDecoder != fromEngine)
        #expect(abs(fromDecoder.gateConfidence - fromEngine.gateConfidence) < 1e-12)
    }

    @Test func negatedEntropyFallsWhenRunnersUpCrowdTheChosenToken() throws {
        let sure = try #require(DecoderCertainty(tokens: [TokenEvidence(logProb: log(0.9), alternatives: [log(0.01)])]))
        let torn = try #require(DecoderCertainty(tokens: [TokenEvidence(logProb: log(0.5), alternatives: [log(0.45)])]))

        #expect(sure.negatedEntropy > torn.negatedEntropy)
        #expect(DecoderCertainty(tokens: []) == nil)
    }
}
