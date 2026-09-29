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
    acceptKey: AcceptKey = .tab, isQuiet: Bool = false, sawKeystrokes: Int? = nil
) throws -> SuggestionUpdate? {
    let context = context ?? PredictionContext(typed: typed)
    let turn = session.turn(
        in: surface, at: context, acceptKey: acceptKey, isQuiet: isQuiet, sawKeystrokes: sawKeystrokes)
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

    @Test("Marked text in the field draws nothing and claims no key, so Escape reaches the input method.")
    func markedTextQuietsTheTurn() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let composing = PredictionContext(typed: "git c", markedText: .present)
        let update = try draw(&session, typing: "git c", context: composing)
        #expect(update == .quiet(because: .composing))
        #expect(update?.armed.isEmpty == true)
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
        let denied = session.resolveSure(
            [], for: asked, elapsedMilliseconds: 0, whenEmpty: .notOnThisMachine)
        #expect(denied?.silence == .notOnThisMachine)
        #expect(session.resolveSure([], for: asked, elapsedMilliseconds: 0)?.silence == .nothingOffered)
    }

    @Test(
        "Typing a suggestion's accent scalar by scalar, base letter then combining mark, is never a refusal."
    )
    func decomposedAccentTypedScalarByScalarIsNotRejected() throws {
        var session = SuggestionSession()
        // The suggestion's é arrived from the store already decomposed: "e" followed by U+0301.
        let accented = "caf" + "e\u{301}"
        _ = try draw(&session, typing: "caf", candidates: lone(accented))
        // The base letter is typed first, one keystroke ahead of its own combining mark.
        #expect(session.turn(in: field, at: PredictionContext(typed: "cafe")).rejected == nil)
        #expect(session.rejectionsHere == 0)
    }

    @Test("A model guess typed past counts toward quieting the field but blames nothing in the store.")
    func aGeneratedGuessCountsButIsNotBlamed() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git checkout"], for: asked, elapsedMilliseconds: 0)
        #expect(session.suggestion == .certain("git checkout"))
        let turn = session.turn(in: field, at: PredictionContext(typed: "git x"))
        #expect(turn.rejected == nil)
        #expect(session.rejectionsHere == 1)
    }

    @Test("Three model guesses typed past in one field quiet it, as three remembered ones do.")
    func generatedGuessesTypedPastQuietTheField() throws {
        var session = SuggestionSession()
        for _ in 0..<Quieting.rejectionsBeforeSilence {
            let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
            _ = session.resolveSure(["git checkout"], for: asked, elapsedMilliseconds: 0)
            #expect(session.turn(in: field, at: PredictionContext(typed: "git x")).rejected == nil)
        }
        #expect(session.rejectionsHere == Quieting.rejectionsBeforeSilence)
        let quiet = PredictionContext(typed: "git c", rejectionsThisSession: session.rejectionsHere)
        #expect(Quieting.reason(quiet) == .rejectedTooOften)
    }

    @Test(
        "Alternatives that arrive after the one generated line turn it into a choice, without moving the highlight."
    )
    func alternativesExpandTheGeneratedLine() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        let expanded = session.expandSure(
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
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        _ = session.expandSure(["git checkout main"], for: asked)
        let again = try draw(&session, typing: "git c")
        #expect(again?.suggestion == .choice(leader: "git commit -m", others: ["git checkout main"]))
        #expect(again?.armed.contains(.optionDownArrow) == true)
        // A different line is a different answer, and takes the list with it.
        let other = try draw(&session, typing: "git c", candidates: lone("git clone"))
        #expect(other?.suggestion == .certain("git clone"))
    }

    @Test(
        "A verified answer that dropped an alternative takes it off the list, so Down and Tab cannot reach it."
    )
    func aVerificationDropsTheAlternativeItRemoved() throws {
        var session = SuggestionSession()
        let both = [remembered("git commit", count: 5), remembered("git checkout", count: 4)]
        let first = try draw(&session, typing: "git c", candidates: both)
        #expect(first?.suggestion == .choice(leader: "git commit", others: ["git checkout"]))

        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        guard
            case .verify(let request) = session.resolve(both, for: asked, now: moment, elapsedMilliseconds: 0)
        else {
            Issue.record("expected a verification request")
            return
        }
        let second = session.resolve(
            [remembered("git commit", count: 5)], for: request, now: moment, elapsedMilliseconds: 0)

        #expect(second?.suggestion == .certain("git commit"))
        #expect(second?.armed.contains(.optionDownArrow) == false)
        _ = session.route(KeyStroke(.downArrow, modifiers: .option))
        #expect(session.route(KeyStroke(.tab)) != .accept("git checkout"))
    }

    @Test(
        "A redraw that narrows the model's list lets go of the highlight, so Return cannot take a line nobody chose."
    )
    func aNarrowedListDropsTheHighlight() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        _ = session.expandSure(["git commit --amend", "git checkout main"], for: asked)
        _ = session.route(KeyStroke(.downArrow, modifiers: .option))
        _ = session.route(KeyStroke(.downArrow, modifiers: .option))
        #expect(session.selection == SuggestionSelection(index: 2, hasMoved: true))

        let again = try draw(&session, typing: "git com")

        #expect(again?.suggestion == .choice(leader: "git commit -m", others: ["git commit --amend"]))
        #expect(session.selection == .untouched)
        #expect(session.route(KeyStroke(.return)) == .giveBack(KeyStroke(.return)))
    }

    @Test("Quiet mode keeps no list across a redraw, even the model's.")
    func quietModeKeepsNoList() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        _ = session.expandSure(["git checkout main"], for: asked)

        let again = try draw(&session, typing: "git c", isQuiet: true)

        #expect(again?.suggestion == .certain("git commit -m"))
        #expect(again?.armed.contains(.optionDownArrow) == false)
    }

    @Test("Alternatives that add nothing, or arrive after the user has typed on, change nothing.")
    func emptyOrStaleAlternativesAreDropped() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        #expect(session.expandSure([], for: asked) == nil)
        #expect(session.expandSure(["git commit -m", "svn clone"], for: asked) == nil)
        #expect(session.suggestion == .certain("git commit -m"))
        _ = session.turn(in: field, at: PredictionContext(typed: "git co"))
        #expect(session.expandSure(["git checkout main"], for: asked) == nil)
    }

    @Test("Alternatives never attach to a remembered line, which the gates chose and the model did not.")
    func rememberedLinesTakeNoAlternatives() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let current = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        #expect(session.suggestion == .certain("git commit -m"))
        #expect(session.expandSure(["git checkout main"], for: current) == nil)
    }

    @Test("A remembered suggestion drawn after a generated one is blamed again when typed past.")
    func aRememberedSuggestionCountsAgain() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git checkout"], for: asked, elapsedMilliseconds: 0)
        _ = try draw(&session, typing: "git co")
        #expect(session.turn(in: field, at: PredictionContext(typed: "git x")).rejected == "git commit -m")
        #expect(session.rejectionsHere == 2)
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

    /// The edit was worked out for the line as read, so taking it after the line has moved would eat what was typed since.
    @Test("A key typed after the offer was worked out hands Tab back to the application.")
    func acceptAfterAKeystrokeIsHandedBack() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        session.keystrokeArrived()
        #expect(session.route(KeyStroke(.tab)) == .giveBack(KeyStroke(.tab)))
        #expect(session.typed == "git c")
    }

    @Test("A stale accept by Right Arrow or Option-Tab is handed back with its modifiers.")
    func staleAcceptKeepsItsModifiers() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        session.keystrokeArrived()
        let optionTab = KeyStroke(.tab, modifiers: .option)
        #expect(session.route(optionTab) == .giveBack(optionTab))
        #expect(session.route(KeyStroke(.rightArrow)) == .giveBack(KeyStroke(.rightArrow)))
    }

    @Test("A turn that reads the line after the keystroke may be taken again.")
    func aFreshTurnMayBeTaken() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        session.keystrokeArrived()
        _ = try draw(&session, typing: "git c")
        #expect(session.route(KeyStroke(.tab)) == .accept("git commit -m"))
    }

    @Test(
        "An offer from a read that began before a keystroke is never drawn, since the line it continues has moved."
    )
    func aReadThatMissedTheKeystrokeIsStale() throws {
        var session = SuggestionSession()
        let seen = session.keystrokes
        session.keystrokeArrived()
        #expect(try draw(&session, typing: "git c", sawKeystrokes: seen) == nil)
        #expect(session.suggestion == .silent)
        #expect(session.route(KeyStroke(.tab)) == .giveBack(KeyStroke(.tab)))
    }

    @Test("A key typed while the gates judge the head drops their verdict rather than drawing it.")
    func aKeyDuringVerificationDropsTheVerdict() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        guard
            case .verify(let request) = session.resolve(
                lone(), for: asked, now: moment, elapsedMilliseconds: 0)
        else {
            Issue.record("expected the candidates to go to verification")
            return
        }
        session.keystrokeArrived()
        #expect(session.resolve(request.candidates, for: request, now: moment, elapsedMilliseconds: 0) == nil)
        #expect(session.suggestion == .silent)
    }

    @Test("A key typed while the corpus is asked drops its answer.")
    func aKeyDuringTheQueryDropsTheAnswer() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        session.keystrokeArrived()
        #expect(session.resolve(lone(), for: asked, now: moment, elapsedMilliseconds: 0) == nil)
    }

    @Test("A model pass that finishes after a key, a click or a switch is never drawn.")
    func aLatePassIsNeverDrawn() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "meet at")))
        session.invalidate()
        #expect(
            session.resolveSure(["meet at the north gate at noon"], for: asked, elapsedMilliseconds: 0)
                == nil)
        #expect(session.suggestion == .silent)
    }

    @Test("Alternatives that arrive after the caret moved do not bring the offer back.")
    func lateAlternativesAreDropped() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(["git commit -m"], for: asked, elapsedMilliseconds: 0)
        #expect(session.isCurrent)
        session.invalidate()
        #expect(!session.isCurrent)
        #expect(session.expandSure(["git checkout main"], for: asked) == nil)
    }

    @Test("Of two quick turns only the latest one's answer is drawn, whichever finishes last.")
    func onlyTheLatestTurnDraws() throws {
        var session = SuggestionSession()
        let first = try query(session.turn(in: field, at: PredictionContext(typed: "meet")))
        session.keystrokeArrived()
        let second = try query(
            session.turn(
                in: field, at: PredictionContext(typed: "meet at"), sawKeystrokes: session.keystrokes))
        let latest = session.resolveSure(
            ["meet at the north gate at noon"], for: second, elapsedMilliseconds: 0)
        #expect(latest?.suggestion == .certain("meet at the north gate at noon"))
        #expect(session.resolveSure(["meet me later"], for: first, elapsedMilliseconds: 0) == nil)
        #expect(session.suggestion == .certain("meet at the north gate at noon"))
        #expect(session.isCurrent)
    }

    @Test("A model line that differs from the typed text only in case continues the line as typed.")
    func aGeneratedLineKeepsTheTypedCase() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "Meet a")))
        let update = session.resolveSure(
            ["meet at the north gate at noon"], for: asked, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .certain("Meet at the north gate at noon"))
    }

    /// A new turn starting is not a new offer: the one still on screen was worked out for the line before the key.
    @Test("Tab while the next turn's answer is still in flight does not take the old offer.")
    func theOldOfferStaysStaleWhileTheNextIsAsked() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        session.keystrokeArrived()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git co")))
        #expect(session.suggestion == .certain("git commit -m"), "the old offer is still on screen")
        #expect(session.route(KeyStroke(.tab)) == .giveBack(KeyStroke(.tab)))
        #expect(session.typed == "git co")
        _ = asked
    }

    @Test("Once the next turn's answer is drawn, Tab takes that offer.")
    func theNextOfferIsFreshOnceDrawn() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        session.keystrokeArrived()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git co")))
        // Offered candidates are verified before anything is drawn, so both steps run.
        let resolution = session.resolve(lone(), for: asked, now: moment, elapsedMilliseconds: 0)
        guard case .verify(let request) = resolution else {
            Issue.record("expected the candidates to go to verification")
            return
        }
        _ = session.resolve(request.candidates, for: request, now: moment, elapsedMilliseconds: 0)
        #expect(session.route(KeyStroke(.tab)) == .accept("git commit -m"))
    }

    @Test("A key nothing has claimed goes back to the application unchanged.")
    func unclaimedKeysDoNothing() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.route(KeyStroke(.return)) == .giveBack(KeyStroke(.return)))
        #expect(session.suggestion == .certain("git commit -m"))
    }

    @Test("Down walks the list and Return then takes what it landed on.")
    func downThenReturnAccepts() throws {
        var session = SuggestionSession()
        let close = [remembered("git commit", count: 20), remembered("git checkout", count: 19)]
        _ = try draw(&session, typing: "git c", candidates: close)
        guard case .redraw(let moved) = session.route(KeyStroke(.downArrow, modifiers: .option)) else {
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
        let update = session.resolveSure(["git checkout"], for: asked, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .certain("git checkout"))
    }

    @Test("Several continuations become a choice, kept in the order the model ranked them.")
    func rankedChoice() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveSure(
            ["git checkout", "git commit", "git cherry-pick"], for: asked, elapsedMilliseconds: 0)
        #expect(
            update?.suggestion
                == .choice(leader: "git checkout", others: ["git commit", "git cherry-pick"]))
    }

    @Test("A continuation that does not extend what is typed is not a ghost, so it is dropped.")
    func mustExtendTyped() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveSure(
            ["svn commit", "git commit"], for: asked, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .certain("git commit"))
    }

    @Test("A model line that is the typed text in another case is not an extension, so it is dropped.")
    func theTypedLineInAnotherCaseIsNotADrawable() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "Meet a")
        let update = session.resolveSure(["meet a"], for: asked, elapsedMilliseconds: 0)
        #expect(update == .quiet(because: .nothingOffered))
    }

    @Test("When nothing the model returns can be shown, nothing is.")
    func nothingUsable() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveSure(["svn commit"], for: asked, elapsedMilliseconds: 0)
        #expect(update == .quiet(because: .nothingOffered))
    }

    @Test("An alternative that repeats the line, or the leader, in another case is not a second line.")
    func caseVariantsAreOneLine() throws {
        var session = SuggestionSession()
        let first = try asked(&session, typing: "git c")
        let update = session.resolveSure(
            ["git checkout", "Git Checkout", "git commit"], for: first, elapsedMilliseconds: 0)
        #expect(update?.suggestion == .choice(leader: "git checkout", others: ["git commit"]))
        var again = SuggestionSession()
        let lone = try asked(&again, typing: "git c")
        _ = again.resolveSure(["git checkout"], for: lone, elapsedMilliseconds: 0)
        #expect(again.expandSure(["GIT CHECKOUT", "Git Checkout"], for: lone) == nil)
        let expanded = again.expandSure(["Git Checkout", "git commit", "GIT COMMIT"], for: lone)
        #expect(expanded?.suggestion == .choice(leader: "git checkout", others: ["git commit"]))
    }

    @Test("A generation reached past the turn's budget is not drawn.")
    func pastBudget() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveSure(
            ["git checkout"], for: asked,
            elapsedMilliseconds: SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(update == .quiet(because: .overBudget))
    }
}

