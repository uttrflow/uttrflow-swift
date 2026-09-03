import Foundation
import Testing

@testable import UttrflowPredict

/// The field every test in this suite types into.
private let field = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")

/// A second field, for the tests about leaving one.
private let other = Surface(bundleIdentifier: "com.apple.Safari", role: "AXTextField")

/// One candidate strong enough to be offered on its own.
private func lone(_ text: String = "git commit -m") -> [Candidate] {
    [remembered(text, count: 40)]
}

/// The query a turn asked for, or a failure saying it asked nothing.
private func query(_ turn: SuggestionTurn) throws -> SuggestionQuery {
    guard case .query(let query) = turn.step else {
        Issue.record("expected a query")
        throw CancellationError()
    }
    return query
}

/// What a turn settled on without asking anything.
private func settled(_ turn: SuggestionTurn) -> SuggestionUpdate? {
    guard case .settled(let update) = turn.step else { return nil }
    return update
}

/// Runs one whole turn with gates that allow everything, so each test names only what it is about.
func draw(
    _ session: inout SuggestionSession, typing typed: String, candidates: [Candidate] = lone(),
    context: PredictionContext? = nil, elapsed: Int = 0, in surface: Surface = field,
    acceptKey: AcceptKey = .tab, isQuiet: Bool = false
) throws -> SuggestionUpdate? {
    let moment = context ?? PredictionContext(typed: typed)
    let turn = session.turn(in: surface, at: moment, acceptKey: acceptKey, isQuiet: isQuiet)
    if let update = settled(turn) { return update }
    let asked = try query(turn)
    switch session.resolve(candidates, for: asked, now: now, elapsedMilliseconds: elapsed) {
    case .settled(let update):
        return update
    case .verify(let request):
        return session.resolve(
            request.candidates, for: request, now: now, elapsedMilliseconds: elapsed)
    case nil:
        return nil
    }
}

@Suite("Sequencing one field's suggestions")
struct SuggestionSessionTests {
    @Test("A field with something typed into it asks the store what it might be finishing.")
    func asksTheStore() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        #expect(asked.typed == "git c")
        #expect(asked.surface == field)
    }

    @Test("A strong candidate is drawn, and the accept key is claimed with it.")
    func drawsAndArms() throws {
        var session = SuggestionSession()
        let update = try #require(try draw(&session, typing: "git c"))
        #expect(update.suggestion == .certain("git commit -m"))
        #expect(update.armed.contains(.tab))
        #expect(session.suggestion == .certain("git commit -m"))
    }

    @Test("The accept key follows the application, so a terminal is not robbed of Tab.")
    func followsTheAcceptKey() throws {
        var session = SuggestionSession()
        let update = try #require(try draw(&session, typing: "git c", acceptKey: .rightArrow))
        #expect(update.armed.contains(.rightArrow))
        #expect(!update.armed.contains(.tab))
    }

    @Test("Nothing focused draws nothing and claims no key.")
    func noFieldIsQuiet() {
        var session = SuggestionSession()
        let turn = session.turn(in: nil, at: PredictionContext(typed: "git c"))
        #expect(settled(turn) == .quiet)
        #expect(session.surface == nil)
    }

    @Test("An empty field is not a prefix of anything, so nothing is asked.")
    func emptyIsQuiet() {
        var session = SuggestionSession()
        #expect(settled(session.turn(in: field, at: PredictionContext(typed: ""))) == .quiet)
    }

    @Test("A document's whole value is not a prefix worth matching.")
    func longValuesAreQuiet() {
        var session = SuggestionSession()
        let essay = String(repeating: "a", count: SuggestionSession.maximumTypedLength + 1)
        #expect(settled(session.turn(in: field, at: PredictionContext(typed: essay))) == .quiet)
    }

    @Test("A quieting rule refuses before the store is asked at all.", arguments: [true, false])
    func quietingRefusesFirst(secure: Bool) {
        var session = SuggestionSession()
        let moment = PredictionContext(typed: "git c", hasSelection: !secure, isSecure: secure)
        #expect(settled(session.turn(in: field, at: moment)) == .quiet)
    }

    @Test("A slow turn draws nothing, because it is answering a moment that has passed.")
    func slownessDrawsNothing() throws {
        var session = SuggestionSession()
        let update = try draw(
            &session, typing: "git c", elapsed: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(update == .quiet)
    }

    @Test("A turn just inside the budget still draws.")
    func theBudgetIsInclusive() throws {
        var session = SuggestionSession()
        let update = try draw(
            &session, typing: "git c", elapsed: SuggestionSession.turnBudgetInMilliseconds)
        #expect(update?.suggestion == .certain("git commit -m"))
    }

    @Test("A candidate the user has already finished typing is not offered back to them.")
    func nothingToAddIsNothingToDraw() throws {
        var session = SuggestionSession()
        #expect(try draw(&session, typing: "git commit -m") == .quiet)
    }

    @Test("An answer for a question the user has moved on from is dropped.")
    func staleAnswersAreDropped() throws {
        var session = SuggestionSession()
        let first = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.turn(in: field, at: PredictionContext(typed: "git co"))
        #expect(session.resolve(lone(), for: first, now: now, elapsedMilliseconds: 0) == nil)
    }

    @Test("An answer for a field the user has left is dropped.")
    func answersForOtherFieldsAreDropped() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.turn(in: other, at: PredictionContext(typed: "git c"))
        #expect(session.resolve(lone(), for: asked, now: now, elapsedMilliseconds: 0) == nil)
    }
}

