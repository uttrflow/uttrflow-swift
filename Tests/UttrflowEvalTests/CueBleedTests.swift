// Tests how a start cue is mixed into the head of a clip.
import Testing
import UttrflowEval

@Suite("CueBleed")
struct CueBleedTests {
    @Test func peakIsReadInDecibelsFullScale() {
        #expect(CueBleed.peakDecibels(of: [0, -1, 0.5]) == 0)
        #expect(abs(CueBleed.peakDecibels(of: [0.1]) + 20) < 1e-6)
        #expect(CueBleed.peakDecibels(of: [0, 0]) == -.infinity)
        #expect(CueBleed.peakDecibels(of: []) == -.infinity)
    }

    @Test func scalingMovesThePeakToTheTarget() {
        let scaled = CueBleed.scaled([0.2, -0.4, 0.1], toPeakDecibels: -11.5)
        #expect(abs(CueBleed.peakDecibels(of: scaled) + 11.5) < 1e-4)
        #expect(abs(scaled[0] / scaled[1] + 0.5) < 1e-6)
    }

    @Test func silenceIsNotScaled() {
        #expect(CueBleed.scaled([0, 0], toPeakDecibels: -6) == [0, 0])
    }

    @Test func theCueStartsAtTheFirstSampleAndTheSpeechAfterTheLead() {
        #expect(CueBleed.mixed(speech: [1, 1], lead: 1, cue: [0.5, 0.5]) == [0.5, 1.5, 1])
        #expect(CueBleed.mixed(speech: [1], lead: 0, cue: [0.5, 0.5, 0.5]) == [1.5, 0.5, 0.5])
        #expect(CueBleed.mixed(speech: [1], lead: -3, cue: []) == [1])
    }
}
