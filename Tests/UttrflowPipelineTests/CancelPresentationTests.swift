// Tests what a cancelled recording says, sounds and keeps.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A monitor that never reports anything, so the test sends each command itself.
private final class SilentMonitor: HotkeyMonitoring {
    private let pair = AsyncStream<HotkeyEvent>.makeStream()
    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() {}
    var events: AsyncStream<HotkeyEvent> { pair.stream }
}

/// Counts the discarded cue, the one sound this suite is about.
private final class DiscardCueSpy: RecordingCueing {
    private let discards = Mutex(0)
    func playStart() {}
    func playStop() {}
    func playWarning() {}
    func playDiscarded() { discards.withLock { $0 += 1 } }
    var discardCount: Int { discards.withLock { $0 } }
}

private struct Rig {
    let pipeline: DictationPipeline
    let controller: DictationController<ManualClock>
    let capture: FakeAudioCaptureEngine
    let speech: FakeSpeechEngine
    let recordings: FakeRecordingKeeper
    let recording: KeptRecording
    let cue: DiscardCueSpy
    let clock: ManualClock
    let audio: AudioSamples
}

private func makeRig(screen: AppContext = .fixture()) -> Rig {
    let audio = AudioSamples.silence(seconds: 3)
    let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(90))
    let recordings = FakeRecordingKeeper(current: recording, audioOutcome: .success(audio))
    let capture = FakeAudioCaptureEngine()
    let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "hello there")))
    let clock = ManualClock()
    let pipeline = DictationPipeline(
        capture: capture, speech: speech, cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: screen), inserter: FakeTextInserter(),
        recordings: recordings, clipboard: FakeTextInserter(.success(InsertionAttempt(.clipboard))),
        clock: clock, earlyPoll: .seconds(600))
    let cue = DiscardCueSpy()
    let controller = DictationController(
        pipeline: pipeline, monitor: SilentMonitor(), cue: cue, clock: ManualClock())
    return Rig(
        pipeline: pipeline, controller: controller, capture: capture, speech: speech,
        recordings: recordings, recording: recording, cue: cue, clock: clock, audio: audio)
}

/// Starts a recording, lets `length` pass on the pipeline's clock, then cancels it as Escape does.
private func cancel(after length: Duration, on rig: Rig) async throws {
    #expect(await rig.controller.command(.start) == .started)
    try await eventually { await rig.pipeline.earlyReadsSettled == 1 }
    rig.clock.advance(by: length)
    #expect(await rig.controller.command(.cancel) == .cancelled)
}

extension DictationState {
    fileprivate var discard: DictationDiscard? {
        if case .discarded(let discard) = self { discard } else { nil }
    }
}

@Suite("Cancelling a recording: the line, the cue and Restore")
struct CancelPresentationTests {
    @Test("a cancel of a 2 s hold shows nothing, sounds nothing and keeps nothing")
    func shortCancelIsSilent() async throws {
        let rig = makeRig()

        try await cancel(after: .seconds(2), on: rig)

        #expect(await rig.pipeline.currentState == .idle)
        #expect(rig.cue.discardCount == 0)
        #expect(await rig.capture.calls.events == [.start, .cancel])
        #expect(DictationPresenter.announcement(for: await rig.pipeline.currentState) == nil)
    }

    @Test("a cancel of a 90 s recording shows the line, sounds the cue once and offers Restore")
    func longCancelIsPresented() async throws {
        let rig = makeRig()

        try await cancel(after: .seconds(90), on: rig)

        let state = await rig.pipeline.currentState
        let discard = try #require(state.discard)
        #expect(discard.spokenFor == .seconds(90))
        #expect(discard.keptRecording == rig.recording.id)
        #expect(rig.cue.discardCount == 1)
        #expect(await rig.capture.calls.events == [.start, .cancelKeepingRecording])
        let dock = DictationPresenter.dock(for: state)
        #expect(dock.primaryLine == "Discarded")
        #expect(dock.action == .restoreRecording)
        let spoken = try #require(DictationPresenter.announcement(for: state))
        #expect(spoken.text.hasPrefix("Discarded."))
        #expect(!spoken.isUrgent)
        #expect(await rig.recordings.discarded.isEmpty)
    }

    @Test("Restore inside the window decodes the same samples and keeps the file from the expiry")
    func restoreDecodesTheSameSamples() async throws {
        let rig = makeRig()
        try await cancel(after: .seconds(90), on: rig)

        #expect(await rig.pipeline.retry(rig.recording.id))

        #expect(await rig.recordings.audioRequests == [rig.recording.id])
        #expect(await rig.speech.transcribeCalls.last?.audio == rig.audio)
        // The words landed, so the retry itself deletes the file; the window must not delete it again.
        rig.clock.advance(by: DictationPipeline.restoreWindow)
        await Task.yield()
        #expect(await rig.recordings.discarded == [rig.recording.id])
    }

    @Test("after the window the file is deleted, the store lists nothing and the line comes down")
    func windowCloses() async throws {
        let rig = makeRig()
        try await cancel(after: .seconds(90), on: rig)

        await rig.clock.advanceWhenSomethingIsWaiting(by: DictationPipeline.restoreWindow)

        try await eventually { await rig.recordings.discarded == [rig.recording.id] }
        try await eventually { await rig.pipeline.currentState == .idle }
        #expect(await rig.recordings.waiting(now: Date()).isEmpty)
    }

    @Test("a secure-field destination never offers Restore and deletes the audio at once")
    func secureFieldNeverRestores() async throws {
        let rig = makeRig(screen: .fixture(applicationName: "Keychain Access", isSecure: true))

        try await cancel(after: .seconds(90), on: rig)

        let state = await rig.pipeline.currentState
        let discard = try #require(state.discard)
        #expect(discard.keptRecording == nil)
        #expect(DictationPresenter.dock(for: state).action == nil)
        #expect(await rig.recordings.discarded == [rig.recording.id])
    }
}
