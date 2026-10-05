import Synchronization
import Testing
import UttrflowTestSupport
import Foundation

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPredict

/// A field that keeps what was written into it, and how far back each write reached.
private final class RecordingField: FocusedTextField, @unchecked Sendable {
    /// Whether this field will select backwards, which is what separates the two Accessibility paths.
    private let selectsBackwards: Bool
    private let written = Mutex<[String]>([])
    private let replacedCounts = Mutex<[Int]>([])

    init(selectsBackwards: Bool = true) { self.selectsBackwards = selectsBackwards }

    var text: [String] { written.withLock { $0 } }
    var replaced: [Int] { replacedCounts.withLock { $0 } }

    func replaceSelection(with text: String) throws(TextInsertionError) {
        written.withLock { $0.append(text) }
        replacedCounts.withLock { $0.append(0) }
    }

    func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError) {
        guard selectsBackwards || replaced.isEmpty else {
            throw .insertionRejected(description: "the field cannot select backwards")
        }
        written.withLock { $0.append(text) }
        replacedCounts.withLock { $0.append(replaced.count) }
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

/// A typist that keeps every string it types and every deletion it makes, or refuses.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let typed = Mutex<[String]>([])
    private let deleted = Mutex<[Int]>([])
    private let error: TextInsertionError?

    init(error: TextInsertionError? = nil) {
        self.error = error
    }

    var text: [String] { typed.withLock { $0 } }
    var deletions: [Int] { deleted.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        if let error { throw error }
        typed.withLock { $0.append(text) }
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        deleted.withLock { $0.append(count) }
        if let error { throw error }
    }
}

private enum ReplacementFailureMode: Equatable {
    case firstType
    case afterDeleteCancellation
}

private final class ReplacementTypist: KeystrokeTyping, @unchecked Sendable {
    private struct State {
        var visibleText: String
        var attempts: [String] = []
        var deletions: [Int] = []
    }
    private let state: Mutex<State>
    private let failureMode: ReplacementFailureMode

    init(text: String, failureMode: ReplacementFailureMode) {
        state = Mutex(State(visibleText: text))
        self.failureMode = failureMode
    }
    var visibleText: String { state.withLock { $0.visibleText } }
    var attempts: [String] { state.withLock { $0.attempts } }
    var deletions: [Int] { state.withLock { $0.deletions } }

    func type(_ text: String) throws(TextInsertionError) {
        let fails = state.withLock { state in
            state.attempts.append(text)
            if failureMode == .firstType, state.attempts.count == 1 { return true }
            state.visibleText += text
            return false
        }
        if fails { throw .accessibilityDenied }
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        state.withLock { state in
            state.deletions.append(count)
            state.visibleText = String(state.visibleText.dropLast(count))
        }
        if failureMode == .afterDeleteCancellation {
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
}

/// Pauses after Delete has landed, so quit can be interleaved before the replacement is typed.
private final class PausingTypist: KeystrokeTyping, @unchecked Sendable {
    let didDelete = Signal()
    private let typedValues = Mutex<[String]>([])
    private let resumeTyping = DispatchSemaphore(value: 0)

    var typed: [String] { typedValues.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        resumeTyping.wait()
        typedValues.withLock { $0.append(text) }
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        didDelete.fire()
    }

    func allowTyping() { resumeTyping.signal() }
}

private final class SequencedCompletionFocus: AccessibilityFocus, @unchecked Sendable {
    private let applications: [InsertionDestination]
    private let reads = Mutex(0)

    init(_ applications: [InsertionDestination]) { self.applications = applications }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        reads.withLock { reads in
            let application = applications[min(reads, applications.count - 1)]
            reads += 1
            return application
        }
    }
    func focusedFieldIsSecure() -> Bool { false }
}

@Suite("Typing a completion in")
struct TypedTextInsertionEngineTests {
    @Test("The text goes to the typist exactly as it was given.")
    func typesWhatItIsGiven() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: typist)

        _ = try await engine.insert("mit")

