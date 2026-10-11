import Testing
import UttrflowEval

@Suite struct FinalPieceTests {
    @Test func aPauseLongerThanTheSentencePauseCutsBeforeTheKeyUp() {
        var words: [AlignedWord] = []
        for index in 0..<20 {
            let start = Double(index) * 0.4
            words.append(AlignedWord(word: "a", start: start, end: start + 0.3))
        }
        for index in 0..<10 {
            let start = 9.5 + Double(index) * 0.4
            words.append(AlignedWord(word: "b", start: start, end: start + 0.3))
        }
        let length = FinalPiece.length(of: words, keyUp: 13.6)
        #expect(length > 3 && length < 6)
    }

    @Test func speechWithNoCuttablePauseLeavesOnePieceUpToTheKeyUp() {
        var words: [AlignedWord] = []
        for index in 0..<30 {
            let start = Double(index) * 0.35
            words.append(AlignedWord(word: "a", start: start, end: start + 0.3))
        }
        #expect(abs(FinalPiece.length(of: words, keyUp: 10.5) - 10.5) < 0.05)
    }

    @Test func concatenationKeepsEachUtterancesTimingAndAddsTheGap() {
        let first = [AlignedWord(word: "a", start: 1, end: 2)]
        let second = [AlignedWord(word: "b", start: 5, end: 5.5)]
        let joined = FinalPiece.concatenate([first, second], gap: 0.5)
        #expect(
            joined == [AlignedWord(word: "a", start: 0, end: 1), AlignedWord(word: "b", start: 1.5, end: 2)])
        #expect(FinalPiece.keyUp(in: joined, after: 1.8) == 1.2)
        #expect(FinalPiece.keyUp(in: joined, after: 0.5) == nil)
    }

    @Test func percentileIsNearestRank() {
        #expect(FinalPiece.percentile([4, 1, 3, 2], 0.5) == 2)
        #expect(FinalPiece.percentile([4, 1, 3, 2], 0.95) == 4)
        #expect(FinalPiece.percentile([], 0.5) == nil)
    }

    @Test func aFluentSpeakerLeavesALongerFinalPieceThanOneWhoBreathes() {
        let fluent = FinalPiece.syntheticSpeaker(seconds: 60, pauses: 0.3...0.75, seed: 1)
        let breathing = FinalPiece.syntheticSpeaker(seconds: 60, pauses: 0.9...1.4, seed: 1)
        let fluentLength = FinalPiece.length(of: fluent, keyUp: FinalPiece.keyUp(in: fluent, after: 60) ?? 60)
        let breathingLength = FinalPiece.length(
            of: breathing, keyUp: FinalPiece.keyUp(in: breathing, after: 60) ?? 60)
        #expect(breathingLength < fluentLength)
        #expect(fluent.allSatisfy { $0.end > $0.start })
    }
}
