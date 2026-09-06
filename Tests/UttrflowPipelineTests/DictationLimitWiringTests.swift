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

/// A ``TextInserting`` that records what reached the screen.
private final class QuietInserter: TextInserting, Sendable {
    private let placed = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        placed.withLock { $0.append(text) }
        return .accessibility
    }

    var inserted: [String] { placed.withLock { $0 } }
}

@Suite("Dictation controller: the soft cap on a long recording")
struct DictationLimitWiringTests {
    private static let limit = DictationLimit(warnAfter: .seconds(180), stopAfter: .seconds(240))

    private func makeController(
        clock: ManualClock, inserter: QuietInserter,
        advice: @escaping @Sendable (DictationAdvice) -> Void
    ) -> DictationController<ManualClock> {
        DictationController(
            pipeline: DictationPipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 200))),
                speech: FakeSpeechEngine(
                    transcribeOutcome: .success(Transcription(text: "a long dictation"))),
                cleaner: QuietCleaner(),
                context: FakeContextEngine(),
                inserter: inserter,
                clock: clock),
            monitor: SilentMonitor(),
            activation: .holdToTalk,
            clock: clock,
            limit: Self.limit,
            onAdvice: advice)
    }

    /// Lets the clock reach `deadline`, once something is actually waiting for it.
    private func advance(_ clock: ManualClock, to deadline: Duration) async {
        await clock.advanceWhenSomethingIsWaiting(by: deadline)
    }

    @Test("warns a minute before the cap rather than cutting the speaker off")
    func warnsBeforeTheCap() async {
        let clock = ManualClock()
        let heard = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: QuietInserter()) { advice in
            heard.withLock { $0.append(advice) }
        }

        await controller.handle(.pressed)
        await advance(clock, to: Self.limit.warnAfter)
        while heard.withLock({ $0.isEmpty }) { await Task.yield() }

        #expect(heard.withLock { $0.first } == .approaching(remaining: .seconds(60)))
    }

    @Test("finishes the dictation at the cap, keeping every word of it")
    func finishesAtTheCap() async {
        let clock = ManualClock()
        let inserter = QuietInserter()
        let saw = Mutex<[DictationAdvice]>([])
        let controller = makeController(clock: clock, inserter: inserter) { advice in
            saw.withLock { $0.append(advice) }
        }

        await controller.handle(.pressed)
        await advance(clock, to: Self.limit.warnAfter)
        await advance(clock, to: Self.limit.stopAfter - Self.limit.warnAfter)

        while inserter.inserted.isEmpty { await Task.yield() }
        // Kept, not discarded: a cap that threw the audio away would be worse than none.
        #expect(inserter.inserted == ["a long dictation"])
        #expect(saw.withLock { $0.contains(.finishNow) })
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
