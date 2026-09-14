// Tests that modifiers bound alone dictate when held, and not when they begin another shortcut.
import CoreGraphics
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Keys, decoded the way the tap decodes them

/// A key that sets a flag of its own when held.
private enum ModifierKey {
    case control, command, option, shift, function

    var code: UInt16 {
        switch self {
        case .control: 59
        case .command: 55
        case .option: 58
        case .shift: 56
        case .function: 63
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .control: .maskControl
        case .command: .maskCommand
        case .option: .maskAlternate
        case .shift: .maskShift
        case .function: .maskSecondaryFn
        }
    }
}

private let kKey: UInt16 = 40
private let vKey: UInt16 = 9
private let spaceKey: UInt16 = 49
private let rightArrow: UInt16 = 124

/// A keyboard whose every stroke goes through `SystemKeyboard.stroke`, as a real key event does.
private final class Hands {
    private var flags: CGEventFlags = []

    func hold(_ keys: ModifierKey...) -> [KeyStroke] {
        keys.map { key in
            flags.insert(key.flag)
            return SystemKeyboard.stroke(keyCode: key.code, flags: flags, phase: .modifiersChanged)
        }
    }

    func letGo(_ keys: ModifierKey...) -> [KeyStroke] {
        keys.map { key in
            flags.remove(key.flag)
            return SystemKeyboard.stroke(keyCode: key.code, flags: flags, phase: .modifiersChanged)
        }
    }

    func type(_ keyCode: UInt16) -> [KeyStroke] {
        [
            SystemKeyboard.stroke(keyCode: keyCode, flags: flags, phase: .down),
            SystemKeyboard.stroke(keyCode: keyCode, flags: flags, phase: .up),
        ]
    }
}

private let controlCommandOption = HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control])
private let allFour = HotkeyBinding(keyCode: 56, modifiers: [.control, .option, .shift, .command])

/// Every event a recogniser reports for these strokes, in order.
private func events(_ binding: HotkeyBinding, _ strokes: [KeyStroke]) -> [HotkeyEvent] {
    var recogniser = HotkeyRecogniser(binding: binding)
    return strokes.compactMap { recogniser.receive($0) }
}

// MARK: - A controller fed by the recogniser

private final class QuietMonitor: HotkeyMonitoring {
    private let pair = AsyncStream<HotkeyEvent>.makeStream()
    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() {}
    var events: AsyncStream<HotkeyEvent> { pair.stream }
}

private final class ChordCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: chordTidied, producedBy: .foundationModels)
    }
}

private final class ChordInserter: TextInserting {
    private let log = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        log.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }

    var received: [String] { log.withLock { $0 } }
}

private final class ChordCue: RecordingCueing {
    private let starts = Mutex(0)
    func playStart() { starts.withLock { $0 += 1 } }
    func playStop() {}
    var startsPlayed: Int { starts.withLock { $0 } }
}

private let chordTidied = "Meet me at the corner."

/// One controller watching one binding, driven stroke by stroke through a real recogniser.
private final class Rig {
    let controller: DictationController<ManualClock>
    let pipeline: DictationPipeline
    let capture: FakeAudioCaptureEngine
    let inserter: ChordInserter
    let cue: ChordCue
    let clock: ManualClock
    private var recogniser: HotkeyRecogniser
    let hands = Hands()