        #expect(typist.text == ["mit"])
        #expect(engine.method == .typed)
    }

    @Test("It will type into anything except Uttrflow itself.")
    func declinesOnlyWhenUttrflowIsInFront() async {
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: RecordingTypist())
        #expect(await engine.canInsert())
        #expect(await engine.canWrite())

        let ours = TypedTextInsertionEngine(
            focus: FakeFocus(isSelf: true), typist: RecordingTypist())
        #expect(await ours.canInsert() == false)
        #expect(await ours.canWrite() == false)
    }

    @Test("A completion refuses when Uttrflow came to the front after canWrite() said yes.")
    func writeRefusesWhenSelfBecameFrontmost() async {
        let focus = SwitchableFocus()
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)
        #expect(await engine.canWrite())

        focus.becomeSelfFrontmost()

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("mit", replacing: "co")
        }
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("mit", replacing: "")
        }
        #expect(typist.deletions.isEmpty)
        #expect(typist.text.isEmpty)
    }

    @Test("A completion refuses when its target changes after the initial field read.")
    func writeRefusesWhenDestinationChanges() async {
        let first = InsertionDestination(applicationName: "Notes", bundleIdentifier: "com.example.notes")
        let second = InsertionDestination(applicationName: "Chat", bundleIdentifier: "com.example.chat")
        let focus = SequencedCompletionFocus([first, second])
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await engine.write("completion", replacing: "")
        }
        #expect(typist.text.isEmpty)
    }

    @Test("A cancelled completion refuses before writing.")
    func writeRefusesWhenCancelled() async {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: typist)
        let error = await Task { () -> TextInsertionError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(TextInsertionError) {
                try await engine.write("completion", replacing: "")
                return nil
            } catch { return error }
        }.value

        #expect(error == .insertionRejected(description: TextInsertion.dictationEnded))
        #expect(typist.text.isEmpty)
    }

    @Test("An insertion refuses when Uttrflow came to the front after canInsert() said yes.")
    func insertRefusesWhenSelfBecameFrontmost() async {
        let focus = SwitchableFocus()
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)
        #expect(await engine.canInsert())

        focus.becomeSelfFrontmost()

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            _ = try await engine.insert("mit")
        }
        #expect(typist.text.isEmpty)
    }

    @Test("A dictation is not typed into an application the user switched to.")
    func insertRefusesWhenDestinationChanged() async {
        let target = InsertionDestination(applicationName: "Notes", bundleIdentifier: "com.example.notes")
        let other = InsertionDestination(applicationName: "Chat", bundleIdentifier: "com.example.chat")
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(frontmost: other), typist: typist)

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            _ = try await engine.insert("private words", targeting: target)
        }
        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            _ = try await engine.insert("private words", richText: "<b>w</b>", targeting: target)
        }
        #expect(typist.text.isEmpty)
    }

    @Test("A dictation is typed while its captured application is still in front.")
    func insertTypesIntoUnchangedDestination() async throws {
        let target = InsertionDestination(applicationName: "Notes", bundleIdentifier: "com.example.notes")
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(frontmost: target), typist: typist)

        _ = try await engine.insert("words", targeting: target)

        #expect(typist.text == ["words"])
    }

    @Test("A dictation that has given up is not typed.")
    func insertRefusesWhenCancelled() async {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: typist)
        let task = Task { () async throws(TextInsertionError) -> InsertionArrival in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.insert("late words")
        }

        await #expect(throws: TextInsertionError.insertionRejected(description: TextInsertion.dictationEnded))
        {
            _ = try await task.value
        }
        #expect(typist.text.isEmpty)
    }

    @Test("A refusal from the typist is the engine's refusal too.")
    func refusalIsReported() async {
        let engine = TypedTextInsertionEngine(
            focus: FakeFocus(), typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: TextInsertionError.accessibilityDenied) {
            try await engine.insert("mit")
        }
    }

    @Test("A completion that replaces nothing presses Delete not at all.")
    func anAppendDeletesNothing() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: typist)

        try await engine.write("mit", replacing: "")

        #expect(typist.deletions.isEmpty)
        #expect(typist.text == ["mit"])
    }

    @Test("A completion that replaces presses Delete once per character, before typing.")
    func aReplacementDeletesFirst() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(), typist: typist)

        try await engine.write("it commit -m", replacing: "git ")

        #expect(typist.deletions == [4])
        #expect(typist.text == ["it commit -m"])
    }

    @Test("It refuses when what is before the caret is not what it means to replace, so no prompt is eaten.")
    func refusesWhenPrecedingTextDiffers() async {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(preceding: "$ ru"), typist: typist)

        await #expect(throws: (any Error).self) {
            try await engine.write("n build", replacing: "git ")
        }
        #expect(typist.deletions.isEmpty, "nothing is deleted when the guard refuses")
        #expect(typist.text.isEmpty)
    }

    @Test("It proceeds when the text before the caret is exactly what it will replace.")
    func proceedsWhenPrecedingTextMatches() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(preceding: "git "), typist: typist)

        try await engine.write("it commit", replacing: "git ")

        #expect(typist.deletions == [4])
        #expect(typist.text == ["it commit"])
    }

    @Test("A failed first chunk restores replaced text and asks the user to check the field.")
    func restoresReplacementWhenFirstChunkFails() async {
        let typist = ReplacementTypist(text: "gti c", failureMode: .firstType)
        let target = InsertionDestination(applicationName: "Editor", bundleIdentifier: "com.example.editor")
        let engine = TypedTextInsertionEngine(
            focus: FakeFocus(preceding: "gti c", frontmost: target), typist: typist)

        await #expect(throws: TextInsertionError.insertionUnconfirmed) {
            try await engine.write("it commit", replacing: "gti c", confirmedPreceding: "gti c")
        }

        #expect(typist.deletions == [5])
        #expect(typist.attempts == ["it commit", "gti c"])
        #expect(typist.visibleText == "gti c")
        #expect(
            TextInsertionError.insertionUnconfirmed.userMessage
                == "The app hasn't confirmed whether the text was inserted. Check the field before trying again."
        )
    }

    @Test("Cancellation after Delete does not prevent restoration in the same destination.")
    func cancellationAfterDeleteStillRestoresReplacement() async {
        let target = InsertionDestination(applicationName: "Editor", bundleIdentifier: "com.example.editor")
        let typist = ReplacementTypist(text: "gti c", failureMode: .afterDeleteCancellation)
        let engine = TypedTextInsertionEngine(
            focus: FakeFocus(preceding: "gti c", frontmost: target), typist: typist)
        let write = Task { () -> TextInsertionError? in
            do throws(TextInsertionError) {
                try await engine.write("it commit", replacing: "gti c", confirmedPreceding: "gti c")
                return nil
            } catch { return error }
        }

        let error = await write.value

        #expect(error == .insertionUnconfirmed)
        #expect(typist.deletions == [5])
        #expect(typist.attempts == ["gti c"])
        #expect(typist.visibleText == "gti c")
    }

    @Test("A failed replacement is not restored into a newly focused application.")
    func doesNotRestoreReplacementAfterFocusChanges() async {
        let original = InsertionDestination(applicationName: "Editor", bundleIdentifier: "com.example.editor")
        let other = InsertionDestination(applicationName: "Chat", bundleIdentifier: "com.example.chat")
        // Five reads cover capture, pre-delete checks, setup, and the first-chunk check.
        let focus = SequencedReplacementFocus([
            original, original, original, original, original, other,
        ])
        let typist = ReplacementTypist(text: "gti c", failureMode: .firstType)
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        await #expect(throws: TextInsertionError.insertionUnconfirmed) {
            try await engine.write("it commit", replacing: "gti c", confirmedPreceding: "gti c")
        }

        #expect(typist.deletions == [5])
        #expect(typist.attempts == ["it commit"])
    }

    @Test("A replacement is not deleted when the focused application cannot be identified.")
    func refusesReplacementWithoutKnownApplication() async {
        let typist = ReplacementTypist(text: "gti c", failureMode: .firstType)
        let engine = TypedTextInsertionEngine(
            focus: FakeFocus(preceding: "gti c"), typist: typist)

        await #expect(throws: TextInsertionError.insertionUnconfirmed) {
            try await engine.write("it commit", replacing: "gti c", confirmedPreceding: "gti c")
        }

        #expect(typist.deletions.isEmpty)
        #expect(typist.attempts.isEmpty)
        #expect(typist.visibleText == "gti c")
    }

    @Test("quit waits through the gap between deleting and typing a replacement")
    func quitWaitsForReplacement() async throws {
        let typist = PausingTypist()
        let finishWaitStarted = Signal()
        let engine = TypedTextInsertionEngine(
            focus: FakeFocus(preceding: "git "), typist: typist,
            finishWaitStarted: { finishWaitStarted.fire() })
        let writing = Task { try await engine.write("it commit", replacing: "git ") }
        try await arrival(of: typist.didDelete.fired)

        let finished = Mutex(false)
        let draining = Task {
            await engine.finishWrites()
            finished.withLock { $0 = true }
        }
        try await arrival(of: finishWaitStarted.fired)
        #expect(!finished.withLock { $0 })
        #expect(!draining.isCancelled)
        #expect(typist.typed.isEmpty)

        typist.allowTyping()
        try await writing.value
        await draining.value
        #expect(finished.withLock { $0 })
        #expect(typist.typed == ["it commit"])

        await #expect(
            throws: TextInsertionError.insertionRejected(description: "the application is terminating")
        ) {
            try await engine.write("late", replacing: "")
        }
    }

    @Test(
        "A replacement ending in an emoji passes the guard, since the field is read in characters, not UTF-16 units."
    )
    func acceptsAReplacementEndingInAnEmoji() async throws {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: FakeFocus(value: "ab🙂"), typist: typist)

        try await engine.write("🚀 launch", replacing: "b🙂")

        #expect(typist.deletions == [2], "one Delete per character, and the emoji is one character")
        #expect(typist.text == ["🚀 launch"])
    }

    @Test("Acceptance reuses its bounded read for a large replacement field")
    func acceptanceDoesNotReadTheLargeFieldAgain() async throws {
        let focus = LargeValueFocus()
        let typist = RecordingTypist()
        let acceptor = SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: typist), focus: focus)

        try await acceptor.accept(.certain("git commit"), after: "gti ")

        #expect(focus.boundedReads == 1)
        #expect(focus.largestBoundedRequest < 100)
        #expect(focus.wholeValueReads == 0)
        #expect(typist.deletions == [3])
    }
}

