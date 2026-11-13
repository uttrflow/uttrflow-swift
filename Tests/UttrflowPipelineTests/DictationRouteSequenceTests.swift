// Dictations that follow one another, driven through the real controller and the real pipeline.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Counts the cues sounded, which are all a refused press may produce.
private final class CountingCue: RecordingCueing {
    private let counts = Mutex((starts: 0, refusals: 0))
    func playStart() { counts.withLock { $0.starts += 1 } }
    func playStop() {}
    func playWarning() {}
    func playDiscarded() { counts.withLock { $0.refusals += 1 } }
    var starts: Int { counts.withLock { $0.starts } }
    var refusals: Int { counts.withLock { $0.refusals } }
}

/// The controller over a scenario's real pipeline, with a clock the test moves.
private struct Route {
    let controller: DictationController<ManualClock>
    let session: ScenarioSession
    let clock: ManualClock
    let cue = CountingCue()

    init(_ scenario: Scenario) async {
        session = await ScenarioDriver.session(scenario)
        clock = ManualClock()
        controller = DictationController(
            dependencies: .init(pipeline: session.pipeline, monitor: SilentHotkeyMonitor(), cue: cue),
            clock: clock)
    }

    /// Holds the key for two seconds, then lets go.
    func hold() async {
        controller.submit(.pressed)
        await controller.caughtUp()
        clock.advance(by: .seconds(2))
        controller.submit(.released)
        await controller.caughtUp()
    }

    /// Waits for the decodes the recogniser has been asked for to reach `count`.
    func waitForDecodes(_ count: Int) async throws {
        try await eventually { await session.speech.hints.count >= count }
    }
}

private func scenario(holding held: Int? = nil) -> Scenario {
    Scenario(
        pieces: [ScriptedPiece("first dictation"), ScriptedPiece("second dictation")],
        context: .fixture(), take: ScenarioDriver.oneWindow, heldPiece: held)
}

@Suite("Dictations in a row through the real controller and pipeline", .timeLimit(.minutes(1)))
struct DictationRouteSequenceTests {

    @Test("a press 300 ms into the first dictation's processing is refused, and the first still lands")
    func pressDuringProcessing() async throws {
        let route = await Route(scenario(holding: 0))
        await route.hold()
        try await route.waitForDecodes(1)

        route.clock.advance(by: .milliseconds(300))
        await route.hold()
        #expect(route.cue.refusals == 1)
        #expect(route.cue.starts == 1)

        await route.session.speech.release()
        await route.controller.drained()
        #expect(route.session.inserter.received.count == 1)
        #expect(route.session.inserter.received.first?.lowercased().hasPrefix("first dictation") == true)

        await route.hold()
        await route.controller.drained()
        #expect(route.session.inserter.received.count == 2)
        #expect(route.session.inserter.received.last?.lowercased().hasPrefix("second dictation") == true)
    }

    @Test("Escape while the first is processed writes nothing, and the next dictation lands")
    func cancelThenDictate() async throws {
        let route = await Route(scenario(holding: 0))
        await route.hold()
        try await route.waitForDecodes(1)

        route.controller.submit(.escapePressed)
        await route.controller.caughtUp()
        #expect(await route.session.pipeline.currentState == .idle)
        await route.session.speech.release()
        await route.controller.drained()
        #expect(route.session.inserter.received.isEmpty)

        await route.hold()
        await route.controller.drained()
        #expect(route.session.inserter.received.count == 1)
        #expect(route.session.inserter.received.first?.lowercased().hasPrefix("second dictation") == true)
    }

    @Test("an insertion that fails leaves the next dictation free to land")
    func failedInsertionThenDictate() async throws {
        var failing = scenario()
        failing.insertions = ScriptedSequence(
            .failure(.noFocusedTextField), then: [.success(InsertionAttempt(.accessibility))])
        let route = await Route(failing)
        await route.hold()
        await route.controller.drained()
        guard case .failed = await route.session.pipeline.currentState else {
            Issue.record("the failed insertion did not end in a failure")
            return
        }

        await route.hold()
        await route.controller.drained()
        #expect(route.session.inserter.received.count == 2)
        guard case .inserted = await route.session.pipeline.currentState else {
            Issue.record("the dictation after the failure did not land")
            return
        }
    }
}
