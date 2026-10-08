// Watches the live end of a recording for the quiet that ends it.
import UttrflowCore

extension DictationPipeline {
    /// Returns once the recording has been quiet for `stop`'s wait after speech, reading only its live end.
    func silence<C: Clock>(reaching stop: SilenceStop, on clock: C) async throws
    where C.Duration == Duration {
        let lookBack = stop.lookBack(atRate: AudioSamples.canonicalSampleRate)
        var heard = 0
        while true {
            try await clock.sleep(for: SilenceStop.poll)
            let from = Swift.max(0, heard - lookBack)
            let tail = await capture.capturedSoFar(from: from)
            heard = from + tail.samples.count
            if stop.isReached(in: tail.samples, sampleRate: tail.sampleRate) { return }
        }
    }
}
