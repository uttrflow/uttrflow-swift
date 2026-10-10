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

        let attempt = try await coordinator.insert("hello")

        #expect(attempt.method == .accessibility)
        #expect(first.insertCount == 1)
        #expect(floor.insertCount == 0, "the floor must not run when the first strategy works")
    }

    /// How an app that hides its text fields from Accessibility gets served: the strategy declines.
    @Test("steps around a strategy that cannot insert into what is focused")
    func skipsStrategyThatCannotInsert() async throws {
        let declining = StubInsertionEngine(method: .accessibility, canInsert: false)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [declining, floor])

        let attempt = try await coordinator.insert("hello")

        #expect(attempt.method == .pasteboard)
        #expect(declining.insertCount == 0, "a strategy that declined must not be handed the text")
    }

    @Test("falls through when a strategy accepts the text and then fails")
    func fallsThroughOnFailure() async throws {
        let failing = StubInsertionEngine(method: .accessibility, error: .accessibilityDenied)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [failing, floor])

        let attempt = try await coordinator.insert("hello")

        #expect(attempt.method == .pasteboard)
        #expect(failing.insertCount == 1, "it should have been tried before falling through")
    }

    /// Losing trust hides the field, so without the trust reading the failure reads as "no text field".
    @Test("a dictation after Accessibility is turned off fails as the permission, with settings as recovery")
    func lostTrustIsNamed() async throws {
        let before = TextInsertion.dictation(
            focus: FakeFocus(field: FakeTextField()), typist: SilentTypist())
        _ = try await before.insert("first")

        // As the system typist does once trust is gone: every keystroke is refused.
        let after = TextInsertion.dictation(
            focus: FakeFocus(trusted: false), typist: SilentTypist(refusal: .accessibilityDenied))
        let error = await #expect(throws: TextInsertionError.self) { try await after.insert("second") }

        #expect(error == .accessibilityDenied)
        #expect(error?.recovery == .openSystemSettings(.accessibility))
    }

    /// Which strategy carried the text, not merely that one did, because the harness counts them.
    @Test("reports the method the text actually arrived by", arguments: TextInsertionMethod.allCases)
    func reportsSucceedingMethod(method: TextInsertionMethod) async throws {
        let coordinator = TextInsertionCoordinator(strategies: [StubInsertionEngine(method: method)])

        #expect(try await coordinator.insert("hello").method == method)
    }

    /// #222: what the strategy found out has to survive the fallback, or it reaches nobody.
    @Test("carries what the strategy found out, not only which strategy ran")
    func carriesTheArrival() async throws {
        let coordinator = TextInsertionCoordinator(strategies: [
            StubInsertionEngine(method: .accessibility, canInsert: false),
            StubInsertionEngine(method: .pasteboard, arrival: .unconfirmed),
        ])

        #expect(
            try await coordinator.insert("hello")
                == InsertionAttempt(.pasteboard, arrival: .unconfirmed))
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

    /// #678: Uttrflow itself has focused fields — its own search field is one — and none of them is the destination.
    @Test("refuses to write into Uttrflow's own field even when something is focused")
    func refusesWhenUttrflowIsInFront() async {
        let engine = AccessibilityTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField(), isSelf: true)
        )

        #expect(await engine.canInsert() == false)
    }

    @Test("refuses the write itself when Uttrflow is in front, whatever canInsert said earlier")
    func insertRefusesWhenUttrflowIsInFront() async {
        let field = FakeTextField()
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field, isSelf: true))

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.insert("hello")
        }
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("hello", replacing: "")
        }
        #expect(field.replacements.isEmpty)
    }

    @Test("refuses when the frontmost app changes after the field is captured")
    func refusesWhenTargetChangesBeforeWrite() async {
        let field = FakeTextField()
        let target = InsertionDestination(applicationName: "Editor", bundleIdentifier: "com.example.editor")
        let other = InsertionDestination(applicationName: "Browser", bundleIdentifier: "com.example.browser")
        let focus = TargetRaceFocus(field: field, applications: [target, other])
        let engine = AccessibilityTextInsertionEngine(focus: focus)

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await engine.insert("private text", targeting: target)
        }
        #expect(field.replacements.isEmpty)
    }

    @Test("writes into an application that has a process but no bundle identifier")
    func writesIntoUnbundledApplication() async throws {
        let field = FakeTextField()
        let target = InsertionDestination(
            applicationName: "tool", bundleIdentifier: nil, processIdentifier: 4242)
        let engine = AccessibilityTextInsertionEngine(
            focus: TargetRaceFocus(field: field, applications: [target]))

        _ = try await engine.insert("hello", targeting: target)

        #expect(field.replacements.count == 1)
    }

    @Test("refuses when an unbundled application is replaced by another process of the same name")
    func refusesWhenUnbundledProcessChanges() async {
        let field = FakeTextField()
        let target = InsertionDestination(
            applicationName: "tool", bundleIdentifier: nil, processIdentifier: 4242)
        let other = InsertionDestination(
            applicationName: "tool", bundleIdentifier: nil, processIdentifier: 4343)
        let engine = AccessibilityTextInsertionEngine(
            focus: TargetRaceFocus(field: field, applications: [other]))

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await engine.insert("hello", targeting: target)
        }
        #expect(field.replacements.isEmpty)
    }

    @Test("stops fallback when the captured app is no longer frontmost")
    func targetChangeStopsFallback() async {
        let target = InsertionDestination(applicationName: "Editor", bundleIdentifier: "com.example.editor")
        let other = InsertionDestination(applicationName: "Browser", bundleIdentifier: "com.example.browser")
        let field = FakeTextField()
        let focus = TargetRaceFocus(field: field, applications: [target, other])
        let first = AccessibilityTextInsertionEngine(focus: focus)
        let floor = StubInsertionEngine(method: .pasteboard)
        let coordinator = TextInsertionCoordinator(strategies: [first, floor])

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await coordinator.insert("private text", targeting: target)
        }
        #expect(floor.insertCount == 0)
        #expect(field.replacements.isEmpty)
    }

    @Test("leaves a dictation made over Uttrflow's own field to the clipboard, not to that field")
    func coordinatorFallsPastUttrflowsOwnField() async throws {
        let field = FakeTextField()
        let keystrokes = FakeKeystrokeSender()
        let pasteboard = FakePasteboard()
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: field, isSelf: true), pasteboard: pasteboard,
            keystrokes: keystrokes)

        let attempt = try await coordinator.insert("hello there")

        #expect(attempt.method != .accessibility)
        #expect(field.replacements.isEmpty)
        #expect(keystrokes.pasteCount == 0)
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

        _ = try await engine.insert("नमस्ते, world")

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

        _ = try await engine.insert("Alice")

        #expect(field.contents == "Dear Alice, thanks for the note.")
        #expect(field.replacements == ["Alice"], "the selection is the only thing it may write to")
    }

    /// The same operation covers a caret with nothing selected: an empty selection replaced is an insert.
    @Test("inserts at the caret when the user has selected nothing")
    func insertsAtTheCaret() async throws {
        let field = FakeTextField(before: "Dear ", selected: "", after: ", thanks for the note.")
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        _ = try await engine.insert("Alice")

        #expect(field.contents == "Dear Alice, thanks for the note.")
    }

    @Test("inserts a code completion before the editor's auto-closed parenthesis")
    func completionLeavesTheAutoClosedParenthesisAfterInsertedText() async throws {
        let field = FakeTextField(before: "COUNT(", selected: "", after: ")")
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        _ = try await engine.insert("users")

        #expect(field.contents == "COUNT(users)")
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
    private let arrival: InsertionArrival

    init(
        method: TextInsertionMethod, canInsert: Bool = true, error: TextInsertionError? = nil,
        arrival: InsertionArrival = .notReported
    ) {
        self.method = method
        self.arrival = arrival
        self.state = Mutex(State(canInsert: canInsert, error: error))
    }

    func canInsert() async -> Bool {
        state.withLock { $0.canInsert }
    }

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        let error = state.withLock { state -> TextInsertionError? in
            state.received.append(text)
            return state.error
        }
        if let error { throw error }
        return arrival
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
    /// What is in front at the moment of the write, which a real reader answers from the window server.
    var frontmost: InsertionDestination?
    /// Whether the field hides what is typed.
    var secure = false
    /// Whether macOS still lets this process drive other apps.
    var trusted = true

    init(
        field: (any FocusedTextField)? = nil,
        somethingFocused: Bool? = nil,
        isSelf: Bool = false,
        preceding: String? = nil,
        value: String? = nil,
        frontmost: InsertionDestination? = nil,
        secure: Bool = false,
        trusted: Bool = true
    ) {
        self.secure = secure
        self.trusted = trusted
        self.field = field
        self.somethingFocused = somethingFocused
        self.isSelf = isSelf
        self.preceding = preceding
        self.value = value
        self.frontmost = frontmost
    }

    func focusedTextField() -> (any FocusedTextField)? { field }
    func focusedTextField(in destination: InsertionDestination) -> (any FocusedTextField)? {
        guard frontmost?.bundleIdentifier == destination.bundleIdentifier else { return nil }
        return field
    }
    func hasFocusedElement() -> Bool { somethingFocused ?? (field != nil) }
    func isSelfFrontmost() -> Bool { isSelf }
    func focusedApplication() -> InsertionDestination? { frontmost }
    func focusedFieldIsSecure() -> Bool { secure }
    func isTrusted() -> Bool { trusted }
    func precedingText(_ count: Int) -> String? {
        guard let value else { return preceding }
        return BackwardSelection.text(in: value, endingAt: value.utf16.count, exactly: count)
    }
}

