import Foundation
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowInput

/// A secret clip reaches the clipboard marked concealed, whichever route carries it and whatever field is in front.
@Suite("Inserting a secret through a concealing pasteboard", .timeLimit(.minutes(1)))
struct ConcealingPasteboardTests {
    @Test("a plain or formatted write goes up marked")
    func writesAreConcealed() {
        let pasteboard = FakePasteboard()
        let concealing = ConcealingPasteboard(pasteboard)

        #expect(concealing.setText("sk-live-abcdef123456").didWrite)
        #expect(concealing.setText("sk-live-abcdef123456", richText: "<b>sk-live-abcdef123456</b>").didWrite)

        #expect(pasteboard.concealed == ["sk-live-abcdef123456", "sk-live-abcdef123456"])
        #expect(concealing.text() == "sk-live-abcdef123456")
    }

    @Test("the paste route leaves a secret marked in an ordinary field")
    func pasteRouteConceals() async throws {
        let pasteboard = FakePasteboard()
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: ConcealingPasteboard(pasteboard),
            keystrokes: FakeKeystrokeSender())

        _ = try await engine.insert("sk-live-abcdef123456", richText: "<b>key</b>")

        #expect(pasteboard.concealed == ["sk-live-abcdef123456"])
    }

    @Test("the clipboard floor leaves a secret marked in an ordinary field")
    func floorConceals() async throws {
        let pasteboard = FakePasteboard()
        let engine = ClipboardTextInsertionEngine(
            pasteboard: ConcealingPasteboard(pasteboard), focus: FakeFocus(field: nil))

        _ = try await engine.insert("sk-live-abcdef123456")

        #expect(pasteboard.concealed == ["sk-live-abcdef123456"])
    }

    @Test("the built route never writes a secret unmarked")
    func builtRouteConceals() async throws {
        let pasteboard = FakePasteboard()
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: nil, isSelf: true), pasteboard: ConcealingPasteboard(pasteboard),
            keystrokes: FakeKeystrokeSender())

        _ = try await coordinator.insert("sk-live-abcdef123456")

        #expect(!pasteboard.writes.isEmpty)
        #expect(pasteboard.concealed == pasteboard.writes)
    }

    @Test("a concealed write leaves the clipboard after the chosen delay")
    func writeIsCleared() async throws {
        let pasteboard = FakePasteboard()
        let waits = Mutex<[Duration]>([])
        let clear = ConcealedClipboardClear(sleep: { duration in waits.withLock { $0.append(duration) } })
        let concealing = ConcealingPasteboard(pasteboard, clearingAfter: { 60 }, clear: clear)

        #expect(concealing.writeConcealedText("sk-live-abcdef123456").didWrite)

        #expect(try await Self.cleared(pasteboard))
        #expect(waits.withLock { $0 } == [.seconds(60)])
    }

    @Test("clearing off, or a refused write, schedules no clear")
    func offOrRefusedSchedulesNothing() {
        let never = ConcealedClipboardClear(sleep: { _ in Issue.record("a clear was scheduled") })
        let pasteboard = FakePasteboard()
        let off = ConcealingPasteboard(pasteboard, clearingAfter: { 0 }, clear: never)
        let refusing = ConcealingPasteboard(
            FakePasteboard(refusesWrites: true), clearingAfter: { 60 }, clear: never)

        #expect(off.writeConcealedText("sk-live-abcdef123456").didWrite)
        #expect(!refusing.writeConcealedText("sk-live-abcdef123456").didWrite)

        #expect(pasteboard.text() == "sk-live-abcdef123456")
    }

    @Test("a pasted secret stays on the clipboard, since the paste route puts no earlier copy back")
    func pasteRouteRestoresNothing() async throws {
        let pasteboard = FakePasteboard()
        pasteboard.enableSnapshots()
        pasteboard.copyFromAnotherApp("copied earlier")
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: ConcealingPasteboard(pasteboard),
            keystrokes: FakeKeystrokeSender(), confirmsArrival: false, keepsWordsWhenRefused: false)

        _ = try await engine.insert("sk-live-abcdef123456")

        #expect(pasteboard.text() == "sk-live-abcdef123456")
    }

    @Test("a secret pasted from the panel leaves the clipboard after the delay")
    func pastedSecretIsCleared() async throws {
        let pasteboard = FakePasteboard()
        let (delay, elapse) = AsyncStream<Void>.makeStream()
        let clear = ConcealedClipboardClear(sleep: { _ in for await _ in delay {} })
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()),
            pasteboard: ConcealingPasteboard(pasteboard, clearingAfter: { 60 }, clear: clear),
            keystrokes: FakeKeystrokeSender(), confirmsArrival: false, keepsWordsWhenRefused: false)

        _ = try await engine.insert("sk-live-abcdef123456")
        #expect(pasteboard.text() == "sk-live-abcdef123456")
        elapse.finish()

        #expect(try await Self.cleared(pasteboard))
        #expect(pasteboard.concealed == ["sk-live-abcdef123456"])
    }

    /// Whether the clear, which runs off the test's task, has emptied the clipboard; the suite's time limit ends a clear that never comes.
    private static func cleared(_ pasteboard: FakePasteboard) async throws -> Bool {
        try await eventually { pasteboard.text() == nil }
        return pasteboard.text() == nil
    }
}