@Suite("Typing past a suggestion")
struct SuggestionRejectionTests {
    @Test("Typing on so the offer no longer continues the line counts as a refusal.")
    func typingPastIsRejection() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let turn = session.turn(in: field, at: PredictionContext(typed: "git p"))
        #expect(turn.rejected == "git commit -m")
        #expect(session.rejectionsHere == 1)
    }

    @Test("Typing further into the offer is not a refusal.")
    func continuingIsNotRejection() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.turn(in: field, at: PredictionContext(typed: "git co")).rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test("Leaving the field is not a refusal, and forgets the ones it collected.")
    func leavingForgets() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.turn(in: field, at: PredictionContext(typed: "git p"))
        let turn = session.turn(in: other, at: PredictionContext(typed: "git p"))
        #expect(turn.rejected == nil)
        #expect(session.rejectionsHere == 0)
        #expect(session.suggestion == .silent)
    }

    @Test("Enough refusals in one field silence it.")
    func enoughRefusalsSilenceTheField() throws {
        var session = SuggestionSession()
        for round in 0..<Quieting.rejectionsBeforeSilence {
            _ = try draw(&session, typing: "git c")
            _ = session.turn(in: field, at: PredictionContext(typed: "zzz\(round)"))
        }
        #expect(session.rejectionsHere == Quieting.rejectionsBeforeSilence)
        #expect(try draw(&session, typing: "git c") == .quiet)
    }
}

