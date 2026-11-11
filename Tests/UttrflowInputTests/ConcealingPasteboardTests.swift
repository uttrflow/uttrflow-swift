import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A secret clip reaches the clipboard marked concealed, whichever route carries it and whatever field is in front.
@Suite("Inserting a secret through a concealing pasteboard")
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

    @Test("each concealed write hands on its generation, and a refused one hands on nothing")
    func writesAreHandedOn() {
        let handed = Mutex<[Int?]>([])
        let concealing = ConcealingPasteboard(FakePasteboard()) { generation in
            handed.withLock { $0.append(generation) }
        }
        let refusing = ConcealingPasteboard(FakePasteboard(refusesWrites: true)) { _ in
            Issue.record("a refused write was handed on")
        }

        let written = concealing.writeTransientText("sk-live-abcdef123456", richText: nil)
        _ = refusing.writeTransientText("sk-live-abcdef123456", richText: nil)

        #expect(written.didWrite)
        #expect(handed.withLock { $0 } == [written.changeCount])
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
        let written = Mutex<[Int?]>([])
        let concealing = ConcealingPasteboard(pasteboard) { generation in
            written.withLock { $0.append(generation) }
        }
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: concealing,
            keystrokes: FakeKeystrokeSender(), confirmsArrival: false, keepsWordsWhenRefused: false)

        _ = try await engine.insert("sk-live-abcdef123456")
        let generations = written.withLock { $0 }
        for generation in generations {
            let clear = ConcealedClipboardClear(sleep: { _ in })
            _ = await clear.schedule(on: pasteboard, writtenAt: generation, afterSeconds: 60)?.value
        }

        #expect(generations.count == 1)
        #expect(pasteboard.concealed == ["sk-live-abcdef123456"])
        #expect(pasteboard.text() == nil)
    }
}