private final class SequencedReplacementFocus: AccessibilityFocus, @unchecked Sendable {
    private let applications: [InsertionDestination]
    private let reads = Mutex(0)

    init(_ applications: [InsertionDestination]) { self.applications = applications }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        reads.withLock { reads in
            let application = applications[min(reads, applications.count - 1)]
            reads += 1
            return application
        }
    }
    func focusedFieldIsSecure() -> Bool { false }
}

/// A million-character field that counts bounded reads separately from whole-value reads.
private final class LargeValueFocus: AccessibilityFocus, Sendable {
    private struct State {
        var boundedRequests: [Int] = []
        var wholeValueReads = 0
    }
    private let state = Mutex(State())
    private let value = String(repeating: "z", count: 999_996) + "gti "

    var boundedReads: Int { state.withLock { $0.boundedRequests.count } }
    var largestBoundedRequest: Int { state.withLock { $0.boundedRequests.max() ?? 0 } }
    var wholeValueReads: Int { state.withLock { $0.wholeValueReads } }
    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedFieldIsSecure() -> Bool { false }
    func tail(upTo count: Int) -> FieldTail {
        state.withLock { $0.boundedRequests.append(count) }
        return .text(String(value.suffix(count)))
    }
    func precedingText(_ count: Int) -> String? {
        state.withLock { $0.wholeValueReads += 1 }
        return String(value.suffix(count))
    }
    func windowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail) {
        (nil, tail(upTo: count))
    }
}

