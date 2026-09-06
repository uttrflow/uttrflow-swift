// Owns the lifecycle of a microphone recording, without any audio machinery of its own.
public import UttrflowCore

/// Records the microphone into a canonical-format buffer, owning only the lifecycle, so its rules test dry.
public actor AVAudioCaptureEngine: AudioCaptureEngine {
    private let source: any MicrophoneSource
    private let accumulator: SampleAccumulator
    /// Where each recording is also written as it happens, when the app keeps them.
    private let recordings: RecordingStore?
    private var writer: RecordingWriter?
    private var currentState: AudioCaptureState = .idle

    public init(
        source: any MicrophoneSource, accumulator: SampleAccumulator = SampleAccumulator(),
        recordings: RecordingStore? = nil
    ) {
        self.source = source
        self.accumulator = accumulator
        self.recordings = recordings
    }

    public var state: AudioCaptureState { currentState }

    /// Loudest sample heard in the current recording, in `0...1`.
    public var peakLevel: Float { accumulator.peakLevel }

    /// How loud the microphone is now, in `0...1`; `nonisolated` so a meter never queues behind `stop()`.
    public nonisolated var momentaryLevel: Float { accumulator.momentaryLevel }

    /// Samples captured so far. Lets a caller show a duration while recording.
    public var capturedFrameCount: Int { accumulator.count }

    public func start() async throws(AudioCaptureError) {
        guard currentState == .idle else { throw .alreadyRecording }

        // Reset before starting, so a crash mid-recording cannot prepend audio to the next one.
        accumulator.reset()

        let accumulator = self.accumulator
        // Opened before the tap, so the file holds every block the buffer does.
        let writer = await recordings?.begin()
        self.writer = writer
        do {
            try source.start { samples in
                accumulator.append(samples)
                writer?.append(samples)
            }
        } catch {
            await abandonWriter()
            throw error
        }
        currentState = .recording
    }

    public func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard currentState == .recording else { throw .notRecording }
        source.stop()
        currentState = .idle
        if let writer, let recordings {
            _ = await recordings.finish(writer)
        }
        writer = nil
        return .canonical(accumulator.take())
    }

    /// Everything the microphone has delivered so far, so work can begin before the key is released.
    public func capturedSoFar() async -> AudioSamples {
        guard currentState == .recording else { return .empty }
        return .canonical(accumulator.snapshot)
    }

    public func cancel() async {
        guard currentState == .recording else { return }
        source.stop()
        accumulator.reset()
        currentState = .idle
        await abandonWriter()
    }

    private func abandonWriter() async {
        guard let writer else { return }
        await recordings?.abandon(writer)
        self.writer = nil
    }
}
