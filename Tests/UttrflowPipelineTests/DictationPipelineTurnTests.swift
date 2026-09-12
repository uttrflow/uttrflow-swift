// Tests that one dictation holds the turn across every await, so a second gesture cannot slip in.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A microphone that closes at once but drains until the test lets it, as the real one does on a long recording.
private actor DrainingCaptureEngine: AudioCaptureEngine {
    private var current: AudioCaptureState = .idle
    private var draining: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private let failsAfterDraining: Bool
    private(set) var stops = 0

    init(failsAfterDraining: Bool = false) {
        self.failsAfterDraining = failsAfterDraining
    }

    var state: AudioCaptureState { current }

    func start() async throws(AudioCaptureError) {
        current = .recording
    }

    func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard current == .recording else { throw .notRecording }
        stops += 1
        // Closed before the drain, as the real engine is, so a second stop finds nothing to stop.
        current = .idle
        if !isReleased { await withCheckedContinuation { draining.append($0) } }
        if failsAfterDraining { throw .engineFailed(description: "the buffer was lost") }
        return .silence(seconds: 1)
    }

    func cancel() async {
        current = .idle
    }

    var isDraining: Bool { !draining.isEmpty }

    func release() {
        isReleased = true
        draining.forEach { $0.resume() }
        draining = []
    }
}

/// A keeper whose lookups wait until the test lets them finish, recording what it was told to delete.
private actor SlowRecordingKeeper: RecordingKeeper {
    enum Slow {
        /// The read of a recording's audio waits.
        case read
        /// The lookup of the recording just written waits.
        case lookup
    }

    private let slow: Slow
    private let recording: KeptRecording?
    private let readFails: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private(set) var discarded: [UUID] = []

    init(slow: Slow = .read, recording: KeptRecording? = nil, readFails: Bool = false) {
        self.slow = slow
        self.recording = recording
        self.readFails = readFails
    }

    func current() async -> KeptRecording? {
        if slow == .lookup { await hold() }
        return recording
    }

    func discard(_ id: UUID) {
        discarded.append(id)
    }

    func waiting(now: Date) -> [KeptRecording] { [] }

    func audio(of id: UUID) async throws(AudioCaptureError) -> AudioSamples {
        if slow == .read { await hold() }
        if readFails { throw .engineFailed(description: "the file is gone") }
        return .silence(seconds: 1)
    }

    private func hold() async {
        guard !isReleased else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    var isWaiting: Bool { !waiting.isEmpty }

    func release() {
        isReleased = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// A ``TranscriptCleaning`` that hands the words back untouched.
private struct TurnCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// A ``TextInserting`` that records every string it is handed.
private final class TurnInserter: TextInserting {
    private let log = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        log.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }

    var received: [String] { log.withLock { $0 } }
}

private let heard = "hello there"

private func makePipeline(
    capture: any AudioCaptureEngine,
    inserter: TurnInserter = TurnInserter(),
    recordings: any RecordingKeeper = RecordingsNotKept(),
    clipboard: TurnInserter? = nil
) -> DictationPipeline {
    DictationPipeline(
        capture: capture,
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: heard))),
        cleaner: TurnCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        recordings: recordings,
        clipboard: clipboard)
}

/// Waits until `condition` holds, recording a failure rather than hanging when it never does.
private func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<400 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("the condition never held")
}

// MARK: - Tests

@Suite("Dictation pipeline: one dictation holds the turn")
struct DictationPipelineTurnTests {
    @Test("a second stop while the microphone drains is refused, not reported as a failure")
    func secondStopDuringTheDrainIsRefused() async {
        let capture = DrainingCaptureEngine()
        let inserter = TurnInserter()
        let pipeline = makePipeline(capture: capture, inserter: inserter)
        await pipeline.startRecording()
        let first = Task { await pipeline.finishRecording() }
        await eventually { await capture.isDraining }

        await pipeline.finishRecording()

        #expect(await capture.stops == 1, "the second stop never reached the microphone")
        #expect(await pipeline.currentState == .recording, "still the first dictation, and not failed")
        await capture.release()
        await first.value
        #expect(inserter.received == [heard])
    }