@Suite("Writing a completion through Accessibility")
struct AccessibilityCompletionTests {
    @Test("A field that selects backwards takes the replacement as one write.")
    func oneWriteWhereTheFieldAllowsIt() async throws {
        let field = RecordingField()
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.write("it commit -m", replacing: "git ")

        #expect(field.text == ["it commit -m"])
        #expect(field.replaced == [4])
    }

    @Test("With nothing focused it refuses rather than writing somewhere else.")
    func refusesWithNothingFocused() async {
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus())

        #expect(await engine.canWrite() == false)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("mit", replacing: "")
        }
    }

    @Test("A field that only replaces its selection takes an append and refuses a replacement.")
    func theDefaultReachesNoFurtherThanTheSelection() async throws {
        let field = NarrowField()
        let engine = AccessibilityTextInsertionEngine(focus: FakeFocus(field: field))

        try await engine.write("mit", replacing: "")
        #expect(field.text == ["mit"])

        await #expect(throws: (any Error).self) { try await engine.write("mit", replacing: "x") }
        #expect(field.text == ["mit"])
    }
}

@Suite("Confirming what a completion takes back")
struct BackwardSelectionConfirmationTests {
    @Test("Confirms the characters before the caret when they are exactly what would be replaced.")
    func confirmsAMatch() {
        #expect(BackwardSelection.confirms("git ", in: "git ", endingAt: 4))
        #expect(BackwardSelection.confirms("b🙂", in: "ab🙂", endingAt: 4))
        #expect(BackwardSelection.confirms("", in: "anything", endingAt: 3))
    }

