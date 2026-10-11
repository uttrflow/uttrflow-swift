// Tests that a recording no key is holding finishes itself once the person falls quiet.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A ``HotkeyMonitoring`` that never fires, so a test drives the controller directly.
private final class StillMonitor: HotkeyMonitoring {
    let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream() }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() { continuation.finish() }
}

/// A phrase, then the quiet room around it.
private func take(speaking seconds: Double, thenQuietFor quiet: Double) -> AudioSamples {
    let rate = Double(AudioSamples.canonicalSampleRate)
    let phrase = (0..<Int(seconds * rate)).map { index in
        let time = Double(index) / rate
        return Float(0.3 * (0.7 + 0.3 * sin(2 * .pi * 3 * time)) * sin(2 * .pi * 180 * time))
    }
    let room = (0..<Int(quiet * rate)).map { $0.isMultiple(of: 2) ? Float(0.000_316) : -0.000_316 }
    return .canonical(phrase + room)
}

/// What the controller told the interface about the countdown, in order.
private final class CountdownLog: Sendable {
    private let state = Mutex((shown: [Int?](), warnings: [Int]()))
    var shown: [Int?] { state.withLock { $0.shown } }
    var warnings: [Int] { state.withLock { $0.warnings } }
    func show(_ secondsLeft: Int?) { state.withLock { $0.shown.append(secondsLeft) } }
    func warn(_ secondsLeft: Int) { state.withLock { $0.warnings.append(secondsLeft) } }
}

@Suite("Dictation controller: ending on silence", .timeLimit(.minutes(1)))
struct EndOnSilenceTests {
    private struct Rig {
        let clock = ManualClock()
        let capture: FakeAudioCaptureEngine
        let inserter = FakeTextInserter()
        let pipeline: DictationPipeline
        let controller: DictationController<ManualClock>
        let log = CountdownLog()

        init(_ activation: HotkeyActivation, endOnSilence seconds: Int?, heard: AudioSamples) {
            let log = log
            capture = FakeAudioCaptureEngine(stopOutcome: .success(heard))
            pipeline = DictationPipeline(
                capture: capture,
                speech: FakeSpeechEngine(transcribeOutcome: .success(Transcription(text: "said and done"))),
                cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(), inserter: inserter,
                // Its own clock, never moved, so a slow run reaches no stage limit.
                clock: ManualClock())
            controller = DictationController(
                dependencies: .init(
                    pipeline: pipeline,
                    monitor: StillMonitor()),
                clock: clock,
                options: .init(
                    activation: activation,
                    endOnSilence: seconds.flatMap(SilenceStop.init(seconds:))
                ),
                observers: .init(onSilenceCountdown: log.show, onSilenceWarning: log.warn)
            )
        }

        /// Starts a recording that has already heard `heard`.
        func start(_ heard: AudioSamples) async {
            await capture.setCaptured(heard)
            await controller.handle(.pressed)
        }

        /// Lets the silence checks run for `seconds`, one poll at a time.
        func listen(for seconds: Int) async {
            for _ in 0..<(seconds * 2) {
                await clock.advanceWhenSomethingIsWaiting(by: SilenceStop.poll)
                for _ in 0..<200 { await Task.yield() }
            }
        }

