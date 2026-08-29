/// What the recorder is doing right now.
public enum AudioCaptureState: Sendable, Equatable {
    case idle
    case recording
}

/// Captures microphone audio and hands back a canonical-format buffer.
///
/// `stop` returns the audio rather than pushing it through a delegate so that a
/// caller can await one recording without holding cross-call state.
public protocol AudioCaptureEngine: Sendable {
    var state: AudioCaptureState { get async }

    /// Begins recording. Throws ``AudioCaptureError/alreadyRecording`` if already active.
    func start() async throws(AudioCaptureError)

    /// Ends recording and returns everything captured, resampled to
    /// ``AudioSamples/canonicalSampleRate``.
    func stop() async throws(AudioCaptureError) -> AudioSamples

    /// Ends recording and discards the audio. Safe to call when idle.
    func cancel() async
}
