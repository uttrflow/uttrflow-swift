// Tests the dictation length limit's wiring through the controller.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A ``HotkeyMonitoring`` that never fires, so a test drives the controller directly.
private final class SilentMonitor: HotkeyMonitoring {
    let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream() }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() { continuation.finish() }
}

/// A ``TranscriptCleaning`` that answers at once.
private struct QuietCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// Holds recognition so another hands-free dictation can arrive while the first is transcribing.
private final class GatedSpeechEngine: SpeechEngine {
    private struct State {
        var calls = 0
        var held: CheckedContinuation<Void, Never>?
        var released = false
    }

    private let state = Mutex(State())

    var kind: SpeechEngineKind { .whisperKit }
    func prepare() async throws(SpeechEngineError) {}
    func warm() async {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                state.calls += 1
                guard state.calls == 1, !state.released else { return true }
                state.held = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
        return Transcription(text: "a long dictation")
    }

    var isHolding: Bool { state.withLock { $0.held != nil } }
    func release() {
        let held = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }
}

/// Records each cue the cap timer asks the recording controller to play.
private final class LimitCue: RecordingCueing {
    private let warnings = Mutex(0)

    func playStart() {}
    func playStop() {}
    func playWarning() { warnings.withLock { $0 += 1 } }
    func playDiscarded() {}

    var warningCount: Int { warnings.withLock { $0 } }
}

/// A ``TextInserting`` that records what reached the screen, holding every insertion while it is shut.
private final class QuietInserter: TextInserting, Sendable {
    private struct State {
        var placed: [String] = []
        var isShut = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await withCheckedContinuation { go in
            let proceed = state.withLock { state -> Bool in
                guard state.isShut else { return true }
                state.waiting.append(go)
                return false
            }
            if proceed { go.resume() }
        }
        state.withLock { $0.placed.append(text) }
        return InsertionAttempt(.accessibility)
    }

    /// Holds every insertion from now until ``open()``.
    func shut() { state.withLock { $0.isShut = true } }

