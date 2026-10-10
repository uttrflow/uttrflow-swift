// Holds a dictation to one screen read when nothing could have changed the screen, counted at the `ElementTree` seam.

import CoreGraphics
import Synchronization
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowContext
@testable import UttrflowPipeline

/// One text area in another application, read through the same `ElementTree` seam the system read uses.
private final class NotesField: Sendable {
    static let application = FrontmostApplication(
        name: "Notes", bundleIdentifier: "com.example.notes", processIdentifier: 4_242)

    private let state: Mutex<(value: String, reads: Int)>

    init(value: String) { state = Mutex((value, 0)) }

    /// How many whole reads the field's application has been sent.
    var reads: Int { state.withLock { $0.reads } }

    /// The person types: the field's text becomes `value`, the caret at its end.
    func type(_ value: String) { state.withLock { $0.value = value } }

    /// One whole read, as the system read makes it, banked into `sink`.
    func read(into sink: FocusedWindowSink) {
        let source = TreeWindowSource(
            tree: Tree(field: self), app: 1,
            decode: FieldAnswerDecoder(element: { $0 as? Int }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
    }

    /// What element `element` answers to one attribute: 1 is the application, 2 its window, 3 the field.
    fileprivate func answer(_ name: String, of element: Int) -> FieldAnswer {
        state.withLock { state in
            switch (element, name) {
            case (1, "AXFocusedWindow"): return .value(2)
            case (1, "AXFocusedUIElement"):
                state.reads += 1
                return .value(3)
            case (2, "AXTitle"): return .value("Draft")
            case (3, "AXRole"): return .value("AXTextArea")
            case (3, "AXValue"): return .value(state.value)
            case (3, "AXNumberOfCharacters"): return .value(state.value.utf16.count)
            case (3, "AXSelectedTextRange"):
                return .value(CFRange(location: state.value.utf16.count, length: 0))
            default: return .unsupported
            }
        }
    }

    private struct Tree: ElementTree {
        let field: NotesField

        func role(of element: Int) -> String? { nil }
        func isSecure(_ element: Int) -> Bool { false }
        func text(of element: Int) -> String? { nil }
        func children(of element: Int) -> [Int] { [] }
        func parent(of element: Int) -> Int? { nil }
        func frame(of element: Int) -> CGRect? { nil }
        func attribute(_ name: String, of element: Int) -> FieldAnswer { field.answer(name, of: element) }
    }
}

/// The keys and clicks the test sends, and the activation feed it reports a switch through.
private final class Inputs: Sendable {
    private let keys = Mutex(0)
    private let activate = Mutex<(@Sendable (FrontmostApplication) -> Void)?>(nil)

    var count: Int { keys.withLock { $0 } }
    func pressKey() { keys.withLock { $0 += 1 } }
    func observe(_ callback: @escaping @Sendable (FrontmostApplication) -> Void) {
        activate.withLock { $0 = callback }
    }
    func switchTo(_ application: FrontmostApplication) { activate.withLock { $0 }?(application) }
}

/// A dictation into `NotesField` through the real context engine, with keys, clicks and switches the test sends.
private struct Rig {
    let field = NotesField(value: "Dear team")
    let inputs = Inputs()
    let inserter = FakeTextInserter()
    let metrics = RecordingMetricsRecorder()
    let pipeline: DictationPipeline

    init(seconds: Double) {
        let (field, inputs) = (field, inputs)
        let engine = MacContextEngine(
            readFrontmostApplication: { NotesField.application },
            readFocusedWindow: { _, sink in field.read(into: sink) },
            ownBundleIdentifier: "com.example.uttrflow", ownProcessIdentifier: 1,
            countInputs: { inputs.count },
            observeActivations: { callback in
                inputs.observe(callback)
                return ()
            })
        pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.roomTone(seconds: seconds))),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "see you there"))),
            cleaner: FakeTranscriptCleaner(producedBy: .rules), context: engine, inserter: inserter,
            metrics: metrics, clock: ManualClock())
    }

    /// Holds the key until the screen read that starts the dictation is back, does `meanwhile`, then lets go.
    func dictate(meanwhile: () -> Void = {}) async throws {
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 1 }
        meanwhile()
        await pipeline.finishRecording()
    }
}

@Suite(
    "A dictation reads the screen again only when something could have changed it", .timeLimit(.minutes(1)))
struct DictationScreenReadBudgetTests {
    @Test(
        "with no key, click or switch, the reading taken at key-down is the one written against",
        arguments: [2.0, 40.0])
    func noInputMeansOneRead(seconds: Double) async throws {
        let rig = Rig(seconds: seconds)

        try await rig.dictate()

        #expect(rig.field.reads == 1)
        #expect(await rig.metrics.screenReads.map(\.reads) == [1])
        #expect(
            rig.inserter.received.first?.hasPrefix(" ") == true, "padded against the text before the caret")
    }

    @Test("a key pressed while dictating sends the caret to be read again", arguments: [2.0, 40.0])
    func aKeyMeansASecondRead(seconds: Double) async throws {
        let rig = Rig(seconds: seconds)

        try await rig.dictate {
            rig.field.type("Dear team ")
            rig.inputs.pressKey()
        }

        #expect(rig.field.reads == 2)
        #expect(await rig.metrics.screenReads.map(\.reads) == [2])
        #expect(rig.inserter.received.first?.hasPrefix(" ") == false, "padded against the caret as it is now")
    }

    @Test("an application switch while dictating sends the caret to be read again")
    func aSwitchMeansASecondRead() async throws {
        let rig = Rig(seconds: 2)

        try await rig.dictate {
            rig.inputs.switchTo(NotesField.application)
        }

        #expect(rig.field.reads == 2)
        #expect(await rig.metrics.screenReads.map(\.reads) == [2])
    }
}