private final class TargetRaceFocus: AccessibilityFocus, Sendable {
    private struct State {
        var index = 0
    }

    private let state = Mutex(State())
    private let field: any FocusedTextField
    private let applications: [InsertionDestination]

    init(field: any FocusedTextField, applications: [InsertionDestination]) {
        self.field = field
        self.applications = applications
    }

    func focusedTextField() -> (any FocusedTextField)? { field }
    func focusedTextField(in destination: InsertionDestination) -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        state.withLock { state in
            let index = min(state.index, applications.count - 1)
            state.index += 1
            return applications[index]
        }
    }
    func precedingText(_ count: Int) -> String? { nil }
    func tail(upTo count: Int) -> FieldTail { .unreadable }
    func focusedFieldIsSecure() -> Bool { false }
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

        let attempt = try await coordinator.insert("hello there")

        #expect(attempt.method == .pasteboard, "the words should have been pasted, not abandoned")
        #expect(keystrokes.pasteCount == 1)
    }

    @Test("falls to the clipboard only when the paste itself is refused")
    func clipboardWhenThePasteIsRefused() async throws {
        let keystrokes = FakeKeystrokeSender(error: .accessibilityDenied)
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: nil, somethingFocused: false),
            pasteboard: FakePasteboard(), keystrokes: keystrokes)

        #expect(try await coordinator.insert("hello there").method == .clipboard)
        #expect(keystrokes.pasteCount == 1, "it should have tried before giving up")
    }
}

