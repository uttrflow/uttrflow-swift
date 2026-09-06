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
    let context = context ?? PredictionContext(typed: typed)
    let turn = session.turn(in: surface, at: context, acceptKey: acceptKey, isQuiet: isQuiet)
    if let update = settled(turn) { return update }
    let asked = try query(turn)
    switch session.resolve(candidates, for: asked, now: moment, elapsedMilliseconds: elapsed) {
    case .settled(let update):
        return update
    case .verify(let request):
        return session.resolve(
            request.candidates, for: request, now: moment, elapsedMilliseconds: elapsed)
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
        #expect(settled(turn) == .quiet(because: .nothingFocused))
        #expect(session.surface == nil)
    }

    @Test("An empty field is not a prefix of anything, so nothing is asked.")
    func emptyIsQuiet() {
        var session = SuggestionSession()
        #expect(
            settled(session.turn(in: field, at: PredictionContext(typed: ""))) == .quiet(because: .emptyLine))
    }

    @Test("A document's whole value is not a prefix worth matching.")
    func longValuesAreQuiet() {
        var session = SuggestionSession()
        let essay = String(repeating: "a", count: SuggestionSession.maximumTypedLength + 1)
        #expect(
            settled(session.turn(in: field, at: PredictionContext(typed: essay)))
                == .quiet(because: .lineTooLong))
    }

    @Test(
        "A quieting rule refuses before the store is asked at all, and the update names the rule.",
        arguments: [true, false])
    func quietingRefusesFirst(secure: Bool) {
        var session = SuggestionSession()
        let context = PredictionContext(typed: "git c", hasSelection: !secure, isSecure: secure)
        #expect(
            settled(session.turn(in: field, at: context))
                == .quiet(because: secure ? .secureField : .textSelected))
    }

    @Test(
        "Each rule of the moment carries its own reason through the session.",
        arguments: [
            (PredictionContext(typed: "x", caretAtLineEnd: false), Quieting.Reason.caretInsideText),
            (PredictionContext(typed: "x", isProse: true, millisecondsSinceKeystroke: 100), .writingFluently),
            (PredictionContext(typed: "x", caretAtLineEnd: false, hasSelection: true), .textSelected),
        ])
    func eachRuleNamesItself(context: PredictionContext, expected: Quieting.Reason) {
        var session = SuggestionSession()
        #expect(settled(session.turn(in: field, at: context)) == .quiet(because: expected))
    }

    @Test("A slow turn draws nothing, because it is answering a moment that has passed.")
    func slownessDrawsNothing() throws {
        var session = SuggestionSession()
        let update = try draw(
            &session, typing: "git c", elapsed: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(update == .quiet(because: .overBudget))
    }

    @Test("A verdict reached past the budget draws nothing either, for the same reason.")
    func slowVerificationDrawsNothing() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        guard
            case .verify(let request) = session.resolve(
                lone(), for: asked, now: moment, elapsedMilliseconds: 0)
        else {
            Issue.record("a strong candidate should have gone to the gates")
            return
        }
        let late = session.resolve(
            request.candidates, for: request, now: moment,
            elapsedMilliseconds: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(late == .quiet(because: .overBudget))
    }

    @Test("The gates leaving nothing is nothing offered.")
    func gatesLeavingNothingIsNothingOffered() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        guard
            case .verify(let request) = session.resolve(
                lone(), for: asked, now: moment, elapsedMilliseconds: 0)
        else {
            Issue.record("a strong candidate should have gone to the gates")
            return
        }
        #expect(
            session.resolve([], for: request, now: moment, elapsedMilliseconds: 0)
                == .quiet(because: .nothingOffered))
    }

    @Test("A leader too faint to draw says so, rather than that nothing was found.")
    func thinEvidenceNamesItself() throws {
        var session = SuggestionSession()
        let faint = [remembered("git commit -m", count: 1, lastUsed: daysAgo(400))]
        #expect(try draw(&session, typing: "git c", candidates: faint) == .quiet(because: .evidenceTooThin))
    }

    @Test("An irreversible command withheld for want of certainty says so.")
    func irreversibleWithheldNamesItself() throws {
        var session = SuggestionSession()
        let alone = [remembered("rm -rf build", count: 90, irreversible: true)]
        #expect(
            try draw(&session, typing: "rm", candidates: alone) == .quiet(because: .irreversibleNotCertain))
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
        #expect(try draw(&session, typing: "git commit -m") == .quiet(because: .nothingOffered))
    }

    @Test("An answer for a question the user has moved on from is dropped.")
    func staleAnswersAreDropped() throws {
        var session = SuggestionSession()
        let first = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.turn(in: field, at: PredictionContext(typed: "git co"))
        #expect(session.resolve(lone(), for: first, now: moment, elapsedMilliseconds: 0) == nil)
    }

    @Test("An answer for a field the user has left is dropped.")
    func answersForOtherFieldsAreDropped() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.turn(in: other, at: PredictionContext(typed: "git c"))
        #expect(session.resolve(lone(), for: asked, now: moment, elapsedMilliseconds: 0) == nil)
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
        #expect(try draw(&session, typing: "git c") == .quiet(because: .rejectedTooOften))
    }

    @Test("Clearing the line starts the count again, so three wrong guesses never silence a terminal.")
    func anEmptiedLineForgetsTheRefusals() throws {
        var session = SuggestionSession()
        for round in 0..<Quieting.rejectionsBeforeSilence {
            _ = try draw(&session, typing: "git c")
            _ = session.turn(in: field, at: PredictionContext(typed: "zzz\(round)"))
            _ = session.turn(in: field, at: PredictionContext(typed: ""))
        }
        #expect(session.rejectionsHere == 0)
        #expect(try draw(&session, typing: "git c")?.suggestion == .certain("git commit -m"))
    }

    @Test(
        "A silence the machine imposed is named as its own, and every other empty answer as nothing offered.")
    func generatedSilenceIsNamed() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "vim .env")))
        let denied = session.resolveGenerated(
            [], for: asked, elapsedMilliseconds: 0, whenEmpty: .notOnThisMachine)
        #expect(denied?.silence == .notOnThisMachine)
        #expect(session.resolveGenerated([], for: asked, elapsedMilliseconds: 0)?.silence == .nothingOffered)
    }

    @Test("Typing past a guess the model invented is not a refusal: the model was wrong, not the field.")
    func aGeneratedGuessIsNotRefused() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveGenerated(["git checkout"], for: asked, elapsedMilliseconds: 0)
        #expect(session.suggestion == .certain("git checkout"))
        let turn = session.turn(in: field, at: PredictionContext(typed: "git x"))
        #expect(turn.rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test(
        "Alternatives that arrive after the one generated line turn it into a choice, without moving the highlight."
    )
    func alternativesExpandTheGeneratedLine() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveGenerated(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        let expanded = session.expandGenerated(
            ["git checkout main", "git commit -m", "svn clone", "git c", "git clone"], for: asked)
        #expect(
            expanded?.suggestion
                == .choice(leader: "git commit -m", others: ["git checkout main", "git clone"]))
        #expect(session.selection == .untouched)
        #expect(session.turn(in: field, at: PredictionContext(typed: "git x")).rejected == nil)
    }

    @Test(
        "The same line drawn again from the corpus keeps the list the model put behind it, so Down still opens."
    )
    func aRedrawOfTheSameLineKeepsItsList() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveGenerated(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        _ = session.expandGenerated(["git checkout main"], for: asked)
        let again = try draw(&session, typing: "git c")
        #expect(again?.suggestion == .choice(leader: "git commit -m", others: ["git checkout main"]))
        #expect(again?.armed.contains(.downArrow) == true)
        // A different line is a different answer, and takes the list with it.
        let other = try draw(&session, typing: "git c", candidates: lone("git clone"))
        #expect(other?.suggestion == .certain("git clone"))
    }

    @Test("Alternatives that add nothing, or arrive after the user has typed on, change nothing.")
    func emptyOrStaleAlternativesAreDropped() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveGenerated(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        #expect(session.expandGenerated([], for: asked) == nil)
        #expect(session.expandGenerated(["git commit -m", "svn clone"], for: asked) == nil)
        #expect(session.suggestion == .certain("git commit -m"))
        _ = session.turn(in: field, at: PredictionContext(typed: "git co"))
        #expect(session.expandGenerated(["git checkout main"], for: asked) == nil)
    }

    @Test("Alternatives never attach to a remembered line, which the gates chose and the model did not.")
    func rememberedLinesTakeNoAlternatives() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let current = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        #expect(session.suggestion == .certain("git commit -m"))
        #expect(session.expandGenerated(["git checkout main"], for: current) == nil)
    }

    @Test("A remembered suggestion drawn after a generated one counts again when typed past.")
    func aRememberedSuggestionCountsAgain() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveGenerated(["git checkout"], for: asked, elapsedMilliseconds: 0)
        _ = try draw(&session, typing: "git co")
        #expect(session.turn(in: field, at: PredictionContext(typed: "git x")).rejected == "git commit -m")
        #expect(session.rejectionsHere == 1)
    }

    @Test("A difference only of case is still typing the suggestion, not typing past it.")
    func caseAloneIsNotTypingPast() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.turn(in: field, at: PredictionContext(typed: "Git co")).rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test("Finishing the suggestion by hand and typing on is taking it, not typing past it.")
    func typingOnPastTheEndIsNotARefusal() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let turn = session.turn(in: field, at: PredictionContext(typed: "git commit -m 'fix'"))
        #expect(turn.rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test("A second space typed past a suggestion is a slip, not a refusal, so backspacing costs nothing.")
    func whitespaceAloneIsNotTypingPast() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.turn(in: field, at: PredictionContext(typed: "git c  ")).rejected == nil)
        #expect(session.rejectionsHere == 0)
        _ = try draw(&session, typing: "git c")
        #expect(session.turn(in: field, at: PredictionContext(typed: "git cx")).rejected == "git commit -m")
        #expect(session.rejectionsHere == 1)
    }

    @Test(
        "Typing toward a correction is neither counted nor reported, since the offer never continued the line."
    )
    func aCorrectionTypedPastIsNeitherReportedNorCounted() throws {
        var session = SuggestionSession()
        let corrected = [remembered("git commit -m", count: 40, editDistance: 1)]
        let update = try draw(&session, typing: "gti c", candidates: corrected)
        #expect(update?.suggestion.accepting == "git commit -m")
        let turn = session.turn(in: field, at: PredictionContext(typed: "gti co"))
        #expect(turn.rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test("Shortening the line under a corrected offer reports nothing either.")
    func shorteningUnderACorrectionReportsNothing() throws {
        var session = SuggestionSession()
        let corrected = [remembered("git commit -m", count: 40, editDistance: 1)]
        _ = try draw(&session, typing: "gti c", candidates: corrected)
        #expect(session.turn(in: field, at: PredictionContext(typed: "gti ")).rejected == nil)
        #expect(session.rejectionsHere == 0)
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
        #expect(session.resolve(lone(), for: asked, now: moment, elapsedMilliseconds: 0) == nil)
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
        #expect(update.silence == .minimised)
        #expect(update.armed.contains(.escape))
    }

    @Test("A minimised field stays minimised while its own value keeps growing.")
    func minimisedStaysMinimised() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        let update = settled(session.turn(in: field, at: PredictionContext(typed: "git co")))
        #expect(update?.suggestion == .minimised)
        #expect(update?.silence == .minimised)
    }

    @Test("Clearing the line lifts one escape, so a terminal is not silenced for hours by a single press.")
    func anEmptiedLineLiftsTheDot() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        #expect(
            settled(session.turn(in: field, at: PredictionContext(typed: ""))) == .quiet(because: .emptyLine))
        #expect(try draw(&session, typing: "git c")?.suggestion == .certain("git commit -m"))
    }

    @Test("A second escape silences the field for the rest of its life.")
    func secondEscapeSilencesTheField() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        _ = session.route(KeyStroke(.escape))
        #expect(session.route(KeyStroke(.escape)) == .redraw(.quiet(because: .turnedOffHere)))
        #expect(session.isSilencedHere)
        #expect(try draw(&session, typing: "git c") == .quiet(because: .turnedOffHere))
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
        #expect(update == .quiet(because: .turnedOffHere))
        #expect(!session.isEnabled)
        #expect(try draw(&session, typing: "git c", in: other) == .quiet(because: .turnedOffHere))
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
        #expect(update == .quiet(because: .quietModeChoice))
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

