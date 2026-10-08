import Testing
import UttrflowCore
import UttrflowPredict

@testable import Uttrflow

@Suite("Giving a failed suggestion's accept key back")
struct SuggestionAcceptKeyGiveBackTests {
    @Test("a successful insertion keeps the accept key")
    @MainActor
    func successfulTakeDoesNotReturnTab() async {
        var attempts = 0
        var completed: AcceptanceOutcome?
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            attempts += 1
            return .inserted
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
            UttrflowPredict.KeyStroke(.tab)
        ) {
            attempts += 1
            return .refused
        } completed: { outcome in
            completed = outcome
        }
        var posted: [UttrflowPredict.KeyStroke] = []
        if let keyToReturn { posted.append(keyToReturn) }

        #expect(attempts == 1)
        #expect(completed == .refused)
        #expect(posted == [UttrflowPredict.KeyStroke(.tab)])
    }

    @Test("uncertain writes consume Tab instead of replaying it")
    @MainActor
    func uncertainWritesDoNotReturnTab() async {
        let errors: [TextInsertionError] = [
            .insertionInterrupted(typed: 1, total: 2), .insertionUnconfirmed,
        ]
        for error in errors {
            let outcome = SuggestionCoordinator.acceptanceOutcome(for: error)
            let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
                UttrflowPredict.KeyStroke(.tab)
            ) {
                outcome
            }

            #expect(outcome == .mayHaveWritten)
            #expect(keyToReturn == nil)
        }
    }

    @Test("proven unwritten insertion errors return Tab")
    @MainActor
    func unwrittenErrorsReturnTab() async {
        let error = TextInsertionError.insertionRejected(description: "unwritten")
        let outcome = SuggestionCoordinator.acceptanceOutcome(for: error)
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            outcome
        }

        #expect(outcome == .refused)
        #expect(keyToReturn == UttrflowPredict.KeyStroke(.tab))
    }

    @Test("a changed insertion target restores the offer and returns Tab")
    @MainActor
    func changedTargetReturnsTab() async {
        let outcome = SuggestionCoordinator.acceptanceOutcome(for: .insertionTargetChanged)
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            outcome
        }

        #expect(outcome == .refused)
        #expect(keyToReturn == UttrflowPredict.KeyStroke(.tab))
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
        #expect(session.route(UttrflowPredict.KeyStroke(.tab)) == .accept("git commit -m"))
        var completions = 0
        let outcome = SuggestionCoordinator.acceptanceOutcome(
            for: .insertionRejected(description: "unwritten"))
        var posted: [UttrflowPredict.KeyStroke] = []

        let returnedKey = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            outcome
        } completed: { completed in
            completions += 1
            session.completeAcceptance(completed)
        }
        if let returnedKey { posted.append(returnedKey) }

        #expect(completions == 1)
        #expect(session.typed == "git c")
        #expect(session.suggestion == .certain("git commit -m"))
        #expect(posted == [UttrflowPredict.KeyStroke(.tab)])
    }
}
