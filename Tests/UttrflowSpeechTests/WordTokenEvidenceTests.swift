// Tests that each recognised word carries the decoder's score and runners-up for its own tokens.
import Testing
import WhisperKit

@testable import UttrflowCore
@testable import UttrflowSpeech

struct WordTokenEvidenceTests {
    @Test func eachWordTakesTheStepsOfItsOwnTokensInOrder() {
        let tokens = [50258, 7, 8, 9, 50257]
        let tokenLogProbs: [[Int: Float]] = [
            [50258: 0], [7: -0.1, 4: -2.5], [8: -0.7, 5: -0.9], [9: -0.2], [50257: 0],
        ]
        let words = [
            WordTiming(word: " meet", tokens: [7, 8], start: 0, end: 0.4, probability: 0.6),
            WordTiming(word: " me", tokens: [9], start: 0.4, end: 0.6, probability: 0.8),
        ]
        let evidence = tokenEvidence(of: words, tokens: tokens, tokenLogProbs: tokenLogProbs)
        #expect(
            evidence == [
                [
                    TokenEvidence(logProb: Double(Float(-0.1)), alternatives: [Double(Float(-2.5))]),
                    TokenEvidence(logProb: Double(Float(-0.7)), alternatives: [Double(Float(-0.9))]),
                ],
                [TokenEvidence(logProb: Double(Float(-0.2)))],
            ])
    }

    @Test func aTokenTheSegmentDidNotRecordGivesNoEvidence() {
        let words = [WordTiming(word: " so", tokens: [3], start: 0, end: 0.2, probability: 0.5)]
        #expect(tokenEvidence(of: words, tokens: [7], tokenLogProbs: [[7: -0.1]]) == [[]])
    }

    @Test func theRecognisedWordKeepsItsEvidenceIntoTheTranscription() {
        let tokens = [TokenEvidence(logProb: -0.3, alternatives: [-1.2])]
        let raw = RawTranscript(
            text: "hello",
            segments: [
                RawSegment(
                    text: "hello", start: 0, end: 1,
                    words: [RawWord(text: " hello", start: 0, end: 1, probability: 0.7, tokens: tokens)])
            ])
        let word = raw.transcription(audioDuration: .seconds(1)).segments.first?.words.first
        #expect(word?.tokens == tokens)
    }
}