        /// Polls until the countdown has been reported `count` times, waiting real time for the analysis, for at most five seconds.
        func listen(untilReported count: Int) async {
            for _ in 0..<500 where log.shown.count < count {
                await clock.advanceWhenSomethingIsWaiting(by: SilenceStop.poll)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        /// Polls until the recording has stopped itself and its words have landed; nothing sleeps after the stop.
        func listenUntilInserted() async {
            while inserter.received.isEmpty, !Task.isCancelled {
                clock.advance(by: SilenceStop.poll)
                for _ in 0..<200 { await Task.yield() }
            }
        }
    }

    @Test("a press-to-toggle recording quiet for the wait stops and inserts what was said")
    func togglesOffOnSilence() async throws {
        let heard = take(speaking: 1, thenQuietFor: 2.5)
        let rig = Rig(.pressToToggle, endOnSilence: 2, heard: heard)
        await rig.start(heard)
        #expect(await rig.pipeline.currentState.isListening)

        await rig.listenUntilInserted()
        #expect(rig.inserter.received == ["said and done"])
        #expect(await rig.capture.calls.events == [.start, .stop])
    }

    @Test("a pause shorter than the wait leaves the microphone open")
    func shortPauseKeepsListening() async {
        let heard = take(speaking: 1, thenQuietFor: 1.5)
        let rig = Rig(.pressToToggle, endOnSilence: 2, heard: heard)
        await rig.start(heard)
        await rig.listen(for: 5)
        #expect(await rig.pipeline.currentState.isListening)
        #expect(rig.inserter.received.isEmpty)

        // The same checks stop it once the pause reaches the wait, so they were running all along.
        await rig.capture.appendCaptured(take(speaking: 0, thenQuietFor: 1))
        await rig.listenUntilInserted()
    }

    @Test("quiet before anything is said leaves the microphone open")
    func quietBeforeSpeechKeepsListening() async {
        let heard = take(speaking: 0, thenQuietFor: 6)
        let rig = Rig(.pressToToggle, endOnSilence: 2, heard: heard)
        await rig.start(heard)
        await rig.listen(for: 5)
        #expect(await rig.pipeline.currentState.isListening)

        await rig.capture.appendCaptured(take(speaking: 1, thenQuietFor: 2.5))
        await rig.listenUntilInserted()
    }

    @Test("switched off, quiet changes nothing")
    func offKeepsListening() async {
        let heard = take(speaking: 1, thenQuietFor: 9)
        let rig = Rig(.pressToToggle, endOnSilence: nil, heard: heard)
        await rig.start(heard)
        await rig.clock.advanceWhenSomethingIsWaiting(by: .seconds(5))
        for _ in 0..<1_000 { await Task.yield() }
        #expect(await rig.pipeline.currentState.isListening)
    }

    @Test("a held key is the stop gesture, so quiet under it changes nothing until the release")
    func heldKeyIsLeftToTheKey() async throws {
        let heard = take(speaking: 1, thenQuietFor: 2.5)
        let rig = Rig(.holdToTalk, endOnSilence: 2, heard: heard)
        await rig.start(heard)
        await rig.listen(for: 2)
        #expect(await rig.pipeline.currentState.isListening)

        await rig.controller.handle(.released)
        #expect(rig.inserter.received == ["said and done"])
    }

    @Test("a hands-free recording a double tap left open stops on silence too")
    func handsFreeStopsOnSilence() async {
        let heard = take(speaking: 1, thenQuietFor: 2.5)
        let rig = Rig(.holdToTalk, endOnSilence: 2, heard: heard)
        await rig.capture.setCaptured(heard)
        for _ in 0..<2 {
            await rig.controller.handle(.pressed)
            rig.clock.advance(by: DictationController<ManualClock>.minimumHold - .milliseconds(1))
            await rig.controller.handle(.released)
        }
        #expect(await rig.controller.currentStopGesture == .pressAgainHandsFree)

        await rig.listenUntilInserted()
        #expect(rig.inserter.received == ["said and done"])
        #expect(await rig.controller.currentStopGesture == .letGo)
    }

    @Test("escape during the wait discards the recording and nothing is inserted")
    func escapeAbandons() async throws {
        let heard = take(speaking: 1, thenQuietFor: 1)
        let rig = Rig(.pressToToggle, endOnSilence: 2, heard: heard)
        await rig.start(heard)
        await rig.controller.handle(.escapePressed)
        await rig.capture.setCaptured(take(speaking: 1, thenQuietFor: 3))
        rig.clock.advance(by: .seconds(3))
        for _ in 0..<1_000 { await Task.yield() }

        #expect(await rig.capture.calls.events == [.start, .cancel])
        #expect(rig.inserter.received.isEmpty)
    }

    @Test("the countdown starts past half the wait, is said once, and speech resets it")
    func countdownResetsOnSpeech() async {
        let heard = take(speaking: 1, thenQuietFor: 1.5)
        let rig = Rig(.pressToToggle, endOnSilence: 4, heard: heard)
        await rig.start(heard)
        await rig.listen(for: 2)
        #expect(rig.log.shown.isEmpty)

        await rig.capture.appendCaptured(take(speaking: 0, thenQuietFor: 1))
        await rig.listen(untilReported: 1)
        #expect(rig.log.shown == [2])
        #expect(rig.log.warnings == [2])

        await rig.capture.appendCaptured(take(speaking: 1, thenQuietFor: 0))
        await rig.listen(untilReported: 2)
        #expect(rig.log.shown == [2, nil])

        await rig.capture.appendCaptured(take(speaking: 0, thenQuietFor: 3))
        await rig.listen(untilReported: 3)
        #expect(rig.log.shown == [2, nil, 1])
        #expect(rig.log.warnings == [2, 1])
        #expect(await rig.pipeline.currentState.isListening)
    }

    @Test("the stop clears the countdown")
    func stopClearsTheCountdown() async {
        let heard = take(speaking: 1, thenQuietFor: 3)
        let rig = Rig(.pressToToggle, endOnSilence: 4, heard: heard)
        await rig.start(heard)
        await rig.listen(untilReported: 1)
        #expect(rig.log.shown == [1])

        await rig.listenUntilInserted()
        #expect(rig.log.shown.last == .some(nil))
    }

    @Test("escape clears the countdown")
    func escapeClearsTheCountdown() async {
        let heard = take(speaking: 1, thenQuietFor: 3)
        let rig = Rig(.pressToToggle, endOnSilence: 4, heard: heard)
        await rig.start(heard)
        await rig.listen(untilReported: 1)
        await rig.controller.handle(.escapePressed)
        #expect(rig.log.shown == [1, nil])
    }

    @Test("a press that stops the recording clears the countdown")
    func pressClearsTheCountdown() async {
        let heard = take(speaking: 1, thenQuietFor: 3)
        let rig = Rig(.pressToToggle, endOnSilence: 4, heard: heard)
        await rig.start(heard)
        await rig.listen(untilReported: 1)
        await rig.controller.handle(.pressed)
        #expect(rig.log.shown == [1, nil])
    }

    @Test("a held key shows no countdown, since only its release ends the recording")
    func heldKeyShowsNoCountdown() async {
        let heard = take(speaking: 1, thenQuietFor: 3)
        let rig = Rig(.holdToTalk, endOnSilence: 4, heard: heard)
        await rig.start(heard)
        await rig.listen(for: 2)
        #expect(rig.log.shown.isEmpty)
        #expect(rig.log.warnings.isEmpty)
    }
}
