import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("TextInsertionCoordinator")
struct TextInsertionCoordinatorTests {
    @Test("uses the first strategy that works and does not run the ones beneath it")
    func picksFirstWorkingStrategy() async throws {
        let first = StubInsertionEngine(method: .accessibility)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [first, floor])

        let method = try await coordinator.insert("hello")

        #expect(method == .accessibility)
        #expect(first.insertCount == 1)
        #expect(floor.insertCount == 0, "the floor must not run when the first strategy works")
    }

    /// This is how an app that hides its text fields from Accessibility gets served:
    /// the strategy declines, and nothing about the text changes.
    @Test("steps around a strategy that cannot insert into what is focused")
    func skipsStrategyThatCannotInsert() async throws {
        let declining = StubInsertionEngine(method: .accessibility, canInsert: false)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [declining, floor])

        let method = try await coordinator.insert("hello")

        #expect(method == .pasteboard)
        #expect(declining.insertCount == 0, "a strategy that declined must not be handed the text")
    }

    @Test("falls through when a strategy accepts the text and then fails")
    func fallsThroughOnFailure() async throws {
        let failing = StubInsertionEngine(method: .accessibility, error: .accessibilityDenied)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [failing, floor])

        let method = try await coordinator.insert("hello")

        #expect(method == .pasteboard)
        #expect(failing.insertCount == 1, "it should have been tried before falling through")
    }

    /// The caller is told how the text arrived, not merely that it did, because the
    /// evaluation harness needs to know which strategy carries real traffic.
    @Test("reports the method the text actually arrived by", arguments: TextInsertionMethod.allCases)
    func reportsSucceedingMethod(method: TextInsertionMethod) async throws {
        let coordinator = TextInsertionCoordinator(strategies: [StubInsertionEngine(method: method)])

        #expect(try await coordinator.insert("hello") == method)
    }

    @Test("lists the strategies it will try, in the order it will try them")
    func routeIsInOrder() {
        let coordinator = TextInsertionCoordinator(
            strategies: [
                StubInsertionEngine(method: .pasteboard), StubInsertionEngine(method: .accessibility),
            ]
        )

        #expect(coordinator.route == [.pasteboard, .accessibility])
    }

    /// The earlier failures are the expected ones — a strategy declining is routine.
    /// The last one is the reason the user has nothing, so it is the one worth showing.
    @Test("reports the last strategy's reason when every strategy failed, not the first")
    func reportsTheLastFailure() async {
        let coordinator = TextInsertionCoordinator(
            strategies: [
                StubInsertionEngine(method: .accessibility, error: .accessibilityDenied),
                StubInsertionEngine(
                    method: .pasteboard, error: .insertionRejected(description: "the clipboard was busy")
                ),
            ]
        )

        await #expect(throws: TextInsertionError.insertionRejected(description: "the clipboard was busy")) {
            try await coordinator.insert("hello")
        }
    }

    @Test("reports that there was nowhere to type when the last strategy declined")
    func reportsDeclineFromTheLastStrategy() async {
        let coordinator = TextInsertionCoordinator(
            strategies: [
                StubInsertionEngine(method: .accessibility, error: .accessibilityDenied),
                StubInsertionEngine(method: .pasteboard, canInsert: false),
            ]
        )

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await coordinator.insert("hello")
        }
    }

    @Test("reports the clipboard as unavailable when it was given nothing to try")
    func noStrategies() async {
        let coordinator = TextInsertionCoordinator(strategies: [])

        #expect(coordinator.route.isEmpty)
        await #expect(throws: TextInsertionError.clipboardUnavailable) {
            try await coordinator.insert("hello")
        }
    }

    /// The text is the user's own words. A coordinator that trimmed, re-encoded, or
    /// re-wrapped them on the way past would have changed what was said.
    @Test("hands every strategy it tries the exact text it was given")
    func passesTextThroughUnmodified() async throws {
        let text = "  नमस्ते — \"quoted\" & <angled>,\nsecond line\t "
        let failing = StubInsertionEngine(method: .accessibility, error: .accessibilityDenied)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [failing, floor])

        try await coordinator.insert(text)

        #expect(failing.receivedText == [text])
        #expect(floor.receivedText == [text])
    }
}

@Suite("AccessibilityTextInsertionEngine")
struct AccessibilityTextInsertionEngineTests {
    @Test("can insert only when something that takes text is focused", arguments: [true, false])
    func canInsertFollowsFocus(isFocused: Bool) async {
        let engine = AccessibilityTextInsertionEngine(
            focus: FakeFocus(field: isFocused ? FakeTextField() : nil)
        )

        let canInsert = await engine.canInsert()

        #expect(canInsert == isFocused)
    }