    static func make(_ binding: HotkeyBinding, _ activation: HotkeyActivation) async throws -> Rig {
        let capture = FakeAudioCaptureEngine()
        let inserter = ChordInserter()
        let pipeline = DictationPipeline(
            capture: capture,
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "meet me at the corner"))),
            cleaner: ChordCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: inserter,
            clock: ManualClock()
        )
        let cue = ChordCue()
        let clock = ManualClock()
        let controller = DictationController(
            pipeline: pipeline, monitor: QuietMonitor(), cue: cue, activation: activation, clock: clock)
        try await controller.start(binding: binding)
        return Rig(
            controller: controller, pipeline: pipeline, capture: capture, inserter: inserter, cue: cue,
            clock: clock, recogniser: HotkeyRecogniser(binding: binding))
    }

    private init(
        controller: DictationController<ManualClock>, pipeline: DictationPipeline,
        capture: FakeAudioCaptureEngine, inserter: ChordInserter, cue: ChordCue, clock: ManualClock,
        recogniser: HotkeyRecogniser
    ) {
        self.controller = controller
        self.pipeline = pipeline
        self.capture = capture
        self.inserter = inserter
        self.cue = cue
        self.clock = clock
        self.recogniser = recogniser
    }

    /// Hands each stroke to the recogniser and each event it reports to the controller, then lets the queue catch up.
    func send(_ strokes: [KeyStroke]) async {
        for stroke in strokes {
            if let event = recogniser.receive(stroke) {
                await controller.handle(event)
            }
        }
        await controller.drained()
    }

    /// Holds on past the settle, so a press that is waiting counts.
    func waitOutTheSettle() async {
        clock.advance(by: DictationController<ManualClock>.modifierSettle)
        await controller.settling()
        await controller.drained()
    }

    /// ⌃⌘⌥ pressed and let go well inside the settle, then a pause shorter than the double-tap window.
    func tapTheChord() async {
        await send(hands.hold(.control, .command, .option))
        clock.advance(by: .milliseconds(80))
        await send(hands.letGo(.option, .command, .control))
        clock.advance(by: .milliseconds(100))
    }

    var isListening: Bool { get async { await pipeline.currentState.isListening } }
    var microphone: [FakeAudioCaptureEngine.Event] { get async { await capture.calls.events } }
}

// MARK: - Recognising

@Suite("Modifiers bound alone, as the recogniser reads them")
struct ModifierChordRecognitionTests {
    @Test("⌃⌘⌥K withdraws the ⌃⌘⌥ press instead of releasing it")
    func keyDuringTheChordWithdrawsIt() {
        let hands = Hands()
        let strokes =
            hands.hold(.control, .command, .option) + hands.type(kKey)
            + hands.letGo(.option, .command, .control)
        #expect(events(controlCommandOption, strokes) == [.pressed, .cancelled])
    }

    @Test("⌃⌥⇧⌘K on a ⌃⌘⌥ binding presses once and never again as ⇧ comes and goes")
    func extraModifierDoesNotToggle() {
        let hands = Hands()
        let strokes =
            hands.hold(.control, .command, .option, .shift) + hands.type(kKey) + hands.letGo(.shift)
            + hands.letGo(.option, .command, .control)
        #expect(events(controlCommandOption, strokes) == [.pressed, .cancelled])
    }

    @Test("⌃⌥⇧⌘K on a four-modifier binding is withdrawn")
    func fourModifierBindingWithAKey() {
        let hands = Hands()
        let strokes =
            hands.hold(.control, .option, .shift, .command) + hands.type(kKey)
            + hands.letGo(.command, .shift, .option, .control)
        #expect(events(allFour, strokes) == [.pressed, .cancelled])
    }

    @Test("a modifier still held from another shortcut keeps the chord from counting until everything is up")
    func modifierLeftFromAnotherShortcut() {
        let hands = Hands()
        let strokes =
            hands.hold(.command) + hands.type(vKey) + hands.hold(.control, .option)
            + hands.letGo(.option, .control, .command) + hands.hold(.control, .command, .option)
        #expect(events(controlCommandOption, strokes) == [.pressed])
    }

    @Test("the chord held alone presses and releases")
    func chordAlone() {
        let hands = Hands()
        let strokes = hands.hold(.control, .command, .option) + hands.letGo(.command, .control, .option)
        #expect(events(controlCommandOption, strokes) == [.pressed, .released])
    }
}

// MARK: - Dictating

