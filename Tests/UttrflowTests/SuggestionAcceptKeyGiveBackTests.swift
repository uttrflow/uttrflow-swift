import Testing
import UttrflowCore
import UttrflowPredict

@testable import Uttrflow

private struct SuccessfulWriteWithChangedCaretField {
    var value = "git c"
    var caret = 5
    private(set) var writeSucceeded = false

    mutating func write(_ text: String) -> TextInsertionError {
        writeSucceeded = true
        value += text
        caret += text.utf16.count + 1
        return .insertionUnconfirmed
    }
}

@Suite("Giving a failed suggestion's accept key back")
struct SuggestionAcceptKeyGiveBackTests {
    @Test("a successful insertion keeps the accept key")
    @MainActor
    func successfulTakeDoesNotReturnTab() async {
        var attempts = 0
        var completed: AcceptanceOutcome?
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            attempts += 1
            return .inserted
        } requestFreshRead: {
            Issue.record("a confirmed insertion needs no read-back")
        } completed: { outcome in
            completed = outcome
        }

        #expect(attempts == 1)
        #expect(completed == .inserted)
        #expect(keyToReturn == nil)
    }

    @Test("a failed insertion returns the swallowed Tab exactly once")
    @MainActor
    func failedTakeReturnsTabOnce() async {
        var attempts = 0
        var completed: AcceptanceOutcome?
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            attempts += 1
            return .refused
        } requestFreshRead: {
            Issue.record("a refusal leaves the field unchanged")
        } completed: { outcome in
            completed = outcome
        }
        var posted: [UttrflowCore.KeyStroke] = []
        if let keyToReturn { posted.append(keyToReturn) }

        #expect(attempts == 1)
        #expect(completed == .refused)
        #expect(posted == [UttrflowCore.KeyStroke(.tab)])
    }

    @Test("uncertain writes consume Tab instead of replaying it")
    @MainActor
    func uncertainWritesDoNotReturnTab() async {
        let errors: [TextInsertionError] = [
            .insertionInterrupted(typed: 1, total: 2), .insertionUnconfirmed,
        ]
        var requestedReads = 0
        for error in errors {
            let outcome = SuggestionCoordinator.acceptanceOutcome(for: error)
            let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
                UttrflowCore.KeyStroke(.tab)
            ) {
                outcome
            } requestFreshRead: {
                requestedReads += 1
            }

            #expect(outcome == .mayHaveWritten)
            #expect(keyToReturn == nil)
        }
        #expect(requestedReads == errors.count)
    }

    @Test("an accepted write with a changed caret consumes Tab and rereads the field")
    @MainActor
    func changedCaretAfterSuccessfulWriteDoesNotReplayTabAndRereads() async {
        var field = SuccessfulWriteWithChangedCaretField()
        let error = field.write("ommit")
        var rereadLine: String?
        var rereadCaret: Int?
        var reads = 0
        var posted: [UttrflowCore.KeyStroke] = []

        let returnedKey = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            SuggestionCoordinator.acceptanceOutcome(for: error)
        } requestFreshRead: {
            reads += 1
            rereadLine = field.value
            rereadCaret = field.caret
        }
        if let returnedKey { posted.append(returnedKey) }

        #expect(field.writeSucceeded)
        #expect(field.value == "git commit")
        #expect(field.caret == 11)
        #expect(returnedKey == nil)
        #expect(posted.isEmpty)
        #expect(reads == 1)
        #expect(rereadLine == "git commit")
        #expect(rereadCaret == 11)
    }

    @Test("proven unwritten insertion errors return Tab")
    @MainActor
    func unwrittenErrorsReturnTab() async {
        let error = TextInsertionError.insertionRejected(description: "unwritten")
        let outcome = SuggestionCoordinator.acceptanceOutcome(for: error)
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            outcome
        } requestFreshRead: {
            Issue.record("a refusal leaves the field unchanged")
        }

        #expect(outcome == .refused)
        #expect(keyToReturn == UttrflowCore.KeyStroke(.tab))
    }

    @Test("a changed insertion target restores the offer and returns Tab")
    @MainActor
    func changedTargetReturnsTab() async {
        let outcome = SuggestionCoordinator.acceptanceOutcome(for: .insertionTargetChanged)
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            outcome
        } requestFreshRead: {
            Issue.record("a target change is known not to have written")
        }

        #expect(outcome == .refused)
        #expect(keyToReturn == UttrflowCore.KeyStroke(.tab))
    }

    @Test("every insertion error is classified by whether text may have reached the field")
    @MainActor
    func classifiesEveryInsertionError() {
        let errors: [(TextInsertionError, AcceptanceOutcome)] = [
            (.noFocusedTextField, .refused),
            (.accessibilityDenied, .refused),
            (.clipboardUnavailable, .mayHaveWritten),
            (.clipboardChanged, .mayHaveWritten),
            (.insertionTimedOut, .mayHaveWritten),
            (.insertionRejected(description: "refused"), .refused),
            (.insertionCancelled, .mayHaveWritten),
            (.insertionUnconfirmed, .mayHaveWritten),
            (.insertionTargetChanged, .refused),
            (.insertionFieldClosed, .refused),
            (.insertionNeedsCopy(description: "copy manually"), .refused),
            (.insertionInterrupted(typed: 1, total: 2), .mayHaveWritten),
        ]

        for (error, expected) in errors {
            #expect(SuggestionCoordinator.acceptanceOutcome(for: error) == expected)
        }
    }

    @Test("a refusal restores the session and returns the swallowed key once")
    @MainActor
    func refusalRestoresOfferAndReturnsTabOnce() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextField")
        var session = SuggestionSession()
        guard
            case .query(let query) = session.turn(
                in: surface, at: PredictionContext(typed: "git c")
            ).step
        else {
            Issue.record("the focused field should request a suggestion")
            return
        }
        let offer = session.resolveGenerated(
            ["git commit -m"], for: query, elapsedMilliseconds: 0,
            scores: ["git commit -m": Verification.certainFloor + 1])
        #expect(offer?.suggestion == .certain("git commit -m"))
        #expect(session.route(UttrflowCore.KeyStroke(.tab)) == .accept("git commit -m"))
        var completions = 0
        let outcome = SuggestionCoordinator.acceptanceOutcome(
            for: .insertionRejected(description: "unwritten"))
        var posted: [UttrflowCore.KeyStroke] = []

        let returnedKey = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowCore.KeyStroke(.tab)
        ) {
            outcome
        } requestFreshRead: {
            Issue.record("a proven refusal leaves the field unchanged")
        } completed: { completed in
            completions += 1
            session.completeAcceptance(completed)
        }
        if let returnedKey { posted.append(returnedKey) }

        #expect(completions == 1)
        #expect(session.typed == "git c")
        #expect(session.suggestion == .certain("git commit -m"))
        #expect(posted == [UttrflowCore.KeyStroke(.tab)])
    }
}