/// #1310: a real Accessibility write that lands can still leave the field's whole value looking untouched.
@Suite("Replacing a selection with the words already there")
struct IdenticalSelectionInsertionTests {
    @Test("writes once through Accessibility, and never falls to a paste that would duplicate the words")
    func doesNotDuplicateViaPaste() async throws {
        let field = SelectionWriter(field: FakeSelectionField("same", caret: 0, length: 4))
        let keystrokes = FakeKeystrokeSender()
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: field, somethingFocused: true),
            pasteboard: FakePasteboard(), keystrokes: keystrokes)

        let attempt = try await coordinator.insert("same")

        #expect(attempt.method == .accessibility, "the Accessibility write succeeded and must not be doubted")
        #expect(keystrokes.pasteCount == 0, "a successful same-text replacement must not also be pasted")
    }

    @Test("stops fallback when an accepted Accessibility write has no resulting selection")
    func doesNotDuplicateAnUnconfirmedWrite() async throws {
        let field = SelectionWriter(
            field: FakeSelectionField("hello") {
                $0.reportsSelection = false
            })
        let keystrokes = FakeKeystrokeSender()
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: field, somethingFocused: true),
            pasteboard: FakePasteboard(), keystrokes: keystrokes)

        await #expect(throws: TextInsertionError.insertionUnconfirmed) {
            try await coordinator.insert(" world")
        }

        #expect(field.field.text == "hello world")
        #expect(keystrokes.pasteCount == 0)
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
        #expect(
            TextInsertion.coordinator(
                focus: FakeFocus(), pasteboard: FakePasteboard(),
                keystrokes: FakeKeystrokeSender(), clipboardFallback: false
            ).route
                == [.accessibility, .pasteboard, .typed])
    }

    /// The words arrive seconds after the user was told the dictation failed, in whatever is in front now.
    @Test("writes nothing once the dictation that asked has given up")
    func writesNothingAfterCancellation() async throws {
        let pasteboard = FakePasteboard()
        let field = FakeTextField()
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: field), pasteboard: pasteboard,
            keystrokes: FakeKeystrokeSender())

        let attempt = Task {
            // Cancelled before it runs, which is what a stage that has timed out leaves behind.
            try await coordinator.insert("ship it")
        }
        attempt.cancel()

        await #expect(throws: TextInsertionError.self) { try await attempt.value }
        #expect(field.contents.isEmpty, "the focused field was written into after the dictation ended")
        #expect(pasteboard.text() == nil, "the user's clipboard was taken after the dictation ended")
    }

    /// §19: a user must never lose words to a failed insertion, so the last strategy cannot fail.
    @Test("ends in a strategy that cannot fail")
    func endsInAGuaranteedStrategy() async throws {
        #expect(coordinator().route.last == .clipboard)
        // `.clipboard`, not `.pasteboard`: the floor says the words are waiting, not that a paste landed.
        #expect(try await coordinator().insert("hello").method == .clipboard)
    }

    /// The user may have switched applications since the recording began, so the write is what is asked.
    @Test("names the application that was in front when the words were written")
    func namesWhereTheWordsWent() async throws {
        let slack = InsertionDestination(
            applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let coordinator = TextInsertion.coordinator(
            focus: FakeFocus(field: FakeTextField(), frontmost: slack),
            pasteboard: FakePasteboard(),
            keystrokes: FakeKeystrokeSender())

        #expect(try await coordinator.insert("hello").destination == slack)
    }

    /// A reader that will not say leaves the record to whatever the pipeline already knew.
    @Test("says nothing about the destination when the reader will not")
    func saysNothingWhenTheReaderWillNot() async throws {
        #expect(try await coordinator().insert("hello").destination == nil)
    }

    /// #1550: the words land when the paste is posted, so a switch during the confirmation wait is not credited.
    @Test("names the application in front when the paste was posted, not after the confirmation wait")
    func namesWhereThePasteWasPosted() async throws {
        let focus = SwitchingDuringWaitFocus()
        let engine = PasteboardTextInsertionEngine(
            focus: focus, pasteboard: FakePasteboard(), keystrokes: FakeKeystrokeSender())
        let coordinator = TextInsertionCoordinator(strategies: [engine], focus: focus)

        let attempt = try await coordinator.insert("hello there")

        #expect(attempt.arrival == .confirmed)
        #expect(attempt.destination == SwitchingDuringWaitFocus.target)
    }
}

/// Focus whose frontmost application changes on the first read-back after the paste, as a user switching mid-wait.
final class SwitchingDuringWaitFocus: AccessibilityFocus, @unchecked Sendable {
    static let target = InsertionDestination(
        applicationName: "Editor", bundleIdentifier: "com.example.editor")
    static let other = InsertionDestination(
        applicationName: "Browser", bundleIdentifier: "com.example.browser")
    private let reads = Mutex(0)

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedFieldIsSecure() -> Bool { false }

    func tail(upTo count: Int) -> FieldTail {
        let read = reads.withLock { reads -> Int in
            reads += 1
            return reads
        }
        return .text(read > 1 ? "hello there" : "")
    }

    func focusedApplication() -> InsertionDestination? {
        reads.withLock { $0 } > 1 ? Self.other : Self.target
    }
}

/// Accepts every keystroke, or refuses each one with `refusal`, recording nothing.
private struct SilentTypist: KeystrokeTyping {
    var refusal: TextInsertionError?
    func type(_ text: String) throws(TextInsertionError) { if let refusal { throw refusal } }
    func deleteBackwards(_ count: Int) throws(TextInsertionError) { if let refusal { throw refusal } }
}
