// The seam behind which audio conversion and hardware are hidden from the pipeline.
public import UttrflowCore

/// A source of microphone audio already converted to canonical `[Float]`, which needs no hardware in a test.
public protocol MicrophoneSource: Sendable {
    /// Begins delivering canonical mono samples from the capture thread, so `onSamples` must be cheap.
    func start(
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onFailure: @escaping @Sendable (AudioCaptureError) -> Void
    ) throws(AudioCaptureError)

    /// Stops delivery. Safe to call when not started.
    func stop()
}

extension MicrophoneSource {
    /// Starts without watching for the microphone dying, for a caller that only reads what arrives.
    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError) {
        try start(onSamples: onSamples, onFailure: { _ in })
    }
}
