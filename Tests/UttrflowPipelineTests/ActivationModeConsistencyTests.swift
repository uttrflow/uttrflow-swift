// The same dictation, started and ended by every gesture the controller accepts, must give the same words.
import Testing
import UttrflowCore

@testable import UttrflowPipeline
import UttrflowTestSupport

/// A ``HotkeyMonitoring`` that watches nothing; the test hands gestures to the controller itself.
private struct SilentMonitor: HotkeyMonitoring {
    let events = AsyncStream<HotkeyEvent> { $0.finish() }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}

    func stop() {}
}

/// The ways a person can start and end one dictation. See Docs/pipeline-gestures.md.
enum ActivationGesture: String, CaseIterable, Sendable {
    case hold
    case toggle
    case handsFree
    case command
}

/// What one gesture's dictation wrote, and what the recogniser answered for it.
private struct GestureResult {
    let gesture: ActivationGesture
    let writes: [String]
    let heard: [String]
}

@Suite(
    "Activation modes: hold, toggle, hands-free and a command give the same words",
    .timeLimit(.minutes(1)))
struct ActivationModeConsistencyTests {
    private typealias Controller = DictationController<ManualClock>

    @Test(
        "every gesture writes the hold's text for each multi-piece corpus case",
        arguments: MultiPieceCorpusTests.cases)
    func everyGestureWritesTheSameText(_ testCase: MultiPieceCase) async throws {
        let pieces = testCase.pieces.map { ScriptedPiece($0) }
        var results: [GestureResult] = []
        for gesture in ActivationGesture.allCases {
            results.append(try await dictate(pieces, into: testCase.context, by: gesture))
        }
        let hold = try #require(results.first { $0.gesture == .hold })
        let reference = try #require(hold.writes.last)
        #expect(hold.writes.count == 1)
        #expect(hold.heard == testCase.pieces)

        for result in results where result.gesture != .hold {
            let written = result.writes.last ?? ""
            let difference = WordErrorRate.measure(
                reference: Self.words(reference), hypothesis: Self.words(written))
            #expect(result.heard == testCase.pieces, "\(result.gesture) heard \(result.heard)")
            #expect(result.writes.count == 1, "\(result.gesture) wrote \(result.writes)")
            #expect(
                written == reference,
                "\(result.gesture) wrote '\(written)', hold wrote '\(reference)', \(difference.errors) words differ"
            )
        }
    }

    /// One dictation of `pieces`, started and ended by `gesture` through the real controller and pipeline.
    private func dictate(
        _ pieces: [ScriptedPiece], into context: AppContext, by gesture: ActivationGesture
    ) async throws -> GestureResult {
        let session = await ScenarioDriver.session(Scenario(pieces: pieces, context: context))
        let clock = ManualClock()
        let controller = Controller(
            pipeline: session.pipeline, monitor: SilentMonitor(), commandMonitor: SilentMonitor(),
            clock: clock,
            options: .init(activation: gesture == .toggle ? .pressToToggle : .holdToTalk))
        switch gesture {
        case .hold:
            await controller.handle(.pressed)
            clock.advance(by: Controller.minimumHold + .milliseconds(1))
            await controller.handle(.released)
        case .toggle:
            await controller.handle(.pressed)
            await controller.handle(.released)
            clock.advance(by: Controller.minimumHold + .milliseconds(1))
            await controller.handle(.pressed)
            await controller.handle(.released)
        case .handsFree:
            await Self.doubleTap(controller, clock)
            clock.advance(by: Controller.doubleTapWindow * 2)
            await Self.doubleTap(controller, clock)
        case .command:
            #expect(await controller.command(.start) == .started)
            #expect(await controller.command(.stop) == .finished)
        }
        try await eventually { await !session.pipeline.currentState.isBusy }
        return GestureResult(
            gesture: gesture, writes: session.inserter.received,
            heard: await session.speech.answered.map(\.text))
    }

    /// Two taps inside the double-tap window, the gesture that opens and closes hands-free.
    private static func doubleTap(_ controller: Controller, _ clock: ManualClock) async {
        for tap in 0..<2 {
            if tap > 0 { clock.advance(by: .milliseconds(120)) }
            await controller.handle(.pressed)
            clock.advance(by: Controller.minimumHold - .milliseconds(1))
            await controller.handle(.released)
        }
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
    }
}
