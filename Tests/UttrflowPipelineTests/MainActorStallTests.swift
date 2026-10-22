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
        let idle = await MainActorHeartbeat.idleGap()
        let gap = try await longestGapDuringDictation { _ in }

        #expect(gap < stallBudget + idle, "main actor stalled \(gap), host idle gap \(idle)")
    }

    @Test("a state observer that blocks for 100 ms is caught")
    func blockingObserverIsCaught() async throws {
        let gap = try await longestGapDuringDictation { state in
            if case .transcribing = state { Thread.sleep(forTimeInterval: 0.1) }
        }

        #expect(gap >= .milliseconds(100))
    }

    @Test("a state observer that computes for 100 ms is caught")
    func computingObserverIsCaught() async throws {
        let gap = try await longestGapDuringDictation { state in
            if case .transcribing = state { compute(nanoseconds: 100_000_000) }
        }

        #expect(gap >= .milliseconds(100))
    }

    @Test("restarting a heartbeat stops the sampler it replaces")
    func restartStopsTheEarlierSampler() throws {
        let heartbeat = MainActorHeartbeat()
        heartbeat.start()
        let first = try #require(heartbeat.watch)
        heartbeat.start()
        #expect(first.isStopped)
        _ = heartbeat.stop()
    }

    @Test("a heartbeat let go without stopping stops its sampler")
    func droppedHeartbeatStopsItsSampler() throws {
        var heartbeat: MainActorHeartbeat? = MainActorHeartbeat()
        heartbeat?.start()
        let watch = try #require(heartbeat?.watch)
        heartbeat = nil
        #expect(watch.isStopped)
    }
}

@Suite("Main actor: time a ready thread waits for a processor")
struct StarvationTallyTests {
    private let start = ContinuousClock.now
    private let ready = (time: Duration.milliseconds(5), ready: true)

    /// Readings every 10 ms from `start`, one per element.
    private func tally(_ readings: [(time: Duration, ready: Bool)?]) -> Duration {
        var tally = StarvationTally()
        for (index, reading) in readings.enumerated() {
            tally.record(reading, at: start.advanced(by: .milliseconds(10 * index)))
        }
        return tally.starved
    }

    @Test("a ready thread whose processor time stands still for 50 ms counts the 30 ms past the tick")
    func standingStillCounts() {
        #expect(tally(Array(repeating: ready, count: 6)) == .milliseconds(30))
    }

    @Test("a ready thread whose processor time keeps moving counts nothing")
    func movingCountsNothing() {
        let readings = (0..<6).map { (time: Duration.milliseconds($0), ready: true) }
        #expect(tally(readings) == .zero)
    }

    @Test("a waiting thread or a refused reading restarts the count")
    func waitingOrRefusedRestarts() {
        let waiting = (time: Duration.milliseconds(5), ready: false)
        #expect(tally([ready, ready, waiting, ready, ready, nil, ready, ready]) == .zero)
    }
}

/// Keeps this thread computing until it has used that much processor time, however long the host takes to give it.
private func compute(nanoseconds: UInt64) {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    while clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start < nanoseconds {}
}
