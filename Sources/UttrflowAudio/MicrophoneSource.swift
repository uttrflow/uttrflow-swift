// The seam behind which audio conversion and hardware are hidden from the pipeline.
public import UttrflowCore

/// What a device change did to a recording, since both outcomes leave the audio untrustworthy.
public enum CaptureInterruption: Sendable, Equatable {
    /// The device went, so the recording has a hole from here whatever happens next.
    case began
    /// The device did not come back, and the recording ends where it went.
    case ended(AudioCaptureError)
}

/// A source of microphone audio already converted to canonical `[Float]`, which needs no hardware in a test.
public protocol MicrophoneSource: Sendable {
    /// Begins delivering canonical mono samples from the capture thread, so `onSamples` must be cheap.
    func start(
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onInterruption: @escaping @Sendable (CaptureInterruption) -> Void
    ) throws(AudioCaptureError)

    /// Stops delivery. Safe to call when not started.
    func stop()
}

extension MicrophoneSource {
    /// Starts without watching for a device change, for a caller that only reads what arrives.
    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError) {
        try start(onSamples: onSamples, onInterruption: { _ in })
    }
}