    /// Read as "gti c", then "m" typed before Tab: the four characters behind the caret are no longer "ti c".
    @Test("Refuses when a character typed since the read sits before the caret.")
    func refusesWhatMoved() {
        #expect(!BackwardSelection.confirms("ti c", in: "gti cm", endingAt: 6))
    }

    @Test("Refuses when there is too little text or the caret splits a character.")
    func refusesAnImpossibleRange() {
        #expect(!BackwardSelection.confirms("ab", in: "a", endingAt: 1))
        #expect(!BackwardSelection.confirms("🙂", in: "a🙂", endingAt: 2))
    }
}

@Suite("The route a completion takes")
struct CompletionRouteTests {
    /// Accepting a suggestion must not cost the user their clipboard, or file a phantom clip.
    @Test("The clipboard is not on it, at any position.")
    func theClipboardIsNotOnIt() {
        let route = TextInsertion.completion(focus: FakeFocus(), typist: RecordingTypist()).route
        #expect(route == [.accessibility, .typed])
        #expect(!route.contains(.clipboard))
        #expect(!route.contains(.pasteboard))
    }

    @Test("Accessibility is tried first, because it writes at the caret and touches nothing else.")
    func accessibilityLeads() async throws {
        let field = RecordingField()
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: FakeFocus(field: field), typist: typist)

        #expect(try await route.write("mit", replacing: "") == .accessibility)
        #expect(field.text == ["mit"])
        #expect(typist.text.isEmpty, "typing is the fallback, not the first attempt")
    }

    @Test("A field Accessibility cannot write into is typed into instead.")
    func typingCatchesWhatAccessibilityCannotReach() async throws {
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: FakeFocus(), typist: typist)

        #expect(try await route.write("mit", replacing: "") == .typed)
        #expect(typist.text == ["mit"])
    }

    @Test("A field that will not select backwards falls to keystrokes rather than losing the replacement.")
    func keystrokesCatchTheReplacementAccessibilityRefuses() async throws {
        let field = RecordingField(selectsBackwards: false)
        let typist = RecordingTypist()
        let route = TextInsertion.completion(focus: FakeFocus(field: field), typist: typist)

        #expect(try await route.write("it commit -m", replacing: "git ") == .typed)
        #expect(field.text.isEmpty)
        #expect(typist.deletions == [4])
        #expect(typist.text == ["it commit -m"])
    }

    @Test("With both routes refused the suggestion is dropped rather than left on the clipboard.")
    func nothingIsLeftBehind() async {
        let route = TextInsertion.completion(
            focus: FakeFocus(isSelf: true),
            typist: RecordingTypist(error: .accessibilityDenied))

        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await route.write("mit", replacing: "")
        }
    }

    @Test("A route with no strategies at all reports that there was nowhere to write.")
    func anEmptyRouteRefuses() async {
        let route = CompletionRoute(strategies: [])

        #expect(route.route.isEmpty)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await route.write("mit", replacing: "")
        }
    }
}

