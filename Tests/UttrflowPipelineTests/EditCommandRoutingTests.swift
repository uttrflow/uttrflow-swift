// Tests that the held command key sends its words to the edit commands and never types them.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``HotkeyMonitoring`` that records the bindings it was asked to watch and takes pushed gestures.
private final class RoutingMonitor: HotkeyMonitoring {
    private let watched = Mutex<[HotkeyBinding]>([])
    private let stops = Mutex(0)
    let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {
        watched.withLock { $0.append(binding) }
    }

    func stop() {
        stops.withLock { $0 += 1 }
    }

    var bindings: [HotkeyBinding] { watched.withLock { $0 } }
    var stopCount: Int { stops.withLock { $0 } }
}

/// An ``EditCommand`` that takes every utterance, or none, and records what it ran on.
private final class SpyCommand: EditCommand {
    private let takesAll: Bool
    private let log = Mutex<[(heard: String, selection: String?)]>([])

    init(takesAll: Bool = true) {
        self.takesAll = takesAll
    }

    func accepts(_ heard: String) -> Bool { takesAll }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        log.withLock { $0.append((heard, target.selectedText)) }
        return "Made the selection bold."
    }

    var ran: [(heard: String, selection: String?)] { log.withLock { $0 } }
}

/// A command whose run always fails, as a write refused by the app would.
private struct RefusedCommand: EditCommand {
    func accepts(_ heard: String) -> Bool { true }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        throw TextInsertionError.insertionTimedOut
    }
}

// MARK: - Harness

private let spoken = "make this bold"

private struct RoutingHarness {
    let controller: DictationController<ManualClock>
    let pipeline: DictationPipeline
    let dictationMonitor: RoutingMonitor
    let commandMonitor: RoutingMonitor
    let inserter: FakeTextInserter
    let clock: ManualClock
}

/// A dictionary holding one spelling for one heard word, wherever it is heard.
private struct OneEntryDictionary: WordCorrecting {
    let heard: String
    let wrote: String

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        transcription.text.split(whereSeparator: \.isWhitespace).enumerated().compactMap {
            $0.element.lowercased() == heard
                ? DictationCorrection(
                    heard: String($0.element), wrote: wrote, wordRange: $0.offset..<($0.offset + 1),
                    entryID: UUID(), reason: .unknown("test"), heardConfidence: 0.2)
                : nil
        }
    }
}

private func makeHarness(
    commands: [any EditCommand], activation: HotkeyActivation = .holdToTalk, heard: String = spoken,
    corrector: any WordCorrecting = NoTextChanges()
) -> RoutingHarness {
    let inserter = FakeTextInserter()
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: heard))),
        cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture(selectedText: "the quarterly plan")),
        inserter: inserter,
        corrector: corrector,
        clock: ManualClock(),
        commands: EditCommandRegistry(commands)
    )
    let dictationMonitor = RoutingMonitor()
    let commandMonitor = RoutingMonitor()
    let clock = ManualClock()
    let controller = DictationController(
        pipeline: pipeline, monitor: dictationMonitor, commandMonitor: commandMonitor,
        activation: activation, clock: clock)
    return RoutingHarness(
        controller: controller, pipeline: pipeline, dictationMonitor: dictationMonitor,
        commandMonitor: commandMonitor, inserter: inserter, clock: clock)
}

private let pastTheMinimum = DictationController<ManualClock>.minimumHold + .milliseconds(1)

/// One full hold of a key that is not a modifier, so no settle is involved.
private func hold(_ harness: RoutingHarness, from route: UtteranceRoute) async {
    await harness.controller.handle(.pressed, from: route)
    harness.clock.advance(by: pastTheMinimum)
    await harness.controller.handle(.released, from: route)
}

// MARK: - Tests

@Suite("Edit commands: the held command key runs commands instead of dictating")
struct EditCommandRoutingTests {