    /// Lets every held and later insertion through.
    func open() {
        let waiting = state.withLock { state in
            state.isShut = false
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    var inserted: [String] { state.withLock { $0.placed } }
}

/// A ``VocabularyLearning`` that holds the first dictation's learning until it is let go.
private final class GatedLearner: VocabularyLearning {
    private struct State {
        var calls = 0
        var held: CheckedContinuation<Void, Never>?
        var released = false
    }

    private let state = Mutex(State())

    func learn(heard: String, wrote: String, seeing context: AppContext) async throws(DictationChangeError) {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                state.calls += 1
                guard state.calls == 1, !state.released else { return true }
                state.held = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    /// Whether the first dictation is held inside its learning step.
    var isHolding: Bool { state.withLock { $0.held != nil } }

    /// Lets the held learning step finish.
    func release() {
        let held = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }
}

@Suite("Dictation controller: the soft cap on a long recording", .timeLimit(.minutes(1)))
struct DictationLimitWiringTests {
    private static let limit = DictationLimit(warnAfter: .seconds(180), stopAfter: .seconds(240))

    private func makeController(
        clock: ManualClock, inserter: QuietInserter, cue: any RecordingCueing = SilentCue(),
        advice: @escaping @Sendable (DictationAdvice) -> Void = { _ in },
        warning: @escaping @Sendable (DictationAdvice) -> Void = { _ in }
    ) -> DictationController<ManualClock> {
        DictationController(
            pipeline: DictationPipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 200))),
                speech: FakeSpeechEngine(
                    transcribeOutcome: .success(Transcription(text: "a long dictation"))),
                cleaner: QuietCleaner(),
                context: FakeContextEngine(),
                inserter: inserter,
                // A real clock here, so the manual one carries only the cap's own sleepers.
                clock: ContinuousClock()),
            monitor: SilentMonitor(),
            cue: cue,
            activation: .holdToTalk,
            clock: clock,
            limit: Self.limit,
            onAdvice: advice,
            onWarning: warning)
    }

    private func makeGatedHandsFreeController(
        clock: ManualClock, inserter: QuietInserter, speech: GatedSpeechEngine
    ) -> DictationController<ManualClock> {
        DictationController(
            pipeline: DictationPipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 200))),
                speech: speech,
                cleaner: QuietCleaner(),
                context: FakeContextEngine(),
                inserter: inserter,
                clock: ContinuousClock()),
            monitor: SilentMonitor(),
            activation: .holdToTalk,
            clock: clock,
            limit: Self.limit)
    }

    /// Lets the clock reach `deadline`, once something is actually waiting for it.
    private func advance(_ clock: ManualClock, to deadline: Duration) async {
        await clock.advanceWhenSomethingIsWaiting(by: deadline)
    }

    @Test("warns a minute before the cap rather than cutting the speaker off")
    func warnsBeforeTheCap() async throws {
        let clock = ManualClock()
        let cue = LimitCue()
        let announcements = Mutex<[DictationAnnouncement]>([])
        let heard = Mutex<[DictationAdvice]>([])
        let reporter = DictationWarningReporter(cue: cue) { announcement in
            announcements.withLock { $0.append(announcement) }
        }
        let controller = makeController(
            clock: clock, inserter: QuietInserter(), cue: cue,
            advice: { advice in heard.withLock { $0.append(advice) } },
            warning: reporter.report)

        await controller.handle(.pressed)
        #expect(cue.warningCount == 0)
        #expect(announcements.withLock { $0 }.isEmpty)
        await advance(clock, to: Self.limit.warnAfter)
        try await eventually { !heard.withLock { $0.isEmpty } }

        #expect(heard.withLock { $0.first } == .approaching(remaining: .seconds(60)))
        #expect(cue.warningCount == 1)
        #expect(
            announcements.withLock { $0 }
                == [DictationAnnouncement(text: "Dictation ends soon. 1 min left.", isUrgent: false)])
    }

    @Test("plays one warning cue and announces it once at warnAfter")
    func warningCueAndAnnouncementHappenOnce() async throws {
        let clock = ManualClock()
        let cue = LimitCue()
        let announcements = Mutex<[DictationAnnouncement]>([])
        let reporter = DictationWarningReporter(cue: cue) { announcement in
            announcements.withLock { $0.append(announcement) }
        }
        let controller = makeController(
            clock: clock, inserter: QuietInserter(), cue: cue, warning: reporter.report)

        await controller.handle(.pressed)
        await advance(clock, to: Self.limit.warnAfter)
        try await eventually { cue.warningCount == 1 && !announcements.withLock { $0.isEmpty } }
        await advance(clock, to: .seconds(30))

        #expect(cue.warningCount == 1)
        #expect(
            announcements.withLock { $0 }
                == [DictationAnnouncement(text: "Dictation ends soon. 1 min left.", isUrgent: false)])
    }

    @Test("finishes the dictation at the cap, keeping every word of it")
    func finishesAtTheCap() async throws {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let saw = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: inserter) { advice in
            saw.withLock { $0.append(advice) }
        }

        await controller.handle(.pressed)
        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)

        try await eventually { !inserter.inserted.isEmpty }
        // Kept, not discarded: a cap that threw the audio away would be worse than none.
        #expect(inserter.inserted == ["a long dictation"])
        #expect(saw.withLock { $0.contains(.finishNow) })
    }

    @Test("counts the last minute down every ten seconds, then finishes")
    func countsDownBeforeTheCap() async {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let saw = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: inserter) { advice in
            saw.withLock { $0.append(advice) }
        }

        await controller.handle(.pressed)
        await advance(clock, to: Self.limit.warnAfter)
        for _ in 0..<6 { await advance(clock, to: .seconds(10)) }
        while inserter.inserted.isEmpty { await Task.yield() }

        let said = saw.withLock { $0 }
        let countdown = said.compactMap { advice -> Int? in
            guard case .approaching(let remaining) = advice else { return nil }
            return Int(remaining.components.seconds)
        }
        #expect(countdown == [60, 50, 40, 30, 20, 10])
        // The cap comes after the last warning, not instead of it.
        #expect(said.last { $0 != .keepGoing } == .finishNow)
        #expect(
            countdown.map { RemainingTime.phrase(for: .approaching(remaining: .seconds($0))) } == [
                "1 min left", "50 sec left", "40 sec left", "30 sec left", "20 sec left", "10 sec left",
            ])
    }

    /// Two taps inside the slip threshold, which open or close a hands-free dictation.
    private func doubleTap(_ controller: DictationController<ManualClock>, clock: ManualClock) async {
        for _ in 0..<2 {
            await controller.handle(.pressed)
            clock.advance(by: DictationController<ManualClock>.minimumHold - .milliseconds(1))
            await controller.handle(.released)
        }
    }

    /// Leaves a double-tap dictation listening, then lets it run to the cap and waits until its words have landed.
    private func runHandsFreeToTheCap(
        _ controller: DictationController<ManualClock>, clock: ManualClock,
        finished: () -> Bool
    ) async {
        await doubleTap(controller, clock: clock)
        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)
        while !finished() { await Task.yield() }
        // A press made while the capped dictation is still processing is refused, so the test waits it out.
        await controller.drained()
    }

    /// Whether the cap's finish has run to its end, which it marks by standing the advice down.
    private static func capFinished(_ advice: [DictationAdvice]) -> Bool {
        guard let finish = advice.firstIndex(of: .finishNow) else { return false }
        return advice[finish...].contains(.keepGoing)
    }

    @Test("a double-tap dictation finished at the cap leaves the hold working")
    func holdWorksAfterHandsFreeReachesTheCap() async {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let heard = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: inserter) { advice in
            heard.withLock { $0.append(advice) }
        }
        await runHandsFreeToTheCap(controller, clock: clock) {
            heard.withLock { Self.capFinished($0) }
        }

        await controller.handle(.pressed)
        clock.advance(by: .seconds(5))
        await controller.handle(.released)

        #expect(inserter.inserted == ["a long dictation", "a long dictation"])
    }

    @Test("a double tap during capped transcription starts another dictation")
    func doubleTapDuringCappedTranscriptionStartsAnotherDictation() async throws {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let speech = GatedSpeechEngine()
        let controller = makeGatedHandsFreeController(clock: clock, inserter: inserter, speech: speech)
        await doubleTap(controller, clock: clock)
        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)
        try await eventually { speech.isHolding }

        for _ in 0..<2 {
            controller.submit(.pressed)
            clock.advance(by: DictationController<ManualClock>.minimumHold - .milliseconds(1))
            controller.submit(.released)
        }
        await controller.drained()
        #expect(await controller.currentStopGesture == .pressAgainHandsFree)

        speech.release()
        clock.advance(by: .seconds(2))
        await doubleTap(controller, clock: clock)

        try await eventually { inserter.inserted.count == 2 }
        #expect(inserter.inserted == ["a long dictation", "a long dictation"])
    }

    /// A press-to-toggle controller whose first dictation is held in its learning step until released.
    private func makeToggleController(
        clock: ManualClock, inserter: QuietInserter, learner: any VocabularyLearning, limit: DictationLimit
    ) -> DictationController<ManualClock> {
        DictationController(
            pipeline: DictationPipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 200))),
                speech: FakeSpeechEngine(
                    transcribeOutcome: .success(Transcription(text: "a long dictation"))),
                cleaner: QuietCleaner(),
                context: FakeContextEngine(context: .fixture()),
                inserter: inserter,
                vocabulary: learner,
                clock: ContinuousClock()),
            monitor: SilentMonitor(),
            activation: .pressToToggle,
            clock: clock,
            limit: limit)
    }

    @Test(
        "a press made while the cap is still finishing waits its turn, and the next dictation keeps its own cap"
    )
    func nextDictationKeepsItsCapWhileTheLastFinishes() async throws {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let learner = GatedLearner()
        let controller = makeToggleController(
            clock: clock, inserter: inserter, learner: learner, limit: Self.limit)

        controller.submit(.pressed)
        await controller.drained()
        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)
        try await eventually { learner.isHolding }

        // Pressed while the capped dictation is still learning, which a cap outside the queue let through.
        controller.submit(.pressed)
        for _ in 0..<1_000 { await Task.yield() }
        learner.release()
        await controller.drained()
        #expect(inserter.inserted == ["a long dictation"])

        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)
        try await eventually { inserter.inserted.count == 2 }
        #expect(inserter.inserted == ["a long dictation", "a long dictation"])
    }

    @Test("a cap reached as its dictation was stopped ends nothing, and the next keeps its own")
    func staleCapLeavesTheNextDictationAlone() async throws {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let limit = DictationLimit(warnAfter: .seconds(240), stopAfter: .seconds(240))
        let controller = makeToggleController(
            clock: clock, inserter: inserter, learner: NoTextChanges(), limit: limit)

        controller.submit(.pressed)
        await controller.drained()
        await clock.waitUntilSomethingIsWaiting()

        // Stop, press again while the words are held, and reach the first dictation's cap, all before the queue has handled any of it.
        inserter.shut()
        controller.submit(.pressed)
        controller.submit(.pressed)
        clock.advance(by: limit.stopAfter)
        await controller.caughtUp()
        for _ in 0..<1_000 { await Task.yield() }
        await controller.caughtUp()
        inserter.open()
        await controller.drained()
        #expect(inserter.inserted == ["a long dictation"])

        controller.submit(.pressed)
        await controller.caughtUp()
        await advance(clock, to: limit.stopAfter)
        try await eventually { inserter.inserted.count == 2 }
        #expect(inserter.inserted == ["a long dictation", "a long dictation"])
    }

    @Test("says nothing about a limit for a dictation that ends normally")
    func ordinaryDictationIsUnaffected() async {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let heard = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: inserter) { advice in
            heard.withLock { $0.append(advice) }
        }

        await controller.handle(.pressed)
        clock.advance(by: .seconds(5))
        await controller.handle(.released)

        #expect(inserter.inserted == ["a long dictation"])
        #expect(heard.withLock { $0.allSatisfy { $0 == .keepGoing } })
    }
}

