import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPredict

/// Focus that answers whatever the test needs it to.
private struct StubFocus: AccessibilityFocus {
    var field: (any FocusedTextField)?
    var selfFrontmost = false
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { field != nil }
    func isSelfFrontmost() -> Bool { selfFrontmost }
}

/// A field that keeps what was written into it, and how far back each write reached.
private final class RecordingField: FocusedTextField, @unchecked Sendable {
    /// Whether this field will select backwards, which is what separates the two Accessibility paths.
    private let selectsBackwards: Bool
    private let written = Mutex<[String]>([])
    private let swallowed = Mutex<[Int]>([])

    init(selectsBackwards: Bool = true) { self.selectsBackwards = selectsBackwards }

    var text: [String] { written.withLock { $0 } }
    var replaced: [Int] { swallowed.withLock { $0 } }

    func replaceSelection(with text: String) throws(TextInsertionError) {
        written.withLock { $0.append(text) }
        swallowed.withLock { $0.append(0) }
    }

    func replaceSelection(
        precededBy characters: Int, with text: String
    ) throws(TextInsertionError) {
        guard selectsBackwards || characters == 0 else {
            throw .insertionRejected(description: "the field cannot select backwards")
        }
        written.withLock { $0.append(text) }
        swallowed.withLock { $0.append(characters) }
    }
}

/// A field that implements only the narrow write, so the protocol's own default is what runs.
private final class NarrowField: FocusedTextField, @unchecked Sendable {
    private let accepted = Mutex<[String]>([])
    var text: [String] { accepted.withLock { $0 } }
    func replaceSelection(with text: String) throws(TextInsertionError) {
        accepted.withLock { $0.append(text) }
    }
}

/// A typist that keeps what it was asked to type and delete, or refuses.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let typed = Mutex<[String]>([])
    private let deleted = Mutex<[Int]>([])
    private let error: TextInsertionError?

    init(error: TextInsertionError? = nil) { self.error = error }

    var text: [String] { typed.withLock { $0 } }
    var deletions: [Int] { deleted.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        typed.withLock { $0.append(text) }
        if let error { throw error }
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        deleted.withLock { $0.append(count) }
        if let error { throw error }
    }
}

@Suite("Typing a completion in")
struct TypedTextInsertionEngineTests {
    @Test("The text goes to the typist exactly as it was given.")
    func typesWhatItIsGiven() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: StubFocus(), typist: typist)

        try await engine.insert("mit")

        #expect(typist.text == ["mit"])
        #expect(engine.method == .typed)
    }

    @Test("It will type into anything except Uttrflow itself.")
    func declinesOnlyWhenUttrflowIsInFront() async {
        let engine = TypedTextInsertionEngine(focus: StubFocus(), typist: RecordingTypist())
        #expect(await engine.canInsert())
        #expect(await engine.canWrite())

        let ours = TypedTextInsertionEngine(
            focus: StubFocus(selfFrontmost: true), typist: RecordingTypist())
        #expect(await ours.canInsert() == false)
        #expect(await ours.canWrite() == false)
    }

    @Test("A refusal from the typist is the engine's refusal too.")
    func refusalIsReported() async {
        let engine = TypedTextInsertionEngine(
            focus: StubFocus(), typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: TextInsertionError.accessibilityDenied) {
            try await engine.insert("mit")
        }
    }

    @Test("A completion that replaces nothing presses Delete not at all.")
    func anAppendDeletesNothing() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: StubFocus(), typist: typist)

        try await engine.write("mit", replacing: 0)

        #expect(typist.deletions.isEmpty)
        #expect(typist.text == ["mit"])
    }

    @Test("A completion that replaces presses Delete once per character, before typing.")
    func aReplacementDeletesFirst() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: StubFocus(), typist: typist)

        try await engine.write("it commit -m", replacing: 4)

        #expect(typist.deletions == [4])
        #expect(typist.text == ["it commit -m"])
    }
}