@Suite("What the tap's keystrokes come to")
struct SuggestionRoutingTests {
    @Test("The accept key takes the offer and clears the surface behind it.")
    func acceptTakesTheOffer() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.route(KeyStroke(.tab)) == .accept("git commit -m"))
        #expect(session.suggestion == .silent)
        #expect(session.typed == "git commit -m")
    }

    @Test("An answer still in flight when the offer is taken is dropped.")
    func acceptingDropsWhatIsInFlight() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.route(KeyStroke(.tab))
        #expect(session.resolve(lone(), for: asked, now: now, elapsedMilliseconds: 0) == nil)
    }

    @Test("A key nothing has claimed changes nothing.")
    func unclaimedKeysDoNothing() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.route(KeyStroke(.return)) == .nothing)
        #expect(session.suggestion == .certain("git commit -m"))
    }

    @Test("Down walks the list and Return then takes what it landed on.")
    func downThenReturnAccepts() throws {
        var session = SuggestionSession()
        let close = [remembered("git commit", count: 20), remembered("git checkout", count: 19)]
        _ = try draw(&session, typing: "git c", candidates: close)
        guard case .redraw(let moved) = session.route(KeyStroke(.downArrow)) else {
            Issue.record("Down should have moved the highlight")
            return
        }
        #expect(moved.armed.contains(.return))
        #expect(session.selection.hasMoved)
        #expect(session.route(KeyStroke(.return)) == .accept("git checkout"))
    }

    @Test("Escape minimises to the dot, which still answers a second escape.")
    func escapeMinimises() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        guard case .redraw(let update) = session.route(KeyStroke(.escape)) else {
            Issue.record("escape should have redrawn")
            return
        }
        #expect(update.suggestion == .minimised)
        #expect(update.armed.contains(.escape))
    }

    @Test("A minimised field stays minimised while its own value keeps growing.")
    func minimisedStaysMinimised() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        #expect(
            settled(session.turn(in: field, at: PredictionContext(typed: "git co")))?.suggestion
                == .minimised)
    }

    @Test("A second escape silences the field for the rest of its life.")
    func secondEscapeSilencesTheField() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        _ = session.route(KeyStroke(.escape))
        #expect(session.isSilencedHere)
        #expect(try draw(&session, typing: "git c") == .quiet)
    }

    @Test("Leaving the field lifts the silence, since it belonged to the field.")
    func silenceDoesNotFollowTheUser() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        _ = session.route(KeyStroke(.escape))
        _ = session.turn(in: other, at: PredictionContext(typed: ""))
        #expect(!session.isSilencedHere)
    }

    @Test("Option-escape turns the whole feature off, everywhere.")
    func optionEscapeTurnsItOff() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        guard case .redraw(let update) = session.route(KeyStroke(.escape, modifiers: .option))
        else {
            Issue.record("option-escape should have redrawn")
            return
        }
        #expect(update == .quiet)
        #expect(!session.isEnabled)
        #expect(try draw(&session, typing: "git c", in: other) == .quiet)
    }
}

/// Two candidates close enough that the engine offers a list rather than one answer.
private func crowd() -> [Candidate] {
    [remembered("git commit -m", count: 10), remembered("git checkout", count: 9)]
}

@Suite("Only suggesting when it is sure")
struct QuietSuggestionTests {
    @Test("A list is what the session is unsure about, so quiet mode draws none of it.")
    func quietDrawsNoList() throws {
        var session = SuggestionSession()
        let update = try #require(try draw(&session, typing: "git c", candidates: crowd(), isQuiet: true))
        #expect(update.suggestion == .silent)
        #expect(update.armed.isEmpty)
        #expect(session.suggestion == .silent)
    }

    @Test("The same field with quiet mode off is offered the list.")
    func theListIsThereWithoutQuietMode() throws {
        var session = SuggestionSession()
        let update = try #require(try draw(&session, typing: "git c", candidates: crowd()))
        #expect(update.suggestion == .choice(leader: "git commit -m", others: ["git checkout"]))
    }

    @Test("A completion it is sure of is still drawn, and still claims the accept key.")
    func quietStillDrawsCertainty() throws {
        var session = SuggestionSession()
        let update = try #require(try draw(&session, typing: "git c", isQuiet: true))
        #expect(update.suggestion == .certain("git commit -m"))
        #expect(update.armed.contains(.tab))
    }

    @Test("Removing everything short of certainty leaves every other answer alone.")
    func certainOnlyTouchesOnlyTheList() {
        #expect(Suggestion.choice(leader: "git commit", others: ["git checkout"]).certainOnly == .silent)
        #expect(Suggestion.certain("git commit").certainOnly == .certain("git commit"))
        #expect(Suggestion.silent.certainOnly == .silent)
        #expect(Suggestion.minimised.certainOnly == .minimised)
    }
}