@Suite("Generated lines are scored before draw")
struct SuggestionScoringTests {
    /// The query one turn asks, or a failure saying it asked nothing.
    private func asked(
        _ session: inout SuggestionSession, typing typed: String
    ) throws
        -> SuggestionQuery
    {
        try query(session.turn(in: field, at: PredictionContext(typed: typed)))
    }

    @Test("A single generated line that scores below the certainty floor leaves the turn quiet.")
    func loneLowScoreIsQuiet() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "I think we should")
        let belowFloor = Verification.certainFloor - 1
        let update = session.resolveGenerated(
            ["I think we should meet at the north gate at noon"], for: asked,
            elapsedMilliseconds: 0, scores: ["I think we should meet at the north gate at noon": belowFloor])
        #expect(update == .quiet(because: .modelUnsure))
    }

    @Test("A single generated line that scores above the certainty floor is drawn as certain.")
    func loneHighScoreIsCertain() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let aboveFloor = Verification.certainFloor + 1
        let update = session.resolveGenerated(
            ["git commit -m"], for: asked, elapsedMilliseconds: 0,
            scores: ["git commit -m": aboveFloor])
        #expect(update?.suggestion == .certain("git commit -m"))
    }

    @Test("A low-scored leader is offered as a choice when an alternative clears the choice floor.")
    func leaderLowScoreFallsBackToChoice() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let belowCertain = (Verification.certainFloor + Verification.choiceFloor) / 2
        let aboveChoice = Verification.certainFloor
        let update = session.resolveGenerated(
            ["git checkout", "git commit"], for: asked, elapsedMilliseconds: 0,
            scores: [
                "git checkout": belowCertain,
                "git commit": aboveChoice,
            ])
        #expect(update?.suggestion == .choice(leader: "git checkout", others: ["git commit"]))
    }

    @Test("All lines below the choice floor leave the turn quiet.")
    func allLowScoreIsQuiet() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let belowFloor = Verification.choiceFloor - 1
        let update = session.resolveGenerated(
            ["git checkout", "git commit"], for: asked, elapsedMilliseconds: 0,
            scores: [
                "git checkout": belowFloor,
                "git commit": belowFloor,
            ])
        #expect(update == .quiet(because: .modelUnsure))
    }

    @Test("A leader below both floors and no alternatives clears them leaves the turn quiet.")
    func loneBelowChoiceFloorIsQuiet() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "I think we should")
        let belowFloor = Verification.choiceFloor - 1
        let update = session.resolveGenerated(
            ["I think we should meet at the north gate at noon"], for: asked,
            elapsedMilliseconds: 0, scores: ["I think we should meet at the north gate at noon": belowFloor])
        #expect(update == .quiet(because: .modelUnsure))
    }

    @Test("The line drawn alone clears a stricter floor than a line offered in a list.")
    func certainFloorIsStricter() {
        #expect(Verification.certainFloor > Verification.choiceFloor)
    }

    @Test("A line no pass scored is never drawn, alone or as a list's leader.")
    func unscoredLineIsNeverDrawn() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "I think we should")
        let lone = session.resolveGenerated(
            ["I think we should meet at the north gate at noon"], for: asked, elapsedMilliseconds: 0,
            scores: [:])
        #expect(lone == .quiet(because: .modelUnsure))
        let listed = session.resolveGenerated(
            ["I think we should wait", "I think we should go"], for: asked, elapsedMilliseconds: 0,
            scores: ["I think we should go": 0])
        #expect(listed == .quiet(because: .modelUnsure))
    }

    @Test("An alternative no pass scored is dropped, leaving a sure leader drawn alone.")
    func unscoredAlternativeIsDropped() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["git checkout", "git commit"], for: asked, elapsedMilliseconds: 0,
            scores: ["git checkout": Verification.certainFloor + 1])
        #expect(update?.suggestion == .certain("git checkout"))
    }

    @Test("A leader between the floors is quiet alone, since only a list may offer it.")
    func leaderBetweenFloorsAloneIsQuiet() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let between = (Verification.certainFloor + Verification.choiceFloor) / 2
        let update = session.resolveGenerated(
            ["git checkout"], for: asked, elapsedMilliseconds: 0, scores: ["git checkout": between])
        #expect(update == .quiet(because: .modelUnsure))
    }

    @Test("A line scored exactly at the certainty floor clears it.")
    func scoreAtFloorClears() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        let update = session.resolveGenerated(
            ["git checkout"], for: asked, elapsedMilliseconds: 0,
            scores: ["git checkout": Verification.certainFloor])
        #expect(update?.suggestion == .certain("git checkout"))
    }

    @Test("An unscored leader, from a missing or unloaded scorer, turns the turn silent.")
    func missingScorerKeepsTurnQuiet() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        // Scorer absent or held back (Low Power Mode, weights still loading): scoreCompletions returns [:] and no line is scored.
        let noneScored = session.resolveGenerated(
            ["git checkout"], for: asked, elapsedMilliseconds: 0, scores: [:])
        #expect(noneScored == .quiet(because: .modelUnsure))
        // A scorer that answered about other lines but missed the leader still does not pass it.
        let missedLeader = session.resolveGenerated(
            ["git checkout"], for: asked, elapsedMilliseconds: 0,
            scores: ["something else": 0])
        #expect(missedLeader == .quiet(because: .modelUnsure))
    }

    @Test(
        "A model's later alternatives need a score over the choice floor; the machine's listed values need none."
    )
    func expansionScoresModelLinesOnly() throws {
        var session = SuggestionSession()
        let asked = try asked(&session, typing: "git c")
        _ = session.resolveGenerated(
            ["git commit -m"], for: asked, elapsedMilliseconds: 0, scores: ["git commit -m": 0])
        #expect(session.expandGenerated(["git checkout main"], for: asked, scores: [:]) == nil)
        let low = ["git checkout main": Verification.choiceFloor - 1]
        #expect(session.expandGenerated(["git checkout main"], for: asked, scores: low) == nil)
        let listed = session.expandGenerated(["git checkout main"], for: asked, scores: nil)
        #expect(listed?.suggestion == .choice(leader: "git commit -m", others: ["git checkout main"]))
    }

    @Test(
        "A machine-listed line reused from a remembered answer draws, even though no pass scored it."
    )
    func reusedListedLineIsDrawn() throws {
        var session = SuggestionSession()
        let first = try asked(&session, typing: "git checkout ")
        // The model picked "main" from the branch list; the others arrived via expandGenerated.
        _ = session.resolveGenerated(
            ["git checkout main"], for: first, elapsedMilliseconds: 0,
            scores: ["git checkout main": 0])
        _ = session.expandGenerated(
            ["git checkout dev", "git checkout develop"], for: first, scores: nil)
        // Keystroke narrowed the line to "d"; only "dev" and "develop" prefix-match it; neither was scored, so the gate must let the listed ones through.
        let narrowed = try asked(&session, typing: "git checkout d")
        let update = session.resolveGenerated(
            ["git checkout dev", "git checkout develop"], for: narrowed,
            elapsedMilliseconds: 0, scores: [:],
            listed: ["git checkout dev", "git checkout develop"])
        #expect(
            update?.suggestion == .choice(
                leader: "git checkout dev", others: ["git checkout develop"]))
    }

    @Test("A reused machine-listed line alone draws as a certain ghost, no score needed.")
    func reusedListedAloneIsCertain() throws {
        var session = SuggestionSession()
        let first = try asked(&session, typing: "git checkout ")
        _ = session.resolveGenerated(
            ["git checkout main"], for: first, elapsedMilliseconds: 0,
            scores: ["git checkout main": 0])
        _ = session.expandGenerated(
            ["git checkout dev", "git checkout develop"], for: first, scores: nil)
        let narrowed = try asked(&session, typing: "git checkout dev")
        let update = session.resolveGenerated(
            ["git checkout develop"], for: narrowed, elapsedMilliseconds: 0, scores: [:],
            listed: ["git checkout develop"])
        #expect(update?.suggestion == .certain("git checkout develop"))
    }

    @Test(
        "A reused model-written line with no remembered score still goes quiet, per #2034."
    )
    func reusedModelLineWithoutScoreIsQuiet() throws {
        var session = SuggestionSession()
        let first = try asked(&session, typing: "git c")
        // The model wrote "git checkout" but it never produced a new score after typing narrowed the line.
        _ = session.resolveGenerated(
            ["git checkout"], for: first, elapsedMilliseconds: 0,
            scores: ["git checkout": 0])
        let narrowed = try asked(&session, typing: "git ch")
        let update = session.resolveGenerated(
            ["git checkout"], for: narrowed, elapsedMilliseconds: 0, scores: [:])
        #expect(update == .quiet(because: .modelUnsure))
    }
}

