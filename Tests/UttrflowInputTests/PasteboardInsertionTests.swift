import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A clipboard that records everything written to it and never touches the real one.
final class FakePasteboard: Pasteboard {
    private struct State {
        var text: String?
        var changeCount = 0
        var writes: [String] = []
        var acceptsWrites = true
    }

    private let state = Mutex(State())

    /// `acceptsWrites: false` models a clipboard that takes the write and then does not hold it.
    init(text: String? = nil, acceptsWrites: Bool = true) {
        state.withLock { state in
            state.text = text
            state.acceptsWrites = acceptsWrites
        }
    }

    func text() -> String? { state.withLock(\.text) }

    func setText(_ text: String) {
        state.withLock { state in
            state.writes.append(text)
            state.changeCount += 1
            if state.acceptsWrites { state.text = text }
        }
    }

    /// Stands in for another app copying something while the paste is in flight.
    func copyFromAnotherApp(_ text: String) {
        state.withLock { state in
            state.text = text
            state.changeCount += 1
        }
    }

    var writes: [String] { state.withLock(\.writes) }
}

/// A ⌘V that can be counted, and made to fail.
final class FakeKeystrokeSender: KeystrokeSender {
    private struct State {
        var pasteCount = 0
        var error: TextInsertionError?
        var onPaste: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    /// `onPaste` runs inside `sendPaste`, between the engine writing the clipboard and reading it back.
    init(error: TextInsertionError? = nil, onPaste: (@Sendable () -> Void)? = nil) {
        state.withLock { state in
            state.error = error
            state.onPaste = onPaste
        }
    }

    func sendPaste() throws(TextInsertionError) {
        let (error, onPaste) = state.withLock {
            state -> (TextInsertionError?, (@Sendable () -> Void)?) in
            state.pasteCount += 1
            return (state.error, state.onPaste)
        }
        onPaste?()
        if let error { throw error }
    }

    var pasteCount: Int { state.withLock(\.pasteCount) }
}

@Suite("PasteboardTextInsertionEngine")
struct PasteboardTextInsertionEngineTests {
    private func engine(
        _ pasteboard: FakePasteboard,
        _ keystrokes: FakeKeystrokeSender,
        focus: any AccessibilityFocus = FakeFocus(field: FakeTextField())
    ) -> PasteboardTextInsertionEngine {
        PasteboardTextInsertionEngine(
            focus: focus, pasteboard: pasteboard, keystrokes: keystrokes)
    }

    /// Declining costs the user an insertion where trying costs nothing. See `Docs/input-paste-eligibility.md`.
    @Test("declines only when Uttrflow itself is in front")
    func declinesOnlyForItself() async {
        let elsewhere = engine(FakePasteboard(), FakeKeystrokeSender(), focus: FakeFocus(field: nil))
        #expect(await elsewhere.canInsert(), "nothing focused is still worth a try")

        let ourselves = engine(
            FakePasteboard(), FakeKeystrokeSender(), focus: FakeFocus(field: nil, isSelf: true))
        #expect(await ourselves.canInsert() == false, "must never paste into Uttrflow")
    }

    @Test("accepts when something is focused")
    func acceptsWithAFocusedField() async {
        #expect(await engine(FakePasteboard(), FakeKeystrokeSender()).canInsert())
    }

    @Test("copies the text and presses paste exactly once")
    func pastesOnce() async throws {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()

        try await engine(pasteboard, keystrokes).insert("hello there")

        #expect(pasteboard.writes.first == "hello there")
        #expect(keystrokes.pasteCount == 1)
    }

    /// The dictation stays put and the previous contents do not come back. See `Docs/insertion.md`.
    @Test("leaves the dictation on the clipboard rather than betting the paste landed")
    func keepsTheDictationOnTheClipboard() async throws {
        let paragraph = "A paragraph the user copied earlier and still needs."
        let pasteboard = FakePasteboard(text: paragraph)

        try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

        #expect(pasteboard.writes == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// Writing over a copy the user made since would be the same theft in the other direction.
    @Test("leaves a copy made since the paste exactly as it is")
    func leavesANewerCopyAlone() async throws {
        let pasteboard = FakePasteboard(text: "the old paragraph")
        let keystrokes = FakeKeystrokeSender(
            onPaste: { pasteboard.copyFromAnotherApp("something copied since") }
        )

        try await engine(pasteboard, keystrokes).insert("dictated words")

        #expect(pasteboard.writes == ["dictated words"])
        #expect(pasteboard.text() == "something copied since")
    }

    /// A clipboard holding an image reads as `nil` text, and inventing an empty one would erase it.
    @Test("keeps the words when the clipboard was not holding text")
    func keepsWordsWhenTheClipboardHeldNothing() async throws {
        let pasteboard = FakePasteboard(text: nil)

        try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

        #expect(pasteboard.writes == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// Where keeping the words matters most: the floor below would only put the same text back.
    @Test("keeps the words on the clipboard even when the keystroke is refused")
    func keepsWordsAfterFailedPaste() async {
        let pasteboard = FakePasteboard(text: "A paragraph the user copied earlier.")
        let keystrokes = FakeKeystrokeSender(error: .accessibilityDenied)
        let sut = engine(pasteboard, keystrokes)

        await #expect(throws: TextInsertionError.accessibilityDenied) {
            try await sut.insert("dictated words")
        }

        #expect(keystrokes.pasteCount == 1)
        #expect(pasteboard.text() == "dictated words", "the dictation must outlive the failure")
    }

    @Test("copies an empty transcript without inventing anything")
    func emptyText() async throws {
        let pasteboard = FakePasteboard(text: "previous")

        try await engine(pasteboard, FakeKeystrokeSender()).insert("")

        #expect(pasteboard.writes == [""])
    }

    @Test("reports itself as the pasteboard method")
    func method() {
        let sut = engine(FakePasteboard(), FakeKeystrokeSender())
        #expect(sut.method == .pasteboard)
    }

}

@Suite("ClipboardTextInsertionEngine")
struct ClipboardTextInsertionEngineTests {
    @Test("leaves the text on the clipboard for the user to paste")
    func setsTheText() async throws {
        let pasteboard = FakePasteboard(text: "previous")
        try await ClipboardTextInsertionEngine(pasteboard: pasteboard).insert("dictated words")

        #expect(pasteboard.writes == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// Claiming success after a write that did not stick would lose the words silently.
    @Test("reports the clipboard as unavailable when the write does not stick")
    func failedWrite() async {
        let pasteboard = FakePasteboard(acceptsWrites: false)
        let sut = ClipboardTextInsertionEngine(pasteboard: pasteboard)

        await #expect(throws: TextInsertionError.clipboardUnavailable) {
            try await sut.insert("dictated words")
        }
    }

    @Test("copies an empty transcript without complaining")
    func emptyText() async throws {
        let pasteboard = FakePasteboard()
        try await ClipboardTextInsertionEngine(pasteboard: pasteboard).insert("")

        #expect(pasteboard.text() == "")
    }

    /// Not `.pasteboard`: that value means a paste landed, this one that the words are waiting.
    @Test("reports itself as the clipboard method, not a completed paste")
    func method() {
        #expect(ClipboardTextInsertionEngine(pasteboard: FakePasteboard()).method == .clipboard)
    }

    /// This is the last resort in the fallback chain, so it must never decline.
    @Test("is always available, because a clipboard always is")
    func alwaysCanInsert() async {
        #expect(await ClipboardTextInsertionEngine(pasteboard: FakePasteboard()).canInsert())
    }
}
