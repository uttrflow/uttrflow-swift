import Testing

@testable import UttrflowPredict

@Suite("Recovering a failed suggestion acceptance")
struct SuggestionAcceptanceRollbackTests {
    @Test("A failed take restores the offer so the next turn can offer it again.")
    func failedTakeCanBeOfferedAgain() throws {
        var session = SuggestionSession()
        let offer = try #require(try draw(&session, typing: "git c", in: terminal))
        #expect(offer.suggestion == .certain("git commit -m"))
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))

        session.completeAcceptance(.refused)

        #expect(session.typed == "git c")
        #expect(session.suggestion == .certain("git commit -m"))
        let nextTurn = try #require(try draw(&session, typing: "git c", in: terminal))
        #expect(nextTurn.suggestion == .certain("git commit -m"))
    }

    @Test("A same-line read before the refusal does not leave the failed take marked undone.")
    func failedTakeReadBeforeResultCanBeOfferedAgain() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        _ = try draw(&session, typing: "git c", in: terminal)

        session.completeAcceptance(.refused)

        #expect(session.undoneHere.isEmpty)
        #expect(session.typed == "git c")
        let nextTurn = try #require(try draw(&session, typing: "git c", in: terminal))
        #expect(nextTurn.suggestion == .certain("git commit -m"))
    }

    @Test("A same-line reread keeps its newer offer when the earlier take is refused.")
    func refusedTakePreservesNewerSameLineOffer() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c")
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))

        let newerOffer = try #require(
            try draw(&session, typing: "git c", candidates: [remembered("git checkout", count: 40)]))
        #expect(newerOffer.suggestion == .certain("git checkout"))

        session.completeAcceptance(.refused)

        #expect(session.typed == "git c")
        #expect(session.suggestion == .certain("git checkout"))
    }

    @Test("A later quiet same-line turn stays quiet when an earlier refusal arrives.")
    func refusedTakeDoesNotRestoreAnOfferAfterQuietingTurn() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        _ = session.turn(
            in: terminal, at: PredictionContext(typed: "git c", isSecure: true))

        session.completeAcceptance(.refused)

        #expect(session.suggestion == .silent)
        #expect(session.undoneHere.isEmpty)
        #expect(session.taken == nil)
    }

    @Test("A no-focus turn clears same-line rollback eligibility.")
    func refusedTakeDoesNotRestoreAnOfferAfterNoFocusTurn() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git c"))
        _ = session.turn(in: nil, at: PredictionContext(typed: "git c"))

        session.completeAcceptance(.refused)

        #expect(session.suggestion == .silent)
        #expect(session.undoneHere.isEmpty)
        #expect(session.taken == nil)
    }

    @Test("A key during a refused take keeps the new keystroke but clears its false undo mark.")
    func refusedTakeAfterKeystrokeDoesNotMarkOfferUndone() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        session.keystrokeArrived()
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git c"))

        session.completeAcceptance(.refused)

        #expect(session.keystrokes == 1)
        #expect(session.typed == "git c")
        #expect(session.suggestion == .silent)
        #expect(session.undoneHere.isEmpty)
    }

    @Test("A changed-line turn after refusal preserves the line and removes its false undo mark.")
    func refusedTakeAfterChangedLineDoesNotMarkOfferUndone() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git co"))

        session.completeAcceptance(.refused)

        #expect(session.typed == "git co")
        #expect(session.suggestion == .silent)
        #expect(session.undoneHere.isEmpty)
    }

    @Test("A stale refusal preserves a newer undo mark for the same accepted line.")
    func staleRefusalPreservesNewerSameLineUndoMark() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        let oldAcceptance = try #require(session.failedAcceptance)
        let newerGeneration = oldAcceptance.acceptanceGeneration + 1
        session.keystrokeArrived()
        session.taken = TakenLine(
            line: oldAcceptance.acceptedText, over: oldAcceptance.typed,
            moment: moment.addingTimeInterval(2), acceptanceGeneration: newerGeneration)
        // The field echoes the newer take back, which is what lets a shorter read mark it undone.
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git commit -m"))
        _ = session.turn(in: terminal, at: PredictionContext(typed: "git c"))

        session.completeAcceptance(.refused)

        let key = "git commit -m"
        #expect(session.undoneHere == [key])
        #expect(session.undoMarkGenerations[key] == newerGeneration)
        #expect(session.typed == "git c")
    }

    @Test("A refusal after a newer field adopts does not change that field's undo history.")
    func refusedTakeAfterFieldChangePreservesUndoHistory() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))
        let otherField = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/docs")
        _ = session.turn(in: otherField, at: PredictionContext(typed: "git c"))
        session.undoneHere = ["a newer field's undo mark"]

        session.completeAcceptance(.refused)

        #expect(session.undoneHere == ["a newer field's undo mark"])
        #expect(session.surface == otherField)
    }

    @Test("An uncertain insertion keeps the speculative acceptance.")
    func uncertainTakeIsNotRolledBack() throws {
        var session = SuggestionSession()
        _ = try draw(&session, typing: "git c", in: terminal)
        #expect(session.route(KeyStroke(.tab), at: moment) == .accept("git commit -m"))

        session.completeAcceptance(.mayHaveWritten)

        #expect(session.typed == "git commit -m")
        #expect(session.suggestion == .silent)
    }
}