@Suite("Typing through a drawn ghost")
struct SuggestionTypeThroughTests {
    @Test("Five keys that each type the ghost's next letter keep it drawn, armed and takeable.")
    func typingTheGhostKeepsIt() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        for letter in ["o", "m", "m", "i", "t"] {
            let through = session.typedThrough(letter)
            let update = try #require(through)
            #expect(update.suggestion == .certain("git commit -m"))
            #expect(!update.armed.isEmpty)
            #expect(session.isCurrent)
        }
        #expect(session.typed == "git commit")
        #expect(session.route(KeyStroke(.tab)) == .accept("git commit -m"))
    }

    @Test("A key that is not the ghost's next letter leaves the ghost to be withdrawn.")
    func anotherKeyIsNotTypedThrough() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.typedThrough("x") == nil)
        #expect(session.typedThrough("O") == nil)
        #expect(session.typedThrough("") == nil)
        #expect(session.typed == "git c")
    }

    @Test("The key that finishes the ghost, or one past it, is not typed through.")
    func finishingTheGhostIsNotTypedThrough() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git commit -")
        #expect(session.typedThrough("m") == nil)
        #expect(session.typedThrough("-m ") == nil)
    }

    @Test(
        "An answer worked out before a typed-through key is dropped, and one after a stale read is refused.")
    func anAnswerInFlightIsDropped() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.typedThrough("o")
        #expect(session.resolve(lone(), for: asked, now: moment, elapsedMilliseconds: 0) == nil)
        session.keystrokeArrived()
        #expect(session.typedThrough("m") == nil)
    }

    @Test(
        "A list keeps only the lines the typing still leads to, and a moved highlight is never typed through."
    )
    func aListFollowsTheTyping() throws {
        var session = SuggestionSession()
        let asked = try query(session.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = session.resolveSure(
            ["git commit -m", "git checkout", "git cherry-pick"], for: asked, elapsedMilliseconds: 0)
        let through = session.typedThrough("o")
        #expect(through?.suggestion == .certain("git commit -m"))

        var moved = SuggestionSession()
        let again = try query(moved.turn(in: field, at: PredictionContext(typed: "git c")))
        _ = moved.resolveSure(["git commit -m", "git checkout"], for: again, elapsedMilliseconds: 0)
        _ = moved.route(KeyStroke(.downArrow, modifiers: .option))
        #expect(moved.typedThrough("o") == nil)
    }
}
