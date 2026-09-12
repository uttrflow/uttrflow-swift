import Foundation
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
        var pictures: [Data] = []
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

    /// K4 — a picture write, kept apart from the text ones so a test can tell them apart.
    func setImage(_ data: Data) {
        state.withLock { state in
            state.pictures.append(data)
            state.changeCount += 1
            if state.acceptsWrites { state.text = nil }
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
    var pictures: [Data] { state.withLock(\.pictures) }
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

/// A caret that answers a fixed value and counts how many times it was asked, which is the point of #222.
final class CountingFocus: AccessibilityFocus, @unchecked Sendable {
    private let answer: String
    private let reads = Mutex(0)

    init(answer: String) {
        self.answer = answer
    }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }

    func tail(upTo count: Int) -> FieldTail {
        reads.withLock { $0 += 1 }
        return .text(answer)
    }

    var readCount: Int { reads.withLock { $0 } }
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

        _ = try await engine(pasteboard, keystrokes).insert("hello there")

        #expect(pasteboard.writes.first == "hello there")
        #expect(keystrokes.pasteCount == 1)
    }

    /// The dictation stays put and the previous contents do not come back. See `Docs/insertion.md`.
    @Test("leaves the dictation on the clipboard rather than betting the paste landed")
    func keepsTheDictationOnTheClipboard() async throws {
        let paragraph = "A paragraph the user copied earlier and still needs."
        let pasteboard = FakePasteboard(text: paragraph)

        _ = try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

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

        _ = try await engine(pasteboard, keystrokes).insert("dictated words")

        #expect(pasteboard.writes == ["dictated words"])
        #expect(pasteboard.text() == "something copied since")
    }

    /// A clipboard holding an image reads as `nil` text, and inventing an empty one would erase it.
    @Test("keeps the words when the clipboard was not holding text")
    func keepsWordsWhenTheClipboardHeldNothing() async throws {
        let pasteboard = FakePasteboard(text: nil)

        _ = try await engine(pasteboard, FakeKeystrokeSender()).insert("dictated words")

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

        _ = try await engine(pasteboard, FakeKeystrokeSender()).insert("")

        #expect(pasteboard.writes == [""])
    }

    @Test("reports itself as the pasteboard method")
    func method() {
        let sut = engine(FakePasteboard(), FakeKeystrokeSender())
        #expect(sut.method == .pasteboard)
    }

    /// The engine under a caret that answers, with the wait driven by a clock the test owns.
    private func confirming(
        _ focus: CountingFocus, reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil
    ) -> PasteboardTextInsertionEngine {
        PasteboardTextInsertionEngine(
            focus: focus, pasteboard: FakePasteboard(), keystrokes: FakeKeystrokeSender(),
            confirmation: PasteConfirmation(focus: focus, clock: ScriptedClock()),
            reporting: reporting)
    }

    /// #222: the call was optional-chained behind the reporter, so attaching a logger switched it on.
    @Test("waits for the paste even when nothing is listening for the answer")
    func confirmsWithNoReporterAttached() async throws {
        let focus = CountingFocus(answer: "and then dictated words")

        _ = try await confirming(focus).insert("dictated words")

        #expect(
            focus.readCount > 0,
            "whether a logger is attached must not decide whether the paste is checked")
    }

    /// #222: the answer reached only the optional closure, so nothing upstream could act on it.
    @Test("reports a paste it never saw arrive as unconfirmed rather than as inserted")
    func reportsAnUnconfirmedPaste() async throws {
        let focus = CountingFocus(answer: "something else entirely")

        #expect(try await confirming(focus).insert("dictated words") == .unconfirmed)
    }

    @Test("reports a paste it read back as confirmed")
    func reportsAConfirmedPaste() async throws {
        let focus = CountingFocus(answer: "and then dictated words")

        #expect(try await confirming(focus).insert("dictated words") == .confirmed)
    }

    /// A field that will not say what it holds proves nothing, which is most of them.
    @Test("proves nothing about a field that will not report what it holds")
    func reportsNothingForAnUnreadableField() async throws {
        let sut = engine(FakePasteboard(), FakeKeystrokeSender(), focus: FakeFocus(field: nil))

        #expect(try await sut.insert("dictated words") == .notReported)
    }

    /// The reporter stays an observer: it still sees every answer, and decides none of them.
    @Test("still hands the answer to a reporter that is attached")
    func reportsToAnAttachedLogger() async throws {
        let seen = Mutex<[PasteConfirmation.Outcome]>([])
        let focus = CountingFocus(answer: "and then dictated words")

        _ = try await confirming(focus, reporting: { outcome in seen.withLock { $0.append(outcome) } })
            .insert("dictated words")

        #expect(seen.withLock { $0.count } == 1)
    }
}

@Suite("The route that is assembled without a logger")
struct UnreportedPasteRouteTests {
    /// #222: the clip route is built with no `reporting:`, so it was the one path that checked nothing.
    @Test("checks the paste on the route that nothing is listening to")
    func confirmsWithoutAReporter() async throws {
        let focus = CountingFocus(answer: "and then dictated words")
        let coordinator = TextInsertion.coordinator(
            focus: focus, pasteboard: FakePasteboard(), keystrokes: FakeKeystrokeSender())

        let attempt = try await coordinator.insert("dictated words")

        #expect(attempt == InsertionAttempt(.pasteboard, arrival: .confirmed))
        #expect(focus.readCount > 0, "how the route is composed must not decide what it verifies")
    }
}

@Suite("ClipboardTextInsertionEngine")
struct ClipboardTextInsertionEngineTests {
    @Test("leaves the text on the clipboard for the user to paste")
    func setsTheText() async throws {
        let pasteboard = FakePasteboard(text: "previous")
        _ = try await ClipboardTextInsertionEngine(pasteboard: pasteboard).insert("dictated words")

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
        _ = try await ClipboardTextInsertionEngine(pasteboard: pasteboard).insert("")

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
