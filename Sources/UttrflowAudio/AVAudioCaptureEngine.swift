public import UttrflowCore

/// Records the microphone into a canonical-format buffer.
///
/// Holds no audio machinery of its own: it owns the recording *lifecycle* and nothing
/// else, so every rule it enforces — you cannot start twice, you cannot stop what is
/// not running, a cancelled recording leaves nothing behind — is testable without a
/// microphone.
public actor AVAudioCaptureEngine: AudioCaptureEngine {
    private let source: any MicrophoneSource
    private let accumulator: SampleAccumulator
    private var currentState: AudioCaptureState = .idle

    public init(source: any MicrophoneSource, accumulator: SampleAccumulator = SampleAccumulator()) {
        self.source = source
        self.accumulator = accumulator
    }

    public var state: AudioCaptureState { currentState }

    /// Loudest sample heard in the current recording, in `0...1`.
    public var peakLevel: Float { accumulator.peakLevel }

    /// Samples captured so far. Lets a caller show a duration while recording.
    public var capturedFrameCount: Int { accumulator.count }

    public func start() async throws(AudioCaptureError) {
        guard currentState == .idle else { throw .alreadyRecording }

        // Reset before starting, not after stopping: a crash mid-recording must not
        // leave audio behind to be prepended to the next one.
        accumulator.reset()

        let accumulator = self.accumulator
        try source.start { samples in accumulator.append(samples) }
        currentState = .recording
    }

    public func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard currentState == .recording else { throw .notRecording }
        source.stop()
        currentState = .idle
        return .canonical(accumulator.take())
    }

    public func cancel() async {
        guard currentState == .recording else { return }
        source.stop()
        accumulator.reset()
        currentState = .idle
    }
}