@Suite("Modifiers bound alone, as the controller acts on them", .timeLimit(.minutes(1)))
struct ModifierChordActivationTests {
    @Test(
        "⌃⌘⌥K opens no microphone and inserts nothing",
        arguments: [HotkeyActivation.holdToTalk, .pressToToggle])
    func chordWithAKeyDoesNotDictate(_ activation: HotkeyActivation) async throws {
        let rig = try await Rig.make(controlCommandOption, activation)
        await rig.send(rig.hands.hold(.control, .command, .option))
        await rig.send(rig.hands.type(kKey))
        rig.clock.advance(by: .seconds(1))
        await rig.send(rig.hands.letGo(.option, .command, .control))

        #expect(await rig.microphone.isEmpty)
        #expect(rig.cue.startsPlayed == 0)
        #expect(rig.inserter.received.isEmpty)
    }

    @Test(
        "⌃⌥⇧⌘K opens no microphone on a ⌃⌘⌥ or a four-modifier binding",
        arguments: [HotkeyActivation.holdToTalk, .pressToToggle], [controlCommandOption, allFour])
    func fourModifiersWithAKeyDoNotDictate(
        _ activation: HotkeyActivation, _ binding: HotkeyBinding
    ) async throws {
        let rig = try await Rig.make(binding, activation)
        await rig.send(rig.hands.hold(.control, .option))
        await rig.send(rig.hands.hold(.shift))
        await rig.send(rig.hands.hold(.command))
        await rig.send(rig.hands.type(kKey))
        await rig.send(rig.hands.letGo(.shift))
        rig.clock.advance(by: .seconds(1))
        await rig.send(rig.hands.letGo(.command, .option, .control))

        #expect(await rig.microphone.isEmpty)
        #expect(rig.cue.startsPlayed == 0)
    }

    @Test("holding ⌃⌘⌥ alone dictates once it has settled, measured from when the keys went down")
    func holdingTheChordDictates() async throws {
        let rig = try await Rig.make(controlCommandOption, .holdToTalk)
        await rig.send(rig.hands.hold(.control, .command, .option))
        #expect(await rig.microphone.isEmpty, "nothing opens before the settle")

        await rig.waitOutTheSettle()
        #expect(await rig.isListening)
        #expect(rig.cue.startsPlayed == 1)

        rig.clock.advance(by: .seconds(3))
        await rig.send(rig.hands.letGo(.option, .command, .control))
        #expect(rig.inserter.received == [chordTidied])
    }

    @Test("pressing ⌃⌘⌥ toggles a dictation on after the settle, and off with the next press")
    func togglingTheChordDictates() async throws {
        let rig = try await Rig.make(controlCommandOption, .pressToToggle)
        await rig.send(rig.hands.hold(.control, .command, .option))
        #expect(await rig.microphone.isEmpty, "nothing opens before the settle")
        await rig.waitOutTheSettle()
        await rig.send(rig.hands.letGo(.option, .command, .control))
        #expect(await rig.isListening)

        rig.clock.advance(by: .seconds(3))
        await rig.send(rig.hands.hold(.control, .command, .option))
        await rig.waitOutTheSettle()
        await rig.send(rig.hands.letGo(.option, .command, .control))
        #expect(rig.inserter.received == [chordTidied])
    }

    @Test("a quick ⌃⌘⌥ tap in toggle mode starts on the release rather than waiting")
    func quickToggleTapStartsOnRelease() async throws {
        let rig = try await Rig.make(controlCommandOption, .pressToToggle)
        await rig.send(rig.hands.hold(.control, .command, .option))
        rig.clock.advance(by: .milliseconds(80))
        #expect(await rig.microphone.isEmpty, "nothing opens while the press is still settling")
        await rig.send(rig.hands.letGo(.option, .command, .control))

        #expect(await rig.isListening)
    }