    @Test("reports that there is no text field rather than dropping the words")
    func insertWithoutAFocusedField() async {
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: nil))

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.insert("hello")
        }
    }

    @Test("writes the exact text into the focused field")
    func writesExactText() async throws {
        let field = FakeTextField()
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.insert("नमस्ते, world")

        #expect(field.replacements == ["नमस्ते, world"])
    }

    @Test("passes on a failure the field itself reported")
    func propagatesFailureFromTheField() async {
        let field = FakeTextField(error: .insertionRejected(description: "the field is read-only"))
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        await #expect(throws: TextInsertionError.insertionRejected(description: "the field is read-only")) {
            try await engine.insert("hello")
        }
    }

    /// Structural, not caller discipline: dictation calls the write that reaches no further than the selection.
    @Test("can only ever replace the selection, never the whole field")
    func replacesOnlyTheSelection() async throws {
        let field = FakeTextField(before: "Dear ", selected: "Bob", after: ", thanks for the note.")
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.insert("Alice")

        #expect(field.contents == "Dear Alice, thanks for the note.")
        #expect(field.replacements == ["Alice"], "the selection is the only thing it may write to")
    }

    /// The same one operation covers the ordinary case, where the user has a caret and
    /// has selected nothing: an empty selection replaced by the text is an insertion.
    @Test("inserts at the caret when the user has selected nothing")
    func insertsAtTheCaret() async throws {
        let field = FakeTextField(before: "Dear ", selected: "", after: ", thanks for the note.")
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.insert("Alice")

        #expect(field.contents == "Dear Alice, thanks for the note.")
    }

    @Test("identifies itself as the accessibility method")
    func reportsItsMethod() {
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: nil))

        #expect(engine.method == .accessibility)
    }
}

// MARK: - Test doubles

/// An insertion strategy that records what it was asked to insert and fails on demand.
final class StubInsertionEngine: TextInsertionEngine {
    let method: TextInsertionMethod

    private struct State {
        var canInsert: Bool
        var error: TextInsertionError?
        var received: [String] = []
    }

    private let state: Mutex<State>

    init(method: TextInsertionMethod, canInsert: Bool = true, error: TextInsertionError? = nil) {
        self.method = method
        self.state = Mutex(State(canInsert: canInsert, error: error))
    }

    func canInsert() async -> Bool {
        state.withLock { $0.canInsert }
    }

    func insert(_ text: String) async throws(TextInsertionError) {
        let error = state.withLock { state -> TextInsertionError? in
            state.received.append(text)
            return state.error
        }
        if let error { throw error }
    }

    var insertCount: Int { state.withLock { $0.received.count } }
    var receivedText: [String] { state.withLock { $0.received } }
}

/// A text field modelled as text on either side of a selection.
///
/// Keeping the surroundings in the model is what lets a test observe that they survived
/// an insertion, rather than only that the right call was made.
final class FakeTextField: FocusedTextField {
    private struct State {
        var before: String
        var selected: String
        var after: String
        var error: TextInsertionError?
        var replacements: [String] = []
    }

    private let state: Mutex<State>

    init(
        before: String = "",
        selected: String = "",
        after: String = "",
        error: TextInsertionError? = nil
    ) {
        self.state = Mutex(State(before: before, selected: selected, after: after, error: error))
    }

    func replaceSelection(with text: String) throws(TextInsertionError) {
        let error = state.withLock { state -> TextInsertionError? in
            state.replacements.append(text)
            if state.error == nil { state.selected = text }
            return state.error
        }
        if let error { throw error }
    }

    /// Everything the field holds, so a test can see what an insertion left behind.
    var contents: String { state.withLock { $0.before + $0.selected + $0.after } }
    var replacements: [String] { state.withLock { $0.replacements } }
}

/// Focus that reports whichever field a test hands it, or nothing focused at all.
struct FakeFocus: AccessibilityFocus {
    let field: FakeTextField?
    var isSelf = false
    /// Separate from `field`, so a test can describe the case that matters most: an app
    /// that has something focused but will not report its selection. That is where the
    /// accessibility strategy fails and pasting must still be allowed to try.
    var somethingFocused: Bool?

    init(field: FakeTextField?, somethingFocused: Bool? = nil, isSelf: Bool = false) {
        self.field = field
        self.somethingFocused = somethingFocused
        self.isSelf = isSelf
    }

    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { somethingFocused ?? (field != nil) }
    func isSelfFrontmost() -> Bool { isSelf }
}