@Suite("Generating a suggestion the corpus never held")
struct GeneratedSuggestionTests {
    /// The query one turn asks, or a failure saying it asked nothing.
    private func asked(
        _ session: inout SuggestionSession, typing typed: String
    ) throws
        -> SuggestionQuery
    {
        try query(session.turn(in: field, at: PredictionContext(typed: typed)))
    }

    @Test("A lone continuation the model invents is drawn as a certain suggestion.")
    func loneGenerated() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(["git checkout"], for: asked, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .certain("git checkout"))
    }

    @Test("Several continuations become a choice, kept in the order the model ranked them.")
    func rankedChoice() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["git checkout", "git commit", "git cherry-pick"], for: asked, elapsedMilliseconds: 0)
        #expect(
            update?.suggestion
                == .choice(leader: "git checkout", others: ["git commit", "git cherry-pick"]))
    }

    @Test("A continuation that does not extend what is typed is not a ghost, so it is dropped.")
    func mustExtendTyped() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["svn commit", "git commit"], for: asked, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .certain("git commit"))
    }

    @Test("When nothing the model returns can be shown, nothing is.")
    func nothingUsable() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(["svn commit"], for: asked, elapsedMilliseconds: 0)
        #expect(update == .quiet(because: .nothingOffered))
    }

    @Test("An alternative that repeats the line, or the leader, in another case is not a second line.")
    func caseVariantsAreOneLine() throws {
        var session = SuggestionSession()
        let first = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["git checkout", "Git Checkout", "git commit"], for: first, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .choice(leader: "git checkout", others: ["git commit"]))
        var again = SuggestionSession()
        let lone = try asked(&again, typing: "git c")
        _ = again.resolveGenerated(["git checkout"], for: lone, elapsedMilliseconds: 0)
        #expect(again.expandGenerated(["GIT CHECKOUT", "Git Checkout"], for: lone) == nil)
        let expanded = again.expandGenerated(["Git Checkout", "git commit", "GIT COMMIT"], for: lone)
        #expect(expanded?.suggestion == .choice(leader: "git checkout", others: ["git commit"]))
    }

    @Test("A generation reached past the turn's budget is not drawn.")
    func pastBudget() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["git checkout"], for: asked,
            elapsedMilliseconds: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(update == .quiet(because: .overBudget))
    }
}
