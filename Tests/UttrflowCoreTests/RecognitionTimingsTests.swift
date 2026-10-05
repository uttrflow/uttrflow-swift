// Recognition timings add up across windows and retries without making a piece look effortful.
import Testing
import UttrflowCore

@Suite("Recognition timings")
struct RecognitionTimingsTests {
    private let window = RecognitionTimings(
        melSeconds: 0.02, encodeSeconds: 0.28, decoderSetupSeconds: 0.01, decodeSteps: 30,
        decodeSeconds: 0.3, wordTimingRuns: 1, wordTimingSeconds: 0.05, recognitionSeconds: 0.7)

    @Test("two windows sum every sub-stage and step count")
    func addingSums() {
        let both = window.adding(window)
        #expect(both.decodeSteps == 60)
        #expect(both.wordTimingRuns == 2)
        #expect(abs(both.encodeSeconds - 0.56) < 1e-9)
        #expect(abs(both.recognitionSeconds - 1.4) < 1e-9)
    }

    @Test("the unattributed share is what the named sub-stages leave of the total")
    func unattributed() {
        #expect(abs(window.unattributedSeconds - 0.04) < 1e-9)
    }

    @Test("a timed single decode is still plain, and retries carry their timings")
    func effortCarriesTimings() {
        let timed = DecodeEffort(encoderRuns: 1, timings: window)
        #expect(DecodeEffort(timings: window).isPlain)
        #expect(!DecodeEffort(fallbacks: 1, timings: window).isPlain)
        #expect(timed.adding(timed).timings == window.adding(window))
        #expect(timed.addingRetry(timed).timings == window.adding(window))
        #expect(timed.markingCapUnresolved().timings == window)
    }
}