@Suite("When a recording is told how long it has left")
struct DictationLimitCountdownTests {
    @Test("says it at the warning and every ten seconds after, never at the cap")
    func countdown() {
        let limit = DictationLimit(warnAfter: .seconds(180), stopAfter: .seconds(240))
        #expect(limit.countdown == [180, 190, 200, 210, 220, 230].map { .seconds($0) })
    }

    @Test("says nothing when the warning would come at or after the cap")
    func noRoomToWarn() {
        #expect(DictationLimit(warnAfter: .seconds(60), stopAfter: .seconds(60)).countdown.isEmpty)
    }
}

@Suite("How long a recording says it has left")
struct RemainingTimeTests {
    @Test("says nothing while the cap is far off")
    func silentWhileFarOff() {
        #expect(RemainingTime.phrase(for: .keepGoing) == nil)
        #expect(RemainingTime.phrase(for: .finishNow) == nil)
    }

    @Test("counts down in minutes, then in tens of seconds")
    func countsDown() {
        #expect(RemainingTime.phrase(for: .approaching(remaining: .seconds(60))) == "1 min left")
        #expect(RemainingTime.phrase(for: .approaching(remaining: .seconds(120))) == "2 min left")
        #expect(RemainingTime.phrase(for: .approaching(remaining: .seconds(45))) == "50 sec left")
        #expect(RemainingTime.phrase(for: .approaching(remaining: .seconds(3))) == "10 sec left")
    }
}