@Suite("Writing a completion through Accessibility")
struct AccessibilityCompletionTests {
    @Test("A field that selects backwards takes the replacement as one write.")
    func oneWriteWhereTheFieldAllowsIt() async throws {
        let field = RecordingField()
        let engine = AccessibilityTextInsertionEngine(focus: StubFocus(field: field))

        try await engine.write("it commit -m", replacing: 4)

        #expect(field.text == ["it commit -m"])
        #expect(field.replaced == [4])
    }

    @Test("With nothing focused it refuses rather than writing somewhere else.")
    func refusesWithNothingFocused() async {
        let engine = AccessibilityTextInsertionEngine(focus: StubFocus())

        #expect(await engine.canWrite() == false)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("mit", replacing: 0)
        }
    }

    @Test("A field that only replaces its selection takes an append and refuses a replacement.")
    func theDefaultReachesNoFurtherThanTheSelection() async throws {
        let field = NarrowField()
        let engine = AccessibilityTextInsertionEngine(focus: StubFocus(field: field))

        try await engine.write("mit", replacing: 0)
        #expect(field.text == ["mit"])

        await #expect(throws: (any Error).self) { try await engine.write("mit", replacing: 1) }
        #expect(field.text == ["mit"])
    }
}

@Suite("The route a completion takes")
struct CompletionRouteTests {
    /// Accepting a suggestion must not cost the user their clipboard, or file a phantom clip.
    @Test("The clipboard is not on it, at any position.")
    func theClipboardIsNotOnIt() {
        let route = TextInsertion.completion(focus: StubFocus(), typist: RecordingTypist()).route
        #expect(route == [.accessibility, .typed])
        #expect(!route.contains(.clipboard))
        #expect(!route.contains(.pasteboard))
    }

    @Test("Accessibility is tried first, because it writes at the caret and touches nothing else.")
    func accessibilityLeads() async throws {
        let field = RecordingField()
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: StubFocus(field: field), typist: typist)

        #expect(try await route.write("mit", replacing: 0) == .accessibility)
        #expect(field.text == ["mit"])
        #expect(typist.text.isEmpty, "typing is the fallback, not the first attempt")
    }

    @Test("A field Accessibility cannot write into is typed into instead.")
    func typingCatchesWhatAccessibilityCannotReach() async throws {
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: StubFocus(), typist: typist)

        #expect(try await route.write("mit", replacing: 0) == .typed)
        #expect(typist.text == ["mit"])
    }

    @Test("A field that will not select backwards falls to keystrokes rather than losing the replacement.")
    func keystrokesCatchTheReplacementAccessibilityRefuses() async throws {
        let field = RecordingField(selectsBackwards: false)
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: StubFocus(field: field), typist: typist)

        #expect(try await route.write("it commit -m", replacing: 4) == .typed)
        #expect(field.text.isEmpty)
        #expect(typist.deletions == [4])
        #expect(typist.text == ["it commit -m"])
    }

    @Test("With both routes refused the suggestion is dropped rather than left on the clipboard.")
    func nothingIsLeftBehind() async {
        let route = TextInsertion.completion(
            focus: StubFocus(selfFrontmost: true),
            typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await route.write("mit", replacing: 0)
        }
    }

    @Test("A route with no strategies at all reports that there was nowhere to write.")
    func anEmptyRouteRefuses() async {
        let route = CompletionRoute(strategies: [])

        #expect(route.route.isEmpty)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await route.write("mit", replacing: 0)
        }
    }
}

@Suite("Accepting a suggestion")
struct SuggestionAcceptorTests {
    private func acceptor(
        field: (any FocusedTextField)? = nil, typist: RecordingTypist = RecordingTypist()
    ) -> SuggestionAcceptor {
        SuggestionAcceptor(
            completion: TextInsertion.completion(focus: StubFocus(field: field), typist: typist))
    }

    @Test("A suggestion that continues what was typed still inserts only the part not yet there.")
    func insertsOnlyTheTail() async throws {
        let field = RecordingField()

        let method = try await acceptor(field: field)
            .accept(.certain("git commit"), after: "git com")

        #expect(method == .accessibility)
        #expect(field.text == ["mit"])
        #expect(field.replaced == [0], "a continuation destroys nothing")
    }

