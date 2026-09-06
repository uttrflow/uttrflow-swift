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
}

/// The default for engines that only hand audio over at `stop`.
extension AudioCaptureEngine {
    /// Answers nothing, for an engine that can only hand its audio over at `stop`.
    public func capturedSoFar() async -> AudioSamples { .empty }
}
