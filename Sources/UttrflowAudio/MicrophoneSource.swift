public import UttrflowCore

/// A source of microphone audio, already converted to the canonical format.
///
/// Conversion happens behind this boundary so that everything above it deals in plain
/// `[Float]` — which is `Sendable`, unlike `AVAudioPCMBuffer`, and needs no hardware
/// to produce in a test.
public protocol MicrophoneSource: Sendable {
    /// Begins delivering samples at ``AudioSamples/canonicalSampleRate``, mono.
    ///
    /// - Parameter onSamples: Called repeatedly from the capture thread. Must be cheap.
    /// - Throws: ``AudioCaptureError/noInputDevice`` when there is no microphone,
    ///   ``AudioCaptureError/unsupportedInputFormat`` when its audio cannot be
    ///   converted, or ``AudioCaptureError/engineFailed(description:)`` when the
    ///   system refuses to start capturing.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError)

    /// Stops delivery. Safe to call when not started.
    func stop()
}
