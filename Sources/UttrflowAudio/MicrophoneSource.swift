public import UttrflowCore

/// A source of microphone audio already converted to canonical `[Float]`, which needs no hardware in a test.
public protocol MicrophoneSource: Sendable {
    /// Begins delivering canonical mono samples from the capture thread, so `onSamples` must be cheap.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError)

    /// Stops delivery. Safe to call when not started.
    func stop()
}
