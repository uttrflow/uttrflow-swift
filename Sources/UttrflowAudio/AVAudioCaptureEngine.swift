// Owns the lifecycle of a microphone recording, without any audio machinery of its own.
public import UttrflowCore
private import Synchronization

/// Admits one recording's samples until it ends, so a callback still in flight at teardown lands nowhere.
private final class RecordingGate: Sendable {
    private let open = Mutex(true)

    /// Runs `body` only while the recording is live, holding the lock so `close()` waits for it to finish.
    func ifOpen(_ body: () -> Void) {
        open.withLock { if $0 { body() } }
    }

    func close() { open.withLock { $0 = false } }
}

/// Records the microphone into a canonical-format buffer, owning only the lifecycle, so its rules test dry.
public actor AVAudioCaptureEngine: AudioCaptureEngine {
    private enum Lifecycle {
        case idle
        case recording
        case stopping
        case cancelling
        case finishing
    }

    private let source: any MicrophoneSource
    private let accumulator: SampleAccumulator
    /// Where each recording is also written as it happens, when the app keeps them.
    private let recordings: RecordingStore?
    private var writer: RecordingWriter?
    /// The current recording's gate, closed the moment it stops or is cancelled.
    private var gate: RecordingGate?
    private var lifecycle: Lifecycle = .idle
    /// Cancellation requested while a draining stop owns the microphone shutdown.
    private var cancellationRequested = false
    /// Set when the microphone stops for good mid-recording, and thrown by `stop()` rather than half a recording.
    private var failure: AudioCaptureError?
    /// Where the microphone went during this recording, so the audio either side of each hole never joins.
    private var breaks: [Int] = []
    /// How many interruptions have reached the actor, so a test can wait for the hop instead of a clock.
    private(set) var interruptionsHandled = 0
    /// Counts `start()` calls, so an interruption reaching the actor late is applied only to its own recording.
    private var generation = 0
    /// Played the moment the microphone closes, since this engine alone knows that instant.
    private let cue: any RecordingCueing

    public init(
        source: any MicrophoneSource, accumulator: SampleAccumulator = SampleAccumulator(),
        recordings: RecordingStore? = nil, cue: any RecordingCueing = SilentCue()
    ) {
        self.source = source
        self.accumulator = accumulator
        self.recordings = recordings
        self.cue = cue
    }

    public var state: AudioCaptureState {
        switch lifecycle {
        case .idle: .idle
        case .recording: .recording
        case .stopping, .cancelling, .finishing: .stopping
        }
    }

    /// Loudest sample heard in the current recording, in `0...1`.
    public var peakLevel: Float { accumulator.peakLevel }

    /// How loud the microphone is now, in `0...1`; `nonisolated` so a meter never queues behind `stop()`.
    public nonisolated var momentaryLevel: Float { accumulator.momentaryLevel }

    /// Samples captured so far. Lets a caller show a duration while recording.
    public var capturedFrameCount: Int { accumulator.count }

    public func start() async throws(AudioCaptureError) {
        guard lifecycle == .idle else { throw .alreadyRecording }

        // Reset before starting, so a crash mid-recording cannot prepend audio to the next one.
        accumulator.reset()

        failure = nil
        breaks = []
        generation += 1
        let mine = generation
        let accumulator = self.accumulator
        let gate = RecordingGate()
        self.gate = gate
        // Started before the tap and without touching the disk, so the file holds every block the buffer does.
        let writer = await recordings?.begin()
        self.writer = writer
        do {
            try source.start { samples in
                gate.ifOpen {
                    accumulator.append(samples)
                    writer?.append(samples)
                }
            } onInterruption: { [weak self] interruption in
                let at = accumulator.count
                Task { await self?.microphoneInterrupted(interruption, in: mine, at: at) }
            }
        } catch {
            await abandonWriter()
            throw error
        }
        lifecycle = .recording
    }

    public func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard lifecycle == .recording else { throw .notRecording }
        lifecycle = .stopping
        // Drained, so the block the hardware was still filling at key-up reaches the buffer instead of being dropped.
        await source.stop(draining: true)
        closeGate()
        if cancellationRequested {
            accumulator.reset()
            failure = nil
            breaks = []
            await abandonWriter()
            cancellationRequested = false
            lifecycle = .idle
            throw .notRecording
        }
        lifecycle = .finishing
        // After the microphone closes and before the buffer is taken, so the stop cue is heard but never recorded.
        cue.playStop()
        if let writer, let recordings {
            _ = await recordings.finish(writer)
        }
        writer = nil
        let samples = accumulator.take()
        lifecycle = .idle
        // A microphone that died mid-recording captured only the first half, which reads as a whole sentence.
        let marked = breaks
        breaks = []
        if let failure {
            self.failure = nil
            throw failure
        }
        // A hole in the middle is marked, not refused, so the pieces either side are recognised apart.
        return .canonical(samples, discontinuities: marked)
    }

    /// Remembers what a device change did, since only `stop()` has somewhere to report it.
    private func microphoneInterrupted(
        _ interruption: CaptureInterruption, in recording: Int, at position: Int
    ) {
        interruptionsHandled += 1
        guard
            (lifecycle == .recording || lifecycle == .stopping),
            recording == generation
        else { return }
        switch interruption {
        case .began: breaks.append(position)
        case .ended(let error): failure = error
        }
    }

    /// Everything the microphone has delivered so far, so work can begin before the key is released.
    public func capturedSoFar() async -> AudioSamples {
        guard lifecycle == .recording else { return .empty }
        return .canonical(accumulator.snapshot, discontinuities: breaks)
    }

    /// What the microphone has delivered from sample `start` onwards, copying none of the audio before it.
    public func capturedSoFar(from start: Int) async -> AudioSamples {
        guard lifecycle == .recording else { return .empty }
        let from = Swift.max(0, start)
        return .canonical(accumulator.samples(from: from), discontinuities: breaks.map { $0 - from })
    }

    public func cancel() async {
        switch lifecycle {
        case .recording:
            lifecycle = .cancelling
        case .stopping:
            cancellationRequested = true
            return
        default:
            return
        }
        // Not drained: the audio is being thrown away, so waiting for more of it buys nothing.
        await source.stop(draining: false)
        closeGate()
        accumulator.reset()
        await abandonWriter()
        failure = nil
        breaks = []
        lifecycle = .idle
    }

    private func closeGate() {
        gate?.close()
        gate = nil
    }

    private func abandonWriter() async {
        guard let writer else { return }
        await recordings?.abandon(writer)
        self.writer = nil
    }
}
