/// What the recorder is doing right now.
public enum AudioCaptureState: Sendable, Equatable {
    /// Not recording.
    case idle
    /// Recording.
    case recording
}

/// Captures microphone audio; `stop` returns the buffer, so a caller awaits one recording with no delegate.
public protocol AudioCaptureEngine: Sendable {
    /// Whether a recording is under way.
    var state: AudioCaptureState { get async }

    /// Begins recording. Throws ``AudioCaptureError/alreadyRecording`` if already active.
    func start() async throws(AudioCaptureError)

    /// Ends recording and returns everything captured, resampled to ``AudioSamples/canonicalSampleRate``.
    func stop() async throws(AudioCaptureError) -> AudioSamples

    /// Ends recording and discards the audio. Safe to call when idle.
    func cancel() async

    /// Everything captured so far, at the canonical rate, while a recording is under way.
    func capturedSoFar() async -> AudioSamples

    /// What has been captured from sample `start` onwards, at the canonical rate, while a recording is under way.
    func capturedSoFar(from start: Int) async -> AudioSamples
}

/// The default for engines that only hand audio over at `stop`.
extension AudioCaptureEngine {
    /// Answers nothing, for an engine that can only hand its audio over at `stop`.
    public func capturedSoFar() async -> AudioSamples { .empty }

    /// Cuts the whole of ``capturedSoFar()``, for an engine with no cheaper way to read from an offset.
    public func capturedSoFar(from start: Int) async -> AudioSamples {
        let all = await capturedSoFar()
        let from = Swift.min(Swift.max(0, start), all.samples.count)
        return AudioSamples(samples: Array(all.samples[from...]), sampleRate: all.sampleRate) ?? .empty
    }
}
