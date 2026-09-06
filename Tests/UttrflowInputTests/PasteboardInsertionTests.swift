import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A clipboard that records everything written to it and never touches the real one.
final class FakePasteboard: Pasteboard {
    private struct State {
        var text: String?
        var changeCount = 0
        var setTextCalls: [String] = []
        var acceptsWrites = true
    }

    private let state = Mutex(State())

    /// acceptsWrites: `false` models a clipboard that takes the write and
    ///   then does not hold it, which is how a failed copy looks from the outside.
    init(text: String? = nil, acceptsWrites: Bool = true) {
        state.withLock { state in
            state.text = text
            state.acceptsWrites = acceptsWrites
        }
    }

    func text() -> String? { state.withLock(\.text) }

    func setText(_ text: String) {
        state.withLock { state in
            state.setTextCalls.append(text)
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

    var setTextCalls: [String] { state.withLock(\.setTextCalls) }
}

/// A ⌘V that can be counted, and made to fail.
final class FakeKeystrokeSender: KeystrokeSender {
    private struct State {
        var pasteCount = 0
        var error: TextInsertionError?
        var onPaste: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    /// onPaste: runs inside `sendPaste`, the only moment between the
    ///   engine writing the clipboard and reading it back.
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

    /// Declines only for Uttrflow itself. Anywhere else is worth attempting: a paste
    /// into an application that will not take one leaves the words on the clipboard,
    /// which is exactly what the strategy below would do anyway, whereas declining
    /// guarantees the user has to paste by hand. Editors built on Electron expose no
    /// focused element and take a ⌘V perfectly well, and the earlier, stricter check
    /// refused them.
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

        #expect(pasteboard.setTextCalls.first == "hello there")
        #expect(keystrokes.pasteCount == 1)
    }

    /// The dictation stays on the clipboard, and the user's previous contents do not
    /// come back. That is a reversal, and it is deliberate.
    ///
    /// Nothing can tell whether the ⌘V landed — `post` reports nothing and the target
    /// application need not react — so restoring is a bet, and it was the wrong way
    /// round. When the paste worked the user lost a clipboard they can usually recreate;
    /// when it did not they lost the words they had just spoken, from the document and
    /// the clipboard both, while the app reported success. §19 settles it: the words
    /// survive, and the previous clipboard is what it costs.
    @Test("leaves the dictation on the clipboard rather than betting the paste landed")
    func keepsTheDictationOnTheClipboard() async throws {
        let paragraph = "A paragraph the user copied earlier and still needs."
        let pasteboard = FakePasteboard(text: paragraph)

        try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

        #expect(pasteboard.setTextCalls == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// Restoring over a copy the user made after dictating would be the same theft in
    /// the other direction, so a changed clipboard is left exactly as it is.
    @Test("leaves a newer copy alone instead of restoring over it")
    func skipsRestoreWhenSomethingElseCopied() async throws {
        let pasteboard = FakePasteboard(text: "the old paragraph")
        let keystrokes = FakeKeystrokeSender(
            onPaste: { pasteboard.copyFromAnotherApp("something copied since") }
        )

        try await engine(pasteboard, keystrokes).insert("dictated words")

        #expect(pasteboard.setTextCalls == ["dictated words"])
        #expect(pasteboard.text() == "something copied since")
    }

    /// A clipboard holding an image, or nothing at all, reads as `nil` text — there is
    /// no paragraph to hand back and inventing an empty one would erase the image.
    @Test("restores nothing when the clipboard was not holding text")
    func nothingToRestore() async throws {
        let pasteboard = FakePasteboard(text: nil)

        try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

        #expect(pasteboard.setTextCalls == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// A refused keystroke is the case where keeping the words matters most: the
    /// coordinator is about to fall through to the floor, and the floor would only put
    /// the same text back.
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

        #expect(pasteboard.setTextCalls == [""])
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

        #expect(pasteboard.setTextCalls == ["dictated words"])
        #expect(pasteboard.text() == "dictated words")
    }

    /// The words are only safe if they are really on the clipboard; claiming success
    /// after a write that did not stick would lose them silently.
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

    /// Not `.pasteboard`. That value means a paste landed in the user's document; this
    /// one means nothing was typed and the words are waiting on the clipboard. Reporting
    /// the same value for both is what let the interface say "Inserted" for a dictation
    /// that never reached the screen.
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