@Suite("Accepting a suggestion")
struct SuggestionAcceptorTests {
    private func acceptor(
        field: (any FocusedTextField)? = nil, typist: RecordingTypist = RecordingTypist()
    ) -> SuggestionAcceptor {
        SuggestionAcceptor(
            completion: TextInsertion.completion(focus: FakeFocus(field: field), typist: typist))
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

    @Test("A normalization split inside a grapheme still accepts the complete edit.")
    func acceptsADecomposedGraphemeWithoutSplittingIt() async throws {
        let field = RecordingField()
        let typed = "e\u{301}"

        try await acceptor(field: field).accept(.certain("e"), after: typed)

        #expect(field.text == ["e"])
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

    @Test("The text before the caret comes back in whole characters, so an emoji is never a lone surrogate.")
    func textIsReadInCharacters() {
        #expect(BackwardSelection.text(in: "ab🙂", endingAt: 4, exactly: 1) == "🙂")
        #expect(BackwardSelection.text(in: "ab🙂", endingAt: 4, exactly: 2) == "b🙂")
        #expect(BackwardSelection.text(in: "ab🙂", endingAt: 4, exactly: 0) == "")
        #expect(BackwardSelection.text(in: "git comi", endingAt: 8, exactly: 4) == "comi")
    }

    @Test("The text is refused for the same carets the range is, so the two readings cannot disagree.")
    func textRefusesWhatTheRangeRefuses() {
        #expect(BackwardSelection.text(in: "ab🙂", endingAt: 3, exactly: 1) == nil)
        #expect(BackwardSelection.text(in: "ab🙂", endingAt: 4, exactly: 4) == nil)
        #expect(BackwardSelection.text(in: "git", endingAt: 9, exactly: 1) == nil)
        #expect(BackwardSelection.text(in: "git", endingAt: 3, exactly: -1) == nil)
    }
}

/// A short field is short, not silent: the delete path wants an exact count, a read-back wants what is there.
@Suite("The tail before the caret")
struct BackwardSelectionTailTests {
    @Test("gives back everything there is when the field holds less than was asked for")
    func clampsToWhatExists() {
        #expect(BackwardSelection.tail(in: "hi", endingAt: 2, upTo: 96) == "hi")
        #expect(BackwardSelection.tail(in: "", endingAt: 0, upTo: 96) == "")
    }

    /// The distinction #223 is about: the exact-count form refuses the same field the tail form reads.
    @Test("reads a field the exact-count form refuses")
    func readsWhatTheExactFormRefuses() {
        #expect(BackwardSelection.text(in: "hi", endingAt: 2, exactly: 96) == nil)
        #expect(BackwardSelection.tail(in: "hi", endingAt: 2, upTo: 96) == "hi")
    }

    @Test("still cuts on whole characters, so an emoji never comes back half")
    func cutsOnCharacters() {
        #expect(BackwardSelection.tail(in: "ab🙂", endingAt: 4, upTo: 1) == "🙂")
        #expect(BackwardSelection.tail(in: "ab🙂", endingAt: 4, upTo: 99) == "ab🙂")
    }

    @Test("says nothing when the caret itself cannot be read")
    func refusesAnUnreadableCaret() {
        // Inside the emoji's surrogate pair, which is not a position in the string at all.
        #expect(BackwardSelection.tail(in: "ab🙂", endingAt: 3, upTo: 8) == nil)
        #expect(BackwardSelection.tail(in: "ab", endingAt: 99, upTo: 8) == nil)
    }
}

/// Focus whose field holds `before` ahead of the caret, as a terminal shows it after the shell echoes.
private struct EchoedFocus: AccessibilityFocus {
    let field: any FocusedTextField
    let before: String
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? { nil }
    func focusedFieldIsSecure() -> Bool { false }
    func tail(upTo count: Int) -> FieldTail { .text(String(before.suffix(count))) }
}

@Suite("Accepting against a read that lags the last keystroke")
struct LaggingReadAcceptTests {
    private func acceptor(_ field: RecordingField, before: String) -> SuggestionAcceptor {
        let focus = EchoedFocus(field: field, before: before)
        return SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: RecordingTypist()), focus: focus)
    }

    @Test("A read one key behind inserts the remainder the field needs now, not the one drawn.")
    func rebasesOntoTheEchoedLine() async throws {
        let field = RecordingField()
        try await acceptor(field, before: "$ sudo s").accept(.certain("sudo su ubuntu"), after: "sudo ")
        #expect(field.text == ["u ubuntu"])
    }

    @Test("A field that matches the read gets the drawn edit unchanged.")
    func keepsACurrentEdit() async throws {
        let field = RecordingField()
        try await acceptor(field, before: "$ sudo ").accept(.certain("sudo su ubuntu"), after: "sudo ")
        #expect(field.text == ["su ubuntu"])
    }

    @Test("A field that has moved off the suggestion is refused and left alone.")
    func refusesADivergedLine() async throws {
        let field = RecordingField()
        await #expect(throws: TextInsertionError.self) {
            try await acceptor(field, before: "$ sudo x").accept(.certain("sudo su ubuntu"), after: "sudo ")
        }
        #expect(field.text.isEmpty)
    }

    @Test("A field already holding the whole suggestion is written nothing.")
    func writesNothingWhenComplete() async throws {
        let field = RecordingField()
        let method = try await acceptor(field, before: "$ sudo su ubuntu")
            .accept(.certain("sudo su ubuntu"), after: "sudo ")
        #expect(method == nil)
        #expect(field.text.isEmpty)
    }

    @Test("A replacement is refused when the field no longer ends with the line it was drawn for.")
    func refusesAStaleReplacement() async throws {
        let field = RecordingField()
        await #expect(throws: TextInsertionError.self) {
            try await acceptor(field, before: "gti cx").accept(.certain("git commit -m"), after: "gti c")
        }
        #expect(field.text.isEmpty)
    }
}

