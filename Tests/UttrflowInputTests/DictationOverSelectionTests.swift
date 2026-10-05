import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowInput

/// Records what the typed route sends, including any deletion it would make first.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let log = Mutex<(typed: [String], deleted: [Int])>(([], []))

    var typed: [String] { log.withLock { $0.typed } }
    var deleted: [Int] { log.withLock { $0.deleted } }

    func type(_ text: String) throws(TextInsertionError) { log.withLock { $0.typed.append(text) } }
    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        log.withLock { $0.deleted.append(count) }
    }
}

/// Each route replaces a selection the person left, as `Docs/insertion.md` decides, and never moves it first.
@Suite("Dictating over a selection")
struct DictationOverSelectionTests {
    @Test("The Accessibility route replaces the selection in one write, without moving it")
    func accessibilityReplaces() throws {
        let field = FakeSelectionField("Keep this paragraph here", caret: 5, length: 14)
        try SelectionWriter(field: field).replaceSelection(with: "that")
        #expect(field.text == "Keep that here")
        #expect(field.textWrites == ["that"])
        #expect(field.selectionWrites.isEmpty)
    }

    @Test("The typed route sends only the words, so the field's own typing replaces the selection")
    func typedSendsOnlyTheWords() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(field: FakeTextField()), typist: typist)
        _ = try await engine.insert("that")
        #expect(typist.typed.joined() == "that")
        #expect(typist.deleted.isEmpty)
    }

    @Test("The paste route posts one paste, so the field's own paste replaces the selection")
    func pastePostsOnce() async throws {
        let keystrokes = FakeKeystrokeSender()
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: FakePasteboard(),
            keystrokes: keystrokes)
        _ = try await engine.insert("that")
        #expect(keystrokes.pasteCount == 1)
    }
}