    @Test("A fuzzy match takes back the characters it disagrees with rather than doubling them.")
    func replacesWhatTheUserMistyped() async throws {
        let field = RecordingField()

        let method = try await acceptor(field: field)
            .accept(.certain("git commit -m"), after: "gti c")

        #expect(method == .accessibility)
        #expect(field.text == ["it commit -m"])
        #expect(field.replaced == [4])
    }

    @Test("A verified correction replaces the wrong character instead of doing nothing.")
    func appliesACorrection() async throws {
        let field = RecordingField()

        try await acceptor(field: field).accept(.certain("git commit"), after: "git comi")

        #expect(field.text == ["mit"])
        #expect(field.replaced == [1])
    }

    @Test("A suggestion the user has already finished typing inserts nothing at all.")
    func insertsNothingWhenThereIsNothingToAdd() async throws {
        let field = RecordingField()

        #expect(
            try await acceptor(field: field).accept(.certain("git commit"), after: "git commit")
                == nil)
        #expect(field.text.isEmpty)
    }

    @Test("Nothing drawn is nothing to accept, so Tab reaches the field untouched.")
    func acceptsNothingWhenNothingIsOffered() async throws {
        let field = RecordingField()

        #expect(try await acceptor(field: field).accept(.silent, after: "git com") == nil)
        #expect(try await acceptor(field: field).accept(.minimised, after: "git com") == nil)
        #expect(field.text.isEmpty)
    }

    @Test("The leader of a list is what Tab takes, replacement and all.")
    func takesTheLeaderOfAChoice() async throws {
        let field = RecordingField()

        try await acceptor(field: field)
            .accept(.choice(leader: "git commit", others: ["git checkout"]), after: "gti c")

        #expect(field.text == ["it commit"])
        #expect(field.replaced == [4])
    }

    @Test("Nothing typed yet means the whole suggestion goes in.")
    func insertsEverythingFromAnEmptyField() async throws {
        let field = RecordingField()

        #expect(
            try await acceptor(field: field).accept(.certain("git commit"), after: "")
                == .accessibility)
        #expect(field.text == ["git commit"])
        #expect(field.replaced == [0])
    }

    @Test("The route it will take is the one a caller can check for a clipboard.")
    func exposesItsRoute() {
        #expect(acceptor().route == [.accessibility, .typed])
    }
}

@Suite("Selecting backwards from the caret")
struct BackwardSelectionTests {
    @Test("The range covers exactly the characters asked for, and ends at the caret.")
    func coversWhatWasAskedFor() throws {
        let range = try #require(
            BackwardSelection.range(in: "git comi", endingAt: 8, covering: 1))
        #expect(range == 7..<8)
    }

    @Test("Asking for none is an empty range at the caret, which replaces nothing.")
    func noneIsAnEmptyRangeAtTheCaret() throws {
        let range = try #require(
            BackwardSelection.range(in: "git comi", endingAt: 8, covering: 0))
        #expect(range == 8..<8)
    }

    @Test("The range is measured in UTF-16 units, so an emoji before the caret counts as two.")
    func countsInTheUnitsAccessibilityUses() throws {
        let range = try #require(
            BackwardSelection.range(in: "🚀 launch", endingAt: 9, covering: 8))
        #expect(range == 0..<9)

        let one = try #require(BackwardSelection.range(in: "a🚀", endingAt: 3, covering: 1))
        #expect(one == 1..<3)
    }

    @Test("Reaching further back than the field's own text is refused rather than clamped.")
    func refusesToReachPastTheStart() {
        #expect(BackwardSelection.range(in: "git", endingAt: 3, covering: 4) == nil)
        #expect(BackwardSelection.range(in: "git", endingAt: 9, covering: 1) == nil)
    }

    @Test("A caret the field reports as nonsense is refused rather than guessed at.")
    func refusesNonsense() {
        #expect(BackwardSelection.range(in: "git", endingAt: -1, covering: 1) == nil)
        #expect(BackwardSelection.range(in: "git", endingAt: 3, covering: -1) == nil)
        #expect(BackwardSelection.range(in: "a🚀", endingAt: 2, covering: 1) == nil)
    }
}