/// The case the whole fallback chain exists for, and the one that broke it.
///
/// Electron apps, web views and anything drawing its own text commonly expose a focused
/// element while refusing to report its selection. Accessibility insertion cannot work
/// there; pasting works fine. When pasting asked the same question accessibility had
/// just failed — "can you report your selection?" — every one of those apps fell through
/// to the clipboard, and the user saw their dictation not appear.
@Suite("An app that takes a paste but will not report its selection")
struct PasteOnlyApplicationTests {
    private final class RecordingPasteboard: Pasteboard, @unchecked Sendable {
        private let held = Mutex<String?>(nil)
        func text() -> String? { held.withLock { $0 } }
        func setText(_ text: String) { held.withLock { $0 = text } }
        func changeCount() -> Int { 0 }
    }

    private final class CountingKeystrokes: KeystrokeSender, @unchecked Sendable {
        private let count = Mutex(0)
        private let error: TextInsertionError?
        init(error: TextInsertionError? = nil) { self.error = error }
        var pasted: Int { count.withLock { $0 } }
        func sendPaste() throws(TextInsertionError) {
            count.withLock { $0 += 1 }
            if let error { throw error }
        }
    }

    @Test("is pasted into, not dropped on the clipboard")
    func pasteWins() async throws {
        // Nothing readable as a text field, but something is focused.
        let focus = FakeFocus(field: nil, somethingFocused: true)
        let keystrokes = CountingKeystrokes()
        let coordinator = TextInsertion.coordinator(
            focus: focus, pasteboard: RecordingPasteboard(), keystrokes: keystrokes)

        let method = try await coordinator.insert("hello there")

        #expect(method == .pasteboard, "the words should have been pasted, not abandoned")
        #expect(keystrokes.pasted == 1)
    }

    @Test("falls to the clipboard only when the paste itself is refused")
    func clipboardWhenThePasteIsRefused() async throws {
        let keystrokes = CountingKeystrokes(error: .accessibilityDenied)
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: nil, somethingFocused: false),
            pasteboard: RecordingPasteboard(), keystrokes: keystrokes)

        #expect(try await coordinator.insert("hello there") == .clipboard)
        #expect(keystrokes.pasted == 1, "it should have tried before giving up")
    }
}

@Suite("The assembled strategies")
struct TextInsertionAssemblyTests {
    private struct NoFocus: AccessibilityFocus {
        func focusedTextField() -> (any FocusedTextField)? { nil }
        func hasFocusedElement() -> Bool { false }
        func isSelfFrontmost() -> Bool { false }
    }

    /// A clipboard that actually holds what it is given.
    ///
    /// It used to hold nothing, and the suite still passed — because the paste strategy
    /// claimed success into a window with nothing focused, so the floor below was never
    /// reached and the test that exists to prove the floor works never ran it. A
    /// clipboard that cannot store text is not a floor, and asserting against one proved
    /// nothing.
    private final class WorkingPasteboard: Pasteboard, @unchecked Sendable {
        private let held = Mutex<String?>(nil)
        func text() -> String? { held.withLock { $0 } }
        func setText(_ text: String) { held.withLock { $0 = text } }
        func changeCount() -> Int { 0 }
    }

    /// Refuses, so the chain is driven all the way to the floor. A keystroke that
    /// silently succeeds would stop at pasting and leave the floor untested — which is
    /// what this suite exists to exercise.
    private struct RefusedKeystrokes: KeystrokeSender {
        func sendPaste() throws(TextInsertionError) { throw .accessibilityDenied }
    }

    private struct SilentKeystrokes: KeystrokeSender {
        func sendPaste() throws(TextInsertionError) {}
    }

    private func coordinator() -> TextInsertionCoordinator {
        TextInsertion.coordinator(
            focus: NoFocus(), pasteboard: WorkingPasteboard(), keystrokes: RefusedKeystrokes())
    }

    /// Accessibility first because it leaves the clipboard alone and writes at the
    /// caret; the clipboard last because it cannot fail.
    @Test("tries the strategies in the order the product needs")
    func order() {
        #expect(coordinator().route == [.accessibility, .pasteboard, .clipboard])
    }

    /// §19: a user must never lose their words to a failed insertion. The last
    /// strategy exists so that "everything failed" cannot happen.
    @Test("ends in a strategy that cannot fail")
    func endsInAGuaranteedStrategy() async throws {
        #expect(coordinator().route.last == .clipboard)
        // `.clipboard`, not `.pasteboard`: the floor leaves the words on the clipboard
        // and says so, where `.pasteboard` means a paste actually landed. They used to
        // report the same value, so the interface said "Inserted" either way.
        #expect(try await coordinator().insert("hello") == .clipboard)
    }
}
