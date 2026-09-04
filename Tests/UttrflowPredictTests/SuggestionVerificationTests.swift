import Foundation
import Testing

@testable import UttrflowPredict

/// A candidate the corpus is sure of, so the ranking always has something to offer the gates.
private func habit(_ text: String, count: Int = 40) -> Candidate {
    remembered(text, count: count)
}

/// What one turn asks the gates about, or a failure saying it asked them nothing.
private func requested(
    _ session: inout SuggestionSession, typing typed: String, candidates: [Candidate],
    in surface: Surface = terminal
) throws -> VerificationRequest {
    let turn = session.turn(in: surface, at: PredictionContext(typed: typed))
    guard case .query(let query) = turn.step else {
        Issue.record("expected a query")
        throw CancellationError()
    }
    guard
        case .verify(let request) = session.resolve(
            candidates, for: query, now: now, elapsedMilliseconds: 0)
    else {
        Issue.record("expected the gates to be asked")
        throw CancellationError()
    }
    return request
}

/// Runs one whole turn through real gates, from the moment to the drawn answer.
private func drawVerified(
    _ session: inout SuggestionSession, typing typed: String, candidates: [Candidate],
    machine: [EnvironmentKind: [String]] = [:], scoring: (any CandidateScoring)? = nil,
    supersession: (any SupersessionRecording)? = nil, elapsed: Int = 0
) async throws -> SuggestionUpdate? {
    let request = try requested(&session, typing: typed, candidates: candidates)
    let verifier = await warmed(
        machine, on: candidates[0].text, scoring: scoring, supersession: supersession)
    let allowed = await verifier.verified(
        request.candidates, in: request.surface, typed: request.typed, now: moment)
    return session.resolve(allowed, for: request, now: now, elapsedMilliseconds: elapsed)
}

@Suite("Verifying what is about to be drawn")
struct SuggestionVerificationTests {
    @Test("A candidate the gates correct is drawn corrected, without a word about the wrong one.")
    func aCorrectionIsDrawnSilently() async throws {
        var session = SuggestionSession()
        let update = try await drawVerified(
            &session, typing: "git comi", candidates: [habit("git comit")],
            machine: [.gitSubcommand: ["commit", "checkout"]])
        #expect(update?.suggestion == .certain("git commit"))
    }

    @Test("The corrected text is what the accept key takes, replacing the letters it disagrees with.")
    func aCorrectionIsWhatTabTakes() async throws {
        var session = SuggestionSession()
        _ = try await drawVerified(
            &session, typing: "git comi", candidates: [habit("git comit")],
            machine: [.gitSubcommand: ["commit"]])
        #expect(session.route(KeyStroke(.tab)) == .accept("git commit"))
        let edit = try #require(Acceptance.edit(accepting: "git commit", after: "git comi"))
        #expect(edit.replaced == "i")
        #expect(edit.inserted == "mit")
    }

    @Test("A candidate the gates refuse is dropped, and the next one takes its place.")
    func aRefusalPromotesTheNextCandidate() async throws {
        var session = SuggestionSession()
        let update = try await drawVerified(
            &session, typing: "git c", candidates: [habit("git zqxjw"), habit("git commit", count: 30)],
            machine: [.gitSubcommand: ["commit"]], scoring: ScriptedScoring(disliked))
        #expect(update?.suggestion == .certain("git commit"))
    }

    @Test("Every candidate the gates refuse leaves nothing to draw at all.")
    func refusingEverythingDrawsNothing() async throws {
        var session = SuggestionSession()
        let update = try await drawVerified(
            &session, typing: "git z", candidates: [habit("git zqxjw")],
            machine: [.gitSubcommand: ["commit"]], scoring: ScriptedScoring(disliked))
        #expect(update == .quiet(because: .nothingOffered))
    }

    @Test("A refused candidate is reported to the store, so it stops accruing weight where it lives.")
    func aRefusalIsReported() async throws {
        var session = SuggestionSession()
        let store = RecordingSupersession()
        _ = try await drawVerified(
            &session, typing: "git z", candidates: [habit("git zqxjw")],
            machine: [.gitSubcommand: ["commit"]], scoring: ScriptedScoring(disliked),
            supersession: store)
        #expect(await store.rejected == ["git zqxjw"])
    }

