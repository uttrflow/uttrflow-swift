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

    /// How an app that hides its text fields from Accessibility gets served: the strategy declines.
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

    /// Which strategy carried the text, not merely that one did, because the harness counts them.
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

    /// The last failure is the reason the user has nothing; the earlier refusals are routine.
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

    /// The text is the user's own words, so trimming or re-encoding it would change what was said.
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

    /// Structural, not caller discipline: this write reaches no further than the selection.
    @Test("can only ever replace the selection, never the whole field")
    func replacesOnlyTheSelection() async throws {
        let field = FakeTextField(before: "Dear ", selected: "Bob", after: ", thanks for the note.")
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.insert("Alice")

        #expect(field.contents == "Dear Alice, thanks for the note.")
        #expect(field.replacements == ["Alice"], "the selection is the only thing it may write to")
    }

    /// The same operation covers a caret with nothing selected: an empty selection replaced is an insert.
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

/// An insertion strategy that records the text handed to it and fails on demand.
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

/// A text field modelled as text on either side of a selection, so a test can see both survive.
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
    let field: (any FocusedTextField)?
    /// Separate from `field`, for an app that has something focused and will not report its selection.
    var somethingFocused: Bool?
    var isSelf = false
    /// What lies before the caret, for a field that will say but has no whole `value`.
    var preceding: String?
    /// The field's whole contents, read with the caret at its end.
    var value: String?

    init(
        field: (any FocusedTextField)? = nil,
        somethingFocused: Bool? = nil,
        isSelf: Bool = false,
        preceding: String? = nil,
        value: String? = nil
    ) {
        self.field = field
        self.somethingFocused = somethingFocused
        self.isSelf = isSelf
        self.preceding = preceding
        self.value = value
    }

    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { somethingFocused ?? (field != nil) }
    func isSelfFrontmost() -> Bool { isSelf }
    func precedingText(_ count: Int) -> String? {
        guard let value else { return preceding }
        return BackwardSelection.text(in: value, endingAt: value.utf16.count, covering: count)
    }
}

/// The case the whole fallback chain exists for. See `Docs/input-paste-eligibility.md`.
@Suite("An app that takes a paste but will not report its selection")
struct PasteOnlyApplicationTests {
    @Test("is pasted into, not dropped on the clipboard")
    func pasteWins() async throws {
        // Nothing readable as a text field, but something is focused.
        let focus = FakeFocus(field: nil, somethingFocused: true)
        let keystrokes = FakeKeystrokeSender()
        let coordinator = TextInsertion.coordinator(
            focus: focus, pasteboard: FakePasteboard(), keystrokes: keystrokes)

        let method = try await coordinator.insert("hello there")

        #expect(method == .pasteboard, "the words should have been pasted, not abandoned")
        #expect(keystrokes.pasteCount == 1)
    }

    @Test("falls to the clipboard only when the paste itself is refused")
    func clipboardWhenThePasteIsRefused() async throws {
        let keystrokes = FakeKeystrokeSender(error: .accessibilityDenied)
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: nil, somethingFocused: false),
            pasteboard: FakePasteboard(), keystrokes: keystrokes)

        #expect(try await coordinator.insert("hello there") == .clipboard)
        #expect(keystrokes.pasteCount == 1, "it should have tried before giving up")
    }
}

@Suite("The assembled strategies")
struct TextInsertionAssemblyTests {
    /// The keystroke is refused, so the chain is driven all the way to the floor this suite exercises.
    private func coordinator() -> TextInsertionCoordinator {
        TextInsertion.coordinator(
            focus: FakeFocus(),
            pasteboard: FakePasteboard(),
            keystrokes: FakeKeystrokeSender(error: .accessibilityDenied))
    }

    /// Accessibility writes at the caret and touches nothing; the clipboard last cannot fail.
    @Test("tries the strategies in the order the product needs")
    func order() {
        #expect(coordinator().route == [.accessibility, .pasteboard, .clipboard])
    }

    /// §19: a user must never lose words to a failed insertion, so the last strategy cannot fail.
    @Test("ends in a strategy that cannot fail")
    func endsInAGuaranteedStrategy() async throws {
        #expect(coordinator().route.last == .clipboard)
        // `.clipboard`, not `.pasteboard`: the floor says the words are waiting, not that a paste landed.
        #expect(try await coordinator().insert("hello") == .clipboard)
    }
}