    @Test("a single ⌃⌘⌥ slip in hold-to-talk makes no sound and opens nothing")
    func slipIsSilent() async throws {
        let rig = try await Rig.make(controlCommandOption, .holdToTalk)
        await rig.send(rig.hands.hold(.control, .command, .option))
        rig.clock.advance(by: .milliseconds(80))
        await rig.send(rig.hands.letGo(.option, .command, .control))

        #expect(await rig.microphone.isEmpty)
        #expect(rig.cue.startsPlayed == 0)
    }

    @Test("two ⌃⌘⌥ taps still leave the microphone open, and two more close it")
    func doubleTapStillGoesHandsFree() async throws {
        let rig = try await Rig.make(controlCommandOption, .holdToTalk)
        await rig.tapTheChord()
        #expect(rig.cue.startsPlayed == 0, "the first tap is only counted")
        await rig.tapTheChord()
        #expect(await rig.isListening)

        rig.clock.advance(by: .seconds(3))
        await rig.tapTheChord()
        await rig.tapTheChord()
        #expect(await rig.isListening == false)
        #expect(rig.inserter.received == [chordTidied])
    }

    @Test(
        "a key arriving after the settle cancels the dictation without inserting anything",
        arguments: [HotkeyActivation.holdToTalk, .pressToToggle])
    func lateKeyCancels(_ activation: HotkeyActivation) async throws {
        let rig = try await Rig.make(controlCommandOption, activation)
        await rig.send(rig.hands.hold(.control, .command, .option))
        await rig.waitOutTheSettle()
        rig.clock.advance(by: .seconds(1))
        await rig.send(rig.hands.type(kKey))
        await rig.send(rig.hands.letGo(.option, .command, .control))

        #expect(await rig.isListening == false)
        #expect(await rig.microphone == [.start, .cancel])
        #expect(rig.inserter.received.isEmpty)
    }

    @Test("a repeated press, a rebind and a stop while waiting to settle start nothing")
    func waitingPressIsForgotten() async throws {
        let rig = try await Rig.make(controlCommandOption, .pressToToggle)
        await rig.controller.handle(.pressed)
        await rig.controller.handle(.pressed)
        try await rig.controller.start(binding: controlCommandOption)
        await rig.controller.handle(.released)
        await rig.controller.handle(.pressed)
        await rig.controller.stop()
        rig.clock.advance(by: .seconds(1))
        await rig.controller.drained()

        #expect(await rig.microphone.isEmpty)
    }

    @Test("Fn still dictates the moment it goes down, and an arrow key during the hold changes nothing")
    func functionHoldUnchanged() async throws {
        let rig = try await Rig.make(.functionHold, .holdToTalk)
        await rig.send(rig.hands.hold(.function))
        #expect(await rig.isListening)

        await rig.send([
            SystemKeyboard.stroke(keyCode: rightArrow, flags: .maskSecondaryFn, phase: .down),
            SystemKeyboard.stroke(keyCode: rightArrow, flags: .maskSecondaryFn, phase: .up),
        ])
        rig.clock.advance(by: .seconds(3))
        await rig.send(rig.hands.letGo(.function))
        #expect(rig.inserter.received == [chordTidied])
    }

    @Test(
        "⌥Space and ⇧⌘V still dictate the moment their key goes down",
        arguments: [
            (HotkeyBinding.optionSpace, [ModifierKey.option], spaceKey),
            (HotkeyBinding.shiftCommandV, [ModifierKey.shift, .command], vKey),
        ] as [(HotkeyBinding, [ModifierKey], UInt16)])
    fileprivate func combinationsUnchanged(
        _ binding: HotkeyBinding, _ modifiers: [ModifierKey], _ keyCode: UInt16
    ) async throws {
        let rig = try await Rig.make(binding, .holdToTalk)
        for key in modifiers { await rig.send(rig.hands.hold(key)) }
        await rig.send([rig.hands.type(keyCode)[0]])
        #expect(await rig.isListening)

        rig.clock.advance(by: .seconds(3))
        for key in modifiers { await rig.send(rig.hands.letGo(key)) }
        #expect(rig.inserter.received == [chordTidied])
    }
}
