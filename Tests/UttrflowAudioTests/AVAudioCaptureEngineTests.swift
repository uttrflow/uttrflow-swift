import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("AVAudioCaptureEngine")
struct AVAudioCaptureEngineTests {
    @Test("starts idle")
    func startsIdle() async {
        let engine = AVAudioCaptureEngine(source: FakeMicrophoneSource())
        #expect(await engine.state == .idle)
    }

    @Test("begins delivering samples when started")
    func startBeginsDelivery() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)

        try await engine.start()

        #expect(await engine.state == .recording)
        #expect(source.startCount == 1)
        #expect(source.isDelivering)
    }

    @Test("refuses a second start rather than losing the first recording")
    func doubleStartThrows() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()

        await #expect(throws: AudioCaptureError.alreadyRecording) { try await engine.start() }
        #expect(source.startCount == 1, "the running recording must not be restarted")
    }

    @Test("stays idle when the microphone will not start")
    func failedStartLeavesEngineIdle() async {
        let source = FakeMicrophoneSource(startError: .noInputDevice)
        let engine = AVAudioCaptureEngine(source: source)

        await #expect(throws: AudioCaptureError.noInputDevice) { try await engine.start() }
        #expect(await engine.state == .idle, "a failed start must be retryable")
    }

    @Test("returns everything captured, at the canonical rate")
    func stopReturnsCapturedAudio() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit([0.1, 0.2])
        source.emit([0.3])

        let audio = try await engine.stop()

        #expect(audio.samples == [0.1, 0.2, 0.3])
        #expect(audio.sampleRate == AudioSamples.canonicalSampleRate)
        #expect(await engine.state == .idle)
        #expect(source.stopCount == 1)
    }

    @Test("returns an empty buffer when nothing was heard")
    func stopWithNoAudio() async throws {
        let engine = AVAudioCaptureEngine(source: FakeMicrophoneSource())
        try await engine.start()

        let audio = try await engine.stop()
        #expect(audio.isEmpty)
        #expect(audio.duration == .zero)
    }

    @Test("refuses to stop what is not running")
    func stopWhenIdleThrows() async {
        let engine = AVAudioCaptureEngine(source: FakeMicrophoneSource())
        await #expect(throws: AudioCaptureError.notRecording) { _ = try await engine.stop() }
    }

    @Test("throws away the audio when cancelled")
    func cancelDiscardsAudio() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit([0.4, 0.5])

        await engine.cancel()

        #expect(await engine.state == .idle)
        #expect(await engine.capturedFrameCount == 0)
        #expect(source.stopCount == 1)
    }

    @Test("does nothing when cancelled while idle")
    func cancelWhenIdleIsSafe() async {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)

        await engine.cancel()

        #expect(await engine.state == .idle)
        #expect(source.stopCount == 0, "there is nothing to stop")
    }

    @Test("never prepends the previous recording to the next one")
    func consecutiveRecordingsDoNotBleed() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)

        try await engine.start()
        source.emit([0.1])
        _ = try await engine.stop()

        try await engine.start()
        source.emit([0.9])
        let second = try await engine.stop()

        #expect(second.samples == [0.9])
    }

    @Test("ignores samples arriving after the recording has stopped")
    func samplesAfterStopAreDropped() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        _ = try await engine.stop()

        source.emit([0.7])

        #expect(await engine.capturedFrameCount == 0)
    }

    @Test("reports level and length while still recording")
    func reportsProgressDuringRecording() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit([0.2, -0.6, 0.1])

        #expect(await engine.peakLevel == 0.6)
        #expect(await engine.capturedFrameCount == 3)
    }
}