    @Test("a dictation cannot open the microphone while a retry reads its recording")
    func noDictationUnderARetry() async {
        let capture = FakeAudioCaptureEngine()
        let keeper = SlowRecordingKeeper()
        let clipboard = TurnInserter()
        let pipeline = makePipeline(capture: capture, recordings: keeper, clipboard: clipboard)
        let retry = Task { await pipeline.retry(UUID()) }
        await eventually { await keeper.isWaiting }

        await pipeline.startRecording()

        #expect(await capture.calls.events.isEmpty, "the microphone stayed shut under the retry")
        await keeper.release()
        await retry.value
        #expect(clipboard.received == [heard])
        #expect(await pipeline.currentState.isListening == false)
    }

    @Test("a cancel while the microphone drains leaves the pipeline at rest, and keeps no recording")
    func cancelDuringTheDrainRests() async {
        let capture = DrainingCaptureEngine()
        let inserter = TurnInserter()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(1))
        let keeper = FakeRecordingKeeper(current: recording)
        let pipeline = makePipeline(capture: capture, inserter: inserter, recordings: keeper)
        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await eventually { await capture.isDraining }

        await pipeline.cancel()
        await capture.release()
        await finishing.value

        #expect(await pipeline.currentState == .idle, "not left transcribing a dictation nobody wants")
        #expect(inserter.received.isEmpty)
        #expect(await keeper.discarded == [recording.id])
    }

    @Test("a stop that fails after a cancel reports nothing over the cancel")
    func failedDrainAfterCancelRests() async {
        let capture = DrainingCaptureEngine(failsAfterDraining: true)
        let pipeline = makePipeline(capture: capture)
        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await eventually { await capture.isDraining }

        await pipeline.cancel()
        await capture.release()
        await finishing.value

        #expect(await pipeline.currentState == .idle)
    }

    @Test("a retry cancelled while its recording is read leaves the pipeline at rest")
    func cancelDuringARetryRests() async {
        let keeper = SlowRecordingKeeper()
        let clipboard = TurnInserter()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(), recordings: keeper, clipboard: clipboard)
        let retry = Task { await pipeline.retry(UUID()) }
        await eventually { await keeper.isWaiting }

        await pipeline.cancel()
        await keeper.release()
        await retry.value

        #expect(await pipeline.currentState == .idle)
        #expect(clipboard.received.isEmpty)
    }

    @Test("a retry whose read fails after a cancel reports nothing over the cancel")
    func failedReadAfterCancelRests() async {
        let keeper = SlowRecordingKeeper(readFails: true)
        let recording = UUID()
        let pipeline = makePipeline(capture: FakeAudioCaptureEngine(), recordings: keeper)
        let retry = Task { await pipeline.retry(recording) }
        await eventually { await keeper.isWaiting }

        await pipeline.cancel()
        await keeper.release()
        await retry.value

        #expect(await pipeline.currentState == .idle, "the cancel stands; the failure is not shown over it")
        #expect(await keeper.discarded == [recording], "an unreadable file is still not offered again")
    }

    @Test("a cancel while the recording is being looked up still deletes it")
    func cancelDuringTheLookupDeletes() async {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(1))
        let keeper = SlowRecordingKeeper(slow: .lookup, recording: recording)
        let inserter = TurnInserter()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(), inserter: inserter, recordings: keeper)
        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await eventually { await keeper.isWaiting }

        await pipeline.cancel()
        await keeper.release()
        await finishing.value

        #expect(await pipeline.currentState == .idle)
        #expect(inserter.received.isEmpty)
        #expect(await keeper.discarded == [recording.id], "not kept and offered for retry")
    }

    @Test("the turn is given back, so the next dictation starts after one finishes")
    func turnIsReleased() async {
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(capture: capture)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        await pipeline.acknowledge()
        await pipeline.startRecording()

        #expect(await pipeline.currentState == .recording)
        #expect(await capture.calls.events == [.start, .stop, .start])
    }
}
