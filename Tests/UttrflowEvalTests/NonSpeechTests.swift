// Tests the non-speech corpus generators and the insertion and loop scoring.
import Testing
import UttrflowCore
import UttrflowEval

@Suite("NonSpeech")
struct NonSpeechTests {
    @Test func everyKindIsRepeatableAndTheRequestedLength() {
        for kind in NonSpeechKind.allCases {
            let first = kind.samples(seconds: 1, seed: 7)
            #expect(first.count == AudioSamples.canonicalSampleRate)
            #expect(first == kind.samples(seconds: 1, seed: 7))
        }
    }

    @Test func levelsSitWhereTheKindSaysTheyDo() {
        #expect(NonSpeechSound.rmsDecibels(of: NonSpeechKind.silence.samples(seed: 0)) == -.infinity)
        #expect(abs(NonSpeechSound.rmsDecibels(of: NonSpeechKind.roomTone.samples(seed: 0)) + 60) < 0.01)
        #expect(abs(NonSpeechSound.rmsDecibels(of: NonSpeechKind.hiss.samples(seed: 0)) + 30) < 0.01)
        #expect(abs(NonSpeechSound.rmsDecibels(of: NonSpeechKind.music.samples(seed: 0)) + 20) < 0.01)
        #expect(NonSpeechKind.keyboard.samples(seed: 0).contains { abs($0) > 0.05 })
    }

    @Test func seedsDiffer() {
        #expect(
            NonSpeechKind.hiss.samples(seconds: 0.1, seed: 1)
                != NonSpeechKind.hiss.samples(seconds: 0.1, seed: 2))
    }

    @Test func anyWordFromANonSpeechClipIsAnInsertion() {
        #expect(NonSpeechScore(reference: [], hypothesis: []).insertedWords == 0)
        #expect(NonSpeechScore(reference: [], hypothesis: ["thank", "you"]).insertedWords == 2)
    }

    @Test func onlyWordsAfterTheLastSpokenWordAreTrailingInsertions() {
        let said = ["send", "the", "draft"]
        #expect(NonSpeechScore(reference: said, hypothesis: said).insertedWords == 0)
        #expect(NonSpeechScore(reference: said, hypothesis: said + ["thank", "you"]).insertedWords == 2)
        #expect(NonSpeechScore(reference: said, hypothesis: ["please"] + said).insertedWords == 0)
        #expect(NonSpeechScore(reference: said, hypothesis: ["send", "draft"]).insertedWords == 0)
    }

    @Test func aPhraseThreeTimesInARowIsALoop() {
        let phrase = ["see", "you", "soon"]
        #expect(NonSpeechScore(reference: [], hypothesis: ["so"] + phrase + phrase + phrase).looped)
        #expect(!NonSpeechScore(reference: [], hypothesis: phrase + phrase).looped)
        #expect(!NonSpeechScore(reference: [], hypothesis: ["no", "no", "no", "no", "no", "no"]).looped)
        #expect(!NonSpeechScore(reference: [], hypothesis: phrase + ["then"] + phrase + phrase).looped)
    }

    @Test func ratesCountClipsAndTheGateNamesWhatFailed() {
        let clean = NonSpeechScore(reference: [], hypothesis: [])
        let invented = NonSpeechScore(reference: [], hypothesis: ["thank", "you"])
        let rates = NonSpeechRates([clean, clean, clean, invented])
        #expect(rates.insertionRate == 0.25)
        #expect(rates.loopRate == 0)
        #expect(rates.exceeded(insertionCeiling: 0, loopCeiling: 0) == ["insertion rate"])
        #expect(rates.exceeded(insertionCeiling: 0.25, loopCeiling: 0).isEmpty)
        #expect(NonSpeechRates([]).insertionRate == 0)
    }
}