    @Test("A corrected candidate is reported to the store, naming what replaces it.")
    func aCorrectionIsReported() async throws {
        var session = SuggestionSession()
        let store = RecordingSupersession()
        _ = try await drawVerified(
            &session, typing: "git comi", candidates: [habit("git comit")],
            machine: [.gitSubcommand: ["commit"]], supersession: store)
        #expect(await store.recorded == ["git comit → git commit"])
    }

    @Test("Only the head of the ranking is judged, so a long list cannot cost a verdict each.")
    func onlyTheHeadIsJudged() throws {
        var session = SuggestionSession()
        let many = (0..<12).map { habit("git commit \($0)", count: 40 - $0) }
        let request = try requested(&session, typing: "git c", candidates: many)
        #expect(request.candidates.count == SuggestionSession.verifiedDepth)
        #expect(request.candidates.first?.text == "git commit 0")
    }

    @Test("A turn with nothing worth drawing never troubles the gates at all.")
    func nothingOnOfferIsNothingToJudge() throws {
        var session = SuggestionSession()
        let turn = session.turn(in: terminal, at: PredictionContext(typed: "git c"))
        guard case .query(let query) = turn.step else {
            Issue.record("expected a query")
            return
        }
        #expect(
            session.resolve([], for: query, now: now, elapsedMilliseconds: 0)
                == .settled(.quiet(because: .nothingOffered)))
    }

    @Test("What is asked of the gates carries the field and what was typed into it.")
    func theRequestNamesTheMoment() throws {
        var session = SuggestionSession()
        let request = try requested(&session, typing: "git c", candidates: [habit("git commit")])
        #expect(request.surface == terminal)
        #expect(request.typed == "git c")
    }
}

@Suite("What the gates are allowed to cost a keystroke")
struct SuggestionVerificationBudgetTests {
    @Test("Past its budget the gates draw only what the machine had already attested.")
    func pastTheBudgetOnlyAttestationIsDrawn() async throws {
        var session = SuggestionSession()
        let slow = ScriptedScoring(liked, delay: .seconds(1))
        let update = try await drawVerified(
            &session, typing: "git c", candidates: [habit("git cm"), habit("git czqxjw", count: 30)],
            machine: [.gitAlias: ["cm"], .gitSubcommand: ["cm"]], scoring: slow)
        #expect(update?.suggestion == .certain("git cm"))
        #expect(await slow.asked == 1)
    }

    @Test("A model still loading is never waited on, so the statistical tiers draw alone.")
    func aLoadingModelIsNeverWaitedOn() async throws {
        var session = SuggestionSession()
        let loading = ScriptedScoring(disliked, loaded: false, delay: .seconds(1))
        let update = try await drawVerified(
            &session, typing: "git z", candidates: [habit("git zqxjw")], scoring: loading)
        #expect(update?.suggestion == .certain("git zqxjw"))
        #expect(await loading.asked == 0)
    }

    @Test("A verdict reached past the turn's budget is not drawn, because the moment has gone.")
    func aLateVerdictIsNotDrawn() async throws {
        var session = SuggestionSession()
        let update = try await drawVerified(
            &session, typing: "git c", candidates: [habit("git commit")],
            elapsed: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(update == .quiet(because: .overBudget))
    }

    @Test("A verdict for a moment the user has typed past is dropped rather than drawn.")
    func aStaleVerdictIsDropped() throws {
        var session = SuggestionSession()
        let request = try requested(&session, typing: "git c", candidates: [habit("git commit")])
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git co"))
        #expect(session.resolve([habit("git commit")], for: request, now: now, elapsedMilliseconds: 0) == nil)
    }

    @Test("A verdict for a field the user has left is dropped rather than drawn.")
    func aVerdictForAnotherFieldIsDropped() throws {
        var session = SuggestionSession()
        let request = try requested(&session, typing: "git c", candidates: [habit("git commit")])
        _ = session.turn(
            in: Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea"),
            at: PredictionContext(typed: "git c"))
        #expect(session.resolve([habit("git commit")], for: request, now: now, elapsedMilliseconds: 0) == nil)
    }
}
