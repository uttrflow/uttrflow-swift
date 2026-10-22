// Fails a scripted dictation when the main actor stops turning while it runs, which no stage budget catches.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A monitor that is never worked, since the test hands gestures to the controller directly.
private final class StillMonitor: HotkeyMonitoring {
    let events = AsyncStream<HotkeyEvent> { $0.finish() }

    func start(binding: HotkeyBinding) {}

    func stop() {}
}

/// How long the main actor may go without turning during a dictation, over what the host's load alone costs.
private let stallBudget = Duration.milliseconds(50)

/// Runs one held dictation through the real controller, presenting each state on the main actor as the app does.
@MainActor
private func longestGapDuringDictation(
    observer: @escaping @MainActor (DictationState) -> Void
) async throws
    -> Duration
{
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "i'll be late"))),
        cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: FakeTextInserter(),
        clock: ManualClock()
    )
    let clock = ManualClock()
    let controller = DictationController(
        dependencies: .init(pipeline: pipeline, monitor: StillMonitor()), clock: clock)
    let settled = Signal()
    let states = await pipeline.states()
    let presenting = Task { @MainActor in
        for await state in states {
            _ = DictationPresenter.dock(for: state)
            observer(state)
            if case .inserted = state { settled.fire() }
        }
    }
    defer { presenting.cancel() }

    let heartbeat = MainActorHeartbeat()
    heartbeat.start()
    await controller.handle(.pressed)
    clock.advance(by: .seconds(3))
    await controller.handle(.released)
    try await arrival(of: settled.fired)
    return heartbeat.stop()
}

@Suite("Main actor: a dictation never stalls it", .timeLimit(.minutes(1)))
@MainActor
struct MainActorStallTests {

    @Test("a scripted dictation keeps the main actor turning")
    func dictationKeepsTheMainActorTurning() async throws {
        // A stall in the dictation shows in every run; a gap the host's scheduling made shows in a few, so the run that held least decides.
        var overshoots: [Duration] = []
        for _ in 0..<Self.attempts {
            let idle = await MainActorHeartbeat.idleGap()
            let gap = try await longestGapDuringDictation { _ in }
            overshoots.append(gap - idle)
            if gap < stallBudget + idle { break }
        }

        #expect(
            overshoots.last.map { $0 < stallBudget } == true,
            "main actor stalled past \(stallBudget) over the host's idle gap in every run: \(overshoots)")
    }

    /// How many runs a dictation gets to show it keeps the main actor turning.
    private static let attempts = 5

    @Test("a state observer that blocks for 100 ms is caught")
    func blockingObserverIsCaught() async throws {
        let gap = try await longestGapDuringDictation { state in
            if case .transcribing = state { Thread.sleep(forTimeInterval: 0.1) }
        }

        #expect(gap >= .milliseconds(100))
    }
}
