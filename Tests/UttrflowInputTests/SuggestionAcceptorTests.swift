import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Focus that answers whatever the test needs it to.
private struct StubFocus: AccessibilityFocus {
    var field: (any FocusedTextField)?
    var selfFrontmost = false
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { field != nil }
    func isSelfFrontmost() -> Bool { selfFrontmost }
}

/// A field that keeps what was written into it.
private final class RecordingField: FocusedTextField, @unchecked Sendable {
    private let written = Mutex<[String]>([])
    var text: [String] { written.withLock { $0 } }
    func replaceSelection(with text: String) throws(TextInsertionError) {
        written.withLock { $0.append(text) }
    }
}

/// A typist that keeps what it was asked to type, or refuses.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let typed = Mutex<[String]>([])
    private let error: TextInsertionError?

    init(error: TextInsertionError? = nil) { self.error = error }

    var text: [String] { typed.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        typed.withLock { $0.append(text) }
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

        let ours = TypedTextInsertionEngine(
            focus: StubFocus(selfFrontmost: true), typist: RecordingTypist())
        #expect(await ours.canInsert() == false)
    }

    @Test("A refusal from the typist is the engine's refusal too.")
    func refusalIsReported() async {
        let engine = TypedTextInsertionEngine(
            focus: StubFocus(), typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: TextInsertionError.accessibilityDenied) {
            try await engine.insert("mit")
        }
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

        #expect(try await route.insert("mit") == .accessibility)
        #expect(field.text == ["mit"])
        #expect(typist.text.isEmpty, "typing is the fallback, not the first attempt")
    }

    @Test("A field Accessibility cannot write into is typed into instead.")
    func typingCatchesWhatAccessibilityCannotReach() async throws {
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: StubFocus(), typist: typist)

        #expect(try await route.insert("mit") == .typed)
        #expect(typist.text == ["mit"])
    }

    @Test("With both routes refused the suggestion is dropped rather than left on the clipboard.")
    func nothingIsLeftBehind() async {
        let route = TextInsertion.completion(
            focus: StubFocus(selfFrontmost: true),
            typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: (any Error).self) { try await route.insert("mit") }
    }
}

@Suite("Accepting a suggestion")
struct SuggestionAcceptorTests {
    private func acceptor(
        field: (any FocusedTextField)? = nil, typist: RecordingTypist = RecordingTypist()
    ) -> SuggestionAcceptor {
        SuggestionAcceptor(
            coordinator: TextInsertion.completion(
                focus: StubFocus(field: field), typist: typist))
    }

    @Test("Only the part the user has not typed is inserted.")
    func insertsOnlyTheTail() async throws {
        let field = RecordingField()

        let method = try await acceptor(field: field).accept("git commit", after: "git com")

        #expect(method == .accessibility)
        #expect(field.text == ["mit"])
    }

    @Test("A suggestion the user has already finished typing inserts nothing at all.")
    func insertsNothingWhenThereIsNothingToAdd() async throws {
        let field = RecordingField()

        #expect(try await acceptor(field: field).accept("git commit", after: "git commit") == nil)
        #expect(field.text.isEmpty)
    }

    @Test("A suggestion that does not continue what was typed is refused rather than duplicated.")
    func refusesWhatItCannotContinue() async throws {
        let field = RecordingField()

        #expect(try await acceptor(field: field).accept("git commit", after: "svn ci") == nil)
        #expect(field.text.isEmpty)
    }

    @Test("Nothing typed yet means the whole suggestion goes in.")
    func insertsEverythingFromAnEmptyField() async throws {
        let field = RecordingField()

        #expect(try await acceptor(field: field).accept("git commit", after: "") == .accessibility)
        #expect(field.text == ["git commit"])
    }

    @Test("The route it will take is the one a caller can check for a clipboard.")
    func exposesItsRoute() {
        #expect(acceptor().route == [.accessibility, .typed])
    }
}
