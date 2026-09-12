// Tests the capture engine's lifecycle rules without a microphone.
import Synchronization
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

    /// Half a sentence reads as a whole one, so the recording has to end as a failure rather than as audio.
    @Test("refuses to hand back a recording the microphone died in the middle of")
    func stopThrowsAfterTheMicrophoneDied() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit(Array(repeating: 0.5, count: 64))

        source.die()
        try await settle()

        await #expect(throws: AudioCaptureError.self) { _ = try await engine.stop() }
    }

    /// The other half of #170: the device came back, so the halves either side of the hole do not join.
    @Test("refuses a recording the microphone was away in the middle of")
    func stopThrowsAfterAGap() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit(Array(repeating: 0.5, count: 64))

        // Away, then back: samples resume into the same buffer with the missing span dropped.
        source.skip()
        source.emit(Array(repeating: 0.5, count: 64))
        try await settle()

        await #expect(throws: AudioCaptureError.self) { _ = try await engine.stop() }
    }

    @Test("a hole in one recording cannot fail the next one")
    func theGapDoesNotOutliveItsRecording() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.skip()
        try await settle()
        // Asserted, not discarded: a gap that stopped being refused would pass this test silently.
        await #expect(throws: AudioCaptureError.self) { _ = try await engine.stop() }

        try await engine.start()
        source.emit(Array(repeating: 0.25, count: 32))

        let audio = try await engine.stop()
        #expect(audio.samples.count == 32)
    }

    @Test("a microphone that died in one recording cannot fail the next one")
    func theFailureDoesNotOutliveItsRecording() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.die()
        try await settle()
        _ = try? await engine.stop()

        try await engine.start()
        source.emit(Array(repeating: 0.25, count: 32))

        let audio = try await engine.stop()
        #expect(audio.samples.count == 32)
    }

    /// The report crosses onto the actor, so the test has to let that hop happen.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(20))
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

@Suite("AVAudioCaptureEngine: audio before the stop")
struct AVAudioCaptureEngineSnapshotTests {
    @Test("shares what has arrived so far without disturbing the recording")
    func sharesAudioSoFar() async throws {
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source)
        try await engine.start()
        source.emit([0.1, 0.2])

        let early = await engine.capturedSoFar()
        source.emit([0.3])
        let all = try await engine.stop()

        #expect(early.samples == [0.1, 0.2])
        #expect(early.sampleRate == AudioSamples.canonicalSampleRate)
        #expect(all.samples == [0.1, 0.2, 0.3])
    }

    @Test("shares nothing while idle")
    func nothingWhileIdle() async {
        let engine = AVAudioCaptureEngine(source: FakeMicrophoneSource())
        #expect(await engine.capturedSoFar() == .empty)
    }
}

@Suite("AVAudioCaptureEngine: the stop cue")
struct AVAudioCaptureEngineCueTests {
    @Test("plays the stop cue once the microphone has closed, so none of it is recorded")
    func stopCueFollowsTheMicrophone() async throws {
        let source = FakeMicrophoneSource()
        let cue = MicrophoneWatchingCue(source: source)
        let engine = AVAudioCaptureEngine(source: source, cue: cue)
        try await engine.start()
        source.emit([0.1, 0.2])

        let audio = try await engine.stop()

        #expect(cue.stopsHeardWhileDelivering == [false], "one stop cue, after the microphone closed")
        #expect(audio.samples == [0.1, 0.2], "the recording is still handed over whole")
    }

    @Test("plays no stop cue for a recording that was cancelled")
    func noStopCueOnCancel() async throws {
        let source = FakeMicrophoneSource()
        let cue = MicrophoneWatchingCue(source: source)
        let engine = AVAudioCaptureEngine(source: source, cue: cue)
        try await engine.start()

        await engine.cancel()

        #expect(cue.stopsHeardWhileDelivering.isEmpty)
    }

    @Test("plays no stop cue when there is no recording to stop")
    func noStopCueWhenIdle() async {
        let source = FakeMicrophoneSource()
        let cue = MicrophoneWatchingCue(source: source)
        let engine = AVAudioCaptureEngine(source: source, cue: cue)

        await #expect(throws: AudioCaptureError.notRecording) { _ = try await engine.stop() }
        #expect(cue.stopsHeardWhileDelivering.isEmpty)
    }

    @Test("never plays the start cue, which waits until the pipeline is listening")
    func startCueIsNotTheEngines() async throws {
        let source = FakeMicrophoneSource()
        let cue = MicrophoneWatchingCue(source: source)
        let engine = AVAudioCaptureEngine(source: source, cue: cue)

        try await engine.start()
        _ = try await engine.stop()

        #expect(cue.starts == 0)
    }
}

/// A cue that notes, for every stop it plays, whether the microphone was still delivering.
private final class MicrophoneWatchingCue: RecordingCueing {
    private struct Log {
        var starts = 0
        var stops: [Bool] = []
    }

    private let source: FakeMicrophoneSource
    private let log = Mutex(Log())

    init(source: FakeMicrophoneSource) {
        self.source = source
    }

    func playStart() {
        log.withLock { $0.starts += 1 }
    }

    func playStop() {
        let delivering = source.isDelivering
        log.withLock { $0.stops.append(delivering) }
    }

    var starts: Int { log.withLock(\.starts) }
    var stopsHeardWhileDelivering: [Bool] { log.withLock(\.stops) }
}