    @Test("a hold of the command key runs the command on the selection and types nothing")
    func commandKeyRunsTheCommand() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command])

        await hold(harness, from: .command)

        #expect(command.ran.map(\.heard) == [spoken])
        #expect(command.ran.map(\.selection) == ["the quarterly plan"])
        #expect(harness.inserter.received.isEmpty)
        #expect(await harness.pipeline.currentState == .executed("Made the selection bold."))
    }

    @Test("command words carry the dictionary's spellings, so a replacement writes a filed term")
    func commandWordsGoThroughTheDictionary() async {
        let command = SpyCommand()
        let harness = makeHarness(
            commands: [command], heard: "replace the plan with kubernetes",
            corrector: OneEntryDictionary(heard: "kubernetes", wrote: "Kubernetes"))

        await hold(harness, from: .command)

        #expect(command.ran.map(\.heard) == ["replace the plan with Kubernetes"])
        #expect(harness.inserter.received.isEmpty)
    }

    @Test("a hold of the dictation key still types its words and runs no command")
    func dictationKeyStillDictates() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command])

        await hold(harness, from: .dictation)

        #expect(command.ran.isEmpty)
        #expect(harness.inserter.received.count == 1)
    }

    @Test("the hold after a command goes back to dictation")
    func routeIsSpentByOneRecording() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command])

        await hold(harness, from: .command)
        await hold(harness, from: .dictation)

        #expect(command.ran.count == 1)
        #expect(harness.inserter.received.count == 1)
    }

    @Test("words no command takes are kept on a notice and nothing is typed")
    func unrecognisedCommandFailsWithTheWords() async {
        let harness = makeHarness(commands: [SpyCommand(takesAll: false)])

        await hold(harness, from: .command)

        #expect(harness.inserter.received.isEmpty)
        guard case .failed(let failure) = await harness.pipeline.currentState else {
            Issue.record("expected a failure notice")
            return
        }
        #expect(failure.transcript == spoken)
    }

    @Test("a command that fails says so, keeping the words, and types nothing")
    func failingCommandKeepsTheWords() async {
        let harness = makeHarness(commands: [RefusedCommand()])

        await hold(harness, from: .command)

        #expect(harness.inserter.received.isEmpty)
        guard case .failed(let failure) = await harness.pipeline.currentState else {
            Issue.record("expected a failure notice")
            return
        }
        #expect(failure.transcript == spoken)
    }

    @Test("the other key's events are ignored while a hold is under way")
    func otherKeyCannotTakeOverAHold() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command])

        await harness.controller.handle(.pressed, from: .dictation)
        harness.clock.advance(by: pastTheMinimum)
        await harness.controller.handle(.pressed, from: .command)
        await harness.controller.handle(.released, from: .command)
        #expect(await harness.pipeline.currentState.isListening)
        await harness.controller.handle(.released, from: .dictation)

        #expect(command.ran.isEmpty)
        #expect(harness.inserter.received.count == 1)
    }

    @Test("in press-to-toggle, the command key's press starts and ends a command")
    func toggleModeRoutesTheCommandKey() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command], activation: .pressToToggle)

        await harness.controller.handle(.pressed, from: .command)
        await harness.controller.handle(.pressed, from: .command)

        #expect(command.ran.map(\.heard) == [spoken])
        #expect(harness.inserter.received.isEmpty)
    }

    @Test("the command key is watched with its own binding and stops with the controller")
    func commandBindingIsWatchedSeparately() async throws {
        let harness = makeHarness(commands: [])

        try await harness.controller.start(binding: .controlOptionHold)
        try await harness.controller.start(commandBinding: .controlShiftHold)
        await harness.controller.stop()

        #expect(harness.dictationMonitor.bindings == [.controlOptionHold])
        #expect(harness.commandMonitor.bindings == [.controlShiftHold])
        #expect(harness.commandMonitor.stopCount == 1)
    }

    @Test("an unbound command key stops being watched")
    func unboundCommandKeyStops() async throws {
        let harness = makeHarness(commands: [])

        try await harness.controller.start(commandBinding: nil)

        #expect(harness.commandMonitor.bindings.isEmpty)
        #expect(harness.commandMonitor.stopCount == 1)
    }

    @Test("a click always dictates, whichever key was used last")
    func clickDictates() async {
        let command = SpyCommand()
        let harness = makeHarness(commands: [command])

        await hold(harness, from: .command)
        _ = await harness.controller.command(.start)
        _ = await harness.controller.command(.stop)
        await harness.controller.drained()

        #expect(command.ran.count == 1)
        #expect(harness.inserter.received.count == 1)
    }
}

@Suite("Edit commands: the shipped command key")
struct EditCommandShortcutTests {
    @Test("the command key ships as ⌃⇧ held and leaves dictation on ⌃⌥ held")
    func defaults() {
        #expect(ShortcutSet.default.first(for: .editCommand) == .controlShiftHold)
        #expect(ShortcutSet.default.first(for: .dictate) == .controlOptionHold)
        #expect(HotkeyBinding.controlShiftHold.isDeliverable)
        #expect(HotkeyBinding.controlShiftHold.heldModifier != nil)
    }
}