/// Focus whose field has stopped answering, or hides what is typed, at the moment of acceptance.
private struct ChangedFocus: AccessibilityFocus {
    let field: any FocusedTextField
    let isSecure: Bool
    let tail: FieldTail
    var windowNumber: UInt32? = nil
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? { nil }
    func focusedFieldIsSecure() -> Bool { isSecure }
    func tail(upTo count: Int) -> FieldTail { tail }
    func windowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail) {
        (windowNumber, tail)
    }
}

@Suite("Accepting into a field that changed under the ghost")
struct ChangedFieldAcceptTests {
    private func acceptor(
        _ field: RecordingField, typist: RecordingTypist, isSecure: Bool = false, tail: FieldTail
    ) -> SuggestionAcceptor {
        let focus = ChangedFocus(field: field, isSecure: isSecure, tail: tail)
        return SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: typist), focus: focus)
    }

    @Test("A field that cannot be read at acceptance is refused, and an add-only edit writes nothing.")
    func refusesAnUnreadableAppend() async {
        let field = RecordingField()
        let typist = RecordingTypist()
        let accepting = acceptor(field, typist: typist, tail: .unreadable)
        #expect(
            await accepting.aim(.certain("git commit"), after: "git com")
                == .refused("the focused field cannot be read"))
        await #expect(throws: TextInsertionError.self) {
            try await accepting.accept(.certain("git commit"), after: "git com")
        }
        #expect(field.text.isEmpty)
        #expect(typist.text.isEmpty)
    }

    @Test("A field that cannot be read at acceptance is refused, and a replacing edit sends no backspace.")
    func refusesAnUnreadableReplacement() async {
        let field = RecordingField()
        let typist = RecordingTypist()
        await #expect(throws: TextInsertionError.self) {
            try await acceptor(field, typist: typist, tail: .unreadable)
                .accept(.certain("git commit -m"), after: "gti c")
        }
        #expect(field.text.isEmpty)
        #expect(field.replaced.isEmpty)
        #expect(typist.deletions.isEmpty)
    }

    @Test("A field that hides what is typed is refused even when its line reads as the one drawn.")
    func refusesASecureField() async {
        let field = RecordingField()
        let typist = RecordingTypist()
        let accepting = acceptor(field, typist: typist, isSecure: true, tail: .text("git com"))
        #expect(
            await accepting.aim(.certain("git commit"), after: "git com")
                == .refused("the focused field hides what is typed"))
        await #expect(throws: TextInsertionError.self) {
            try await accepting.accept(.certain("git commit"), after: "git com")
        }
        #expect(field.text.isEmpty)
    }

    @Test("A readable field that is the drawn line is aimed at the edit drawn.")
    func aimsAtAReadableField() async {
        let field = RecordingField()
        let accepting = acceptor(field, typist: RecordingTypist(), tail: .text("git com"))
        let aim = await accepting.aim(.certain("git commit"), after: "git com")
        #expect(aim == .write(Acceptance.Edit(replaced: "", inserted: "mit")))
    }

    @Test("Matching text in a different window is refused before any insertion is attempted.")
    func refusesMatchingTextInAnotherWindow() async {
        let field = RecordingField()
        let typist = RecordingTypist()
        let focus = ChangedFocus(field: field, isSecure: false, tail: .text("git com"), windowNumber: 42)
        let accepting = SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: typist), focus: focus)

        let aim = await accepting.aim(
            .certain("git commit"), after: "git com", expectedWindowNumber: 41)

        #expect(aim == .refused("the focused field is in a different or unidentified window"))
        #expect(field.text.isEmpty)
        #expect(typist.text.isEmpty)
    }

    @Test("An unidentified focused window cannot authorize an acceptance for a known window.")
    func refusesUnidentifiedWindow() async {
        let field = RecordingField()
        let focus = ChangedFocus(field: field, isSecure: false, tail: .text("git com"))
        let accepting = SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: RecordingTypist()), focus: focus)

        #expect(
            await accepting.aim(.certain("git commit"), after: "git com", expectedWindowNumber: 41)
                == .refused("the focused field is in a different or unidentified window"))
    }
}
