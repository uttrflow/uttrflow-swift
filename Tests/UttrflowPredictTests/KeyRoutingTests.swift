import Testing

@testable import UttrflowPredict

/// The two shapes every rule below is exercised against.
private let one = Suggestion.certain("git commit")
private let several = Suggestion.choice(leader: "git commit", others: ["git checkout", "git clone"])

private func decide(
    _ stroke: KeyStroke, showing suggestion: Suggestion,
    selection: SuggestionSelection = .untouched, acceptKey: AcceptKey = .tab
) -> KeyDecision {
    KeyRouting.decision(
        for: stroke, showing: suggestion, selection: selection, acceptKey: acceptKey)
}

@Suite("Nothing is drawn, so nothing is ours")
struct SilentKeyRoutingTests {
    @Test(
        "Every keystroke reaches the application untouched.",
        arguments: ArmedKeys.slots.map(\.stroke))
    func everythingPassesThrough(stroke: KeyStroke) {
        #expect(decide(stroke, showing: .silent) == .passThrough)
    }

    @Test("Escape closes the application's own dialog rather than minimising nothing.")
    func escapeIsNotOurs() {
        #expect(decide(KeyStroke(.escape), showing: .silent) == .passThrough)
        #expect(decide(KeyStroke(.escape, modifiers: .option), showing: .silent) == .passThrough)
    }

    @Test("Nothing is armed, so the tap takes nothing at all.")
    func nothingIsArmed() {
        #expect(KeyRouting.arming(showing: .silent).isEmpty)
    }
}

@Suite("Accepting the suggestion on screen")
struct AcceptKeyRoutingTests {
    @Test("Tab takes the suggestion when one is drawn.")
    func tabAccepts() {
        #expect(decide(KeyStroke(.tab), showing: one) == .accept("git commit"))
    }

    @Test("In a terminal the right arrow accepts and Tab is left to the shell.")
    func terminalUsesTheRightArrow() {
        #expect(
            decide(KeyStroke(.rightArrow), showing: one, acceptKey: .rightArrow)
                == .accept("git commit"))
        #expect(decide(KeyStroke(.tab), showing: one, acceptKey: .rightArrow) == .passThrough)
    }

    @Test("In an editor Option-Tab accepts and a bare Tab still indents.")
    func editorUsesOptionTab() {
        #expect(
            decide(KeyStroke(.tab, modifiers: .option), showing: one, acceptKey: .optionTab)
                == .accept("git commit"))
        #expect(decide(KeyStroke(.tab), showing: one, acceptKey: .optionTab) == .passThrough)
    }

    @Test("The right arrow is the caret's own key everywhere it does not accept.")
    func rightArrowIsNotOursByDefault() {
        #expect(decide(KeyStroke(.rightArrow), showing: several) == .passThrough)
    }

    @Test("Shift-Tab is the application's back-tab and is never taken.")
    func backTabPassesThrough() {
        #expect(decide(KeyStroke(.tab, modifiers: .shift), showing: one) == .passThrough)
    }

    @Test("A Tab carrying Command is a window shortcut and is never taken.")
    func commandTabPassesThrough() {
        #expect(decide(KeyStroke(.tab, modifiers: .command), showing: one) == .passThrough)
    }

    @Test("Accepting takes the highlighted line rather than always the leader.")
    func acceptsWhatIsHighlighted() {
        let moved = SuggestionSelection(index: 2, hasMoved: true)
        #expect(decide(KeyStroke(.tab), showing: several, selection: moved) == .accept("git clone"))
    }

    @Test("A highlight past the end of the list is brought back to the last line.")
    func selectionIsClamped() {
        let past = SuggestionSelection(index: 9, hasMoved: true)
        #expect(decide(KeyStroke(.tab), showing: several, selection: past) == .accept("git clone"))
    }

    @Test("A highlight before the start of the list is brought back to the leader.")
    func negativeSelectionIsClamped() {
        let before = SuggestionSelection(index: -3, hasMoved: true)
        #expect(decide(KeyStroke(.tab), showing: several, selection: before) == .accept("git commit"))
    }
}

@Suite("Return, which is the key that must not be stolen")
struct ReturnKeyRoutingTests {
    @Test("Before the list is touched it runs the command and sends the message, as always.")
    func passesThroughUntouched() {
        #expect(decide(KeyStroke(.return), showing: several) == .passThrough)
        #expect(decide(KeyStroke(.return), showing: one) == .passThrough)
    }

    @Test("Once Down has moved the highlight it takes the highlighted line.")
    func acceptsAfterTheListIsWalked() {
        let moved = SuggestionSelection(index: 1, hasMoved: true)
        #expect(decide(KeyStroke(.return), showing: several, selection: moved) == .accept("git checkout"))
    }

    @Test("A single suggestion is not a list, so Return stays the application's even when moved.")
    func aLoneSuggestionNeverClaimsReturn() {
        let moved = SuggestionSelection(index: 0, hasMoved: true)
        #expect(decide(KeyStroke(.return), showing: one, selection: moved) == .passThrough)
    }

    @Test("Shift-Return is a new line in a chat box and is never taken.")
    func shiftReturnPassesThrough() {
        let moved = SuggestionSelection(index: 1, hasMoved: true)
        #expect(
            decide(KeyStroke(.return, modifiers: .shift), showing: several, selection: moved)
                == .passThrough)
    }

    @Test("The keypad's Enter is the same key and follows the same rule.")
    func keypadEnterFollowsTheSameRule() {
        #expect(decide(KeyStroke(keyCode: 76), showing: several) == .passThrough)
        let moved = SuggestionSelection(index: 1, hasMoved: true)
        #expect(
            decide(KeyStroke(keyCode: 76), showing: several, selection: moved)
                == .accept("git checkout"))
    }

    @Test("It is armed only once the highlight has moved, so the tap cannot take it early.")
    func armedOnlyAfterMoving() {
        #expect(!KeyRouting.arming(showing: several).contains(.return))
        let moved = SuggestionSelection(index: 1, hasMoved: true)
        #expect(KeyRouting.arming(showing: several, selection: moved).contains(.return))
    }
}

@Suite("Walking the list")
struct SelectionKeyRoutingTests {
    @Test("Down moves to the next line and records that the user moved it.")
    func downMoves() {
        #expect(
            decide(KeyStroke(.downArrow), showing: several)
                == .moveSelection(SuggestionSelection(index: 1, hasMoved: true)))
    }

    @Test("Down from the last line comes back to the leader rather than doing nothing.")
    func downWraps() {
        let last = SuggestionSelection(index: 2, hasMoved: true)
        #expect(
            decide(KeyStroke(.downArrow), showing: several, selection: last)
                == .moveSelection(SuggestionSelection(index: 0, hasMoved: true)))
    }

    @Test("Up before anything has been walked is the shell's history and is left alone.")
    func upIsNotOursUntilTheListIsWalked() {
        #expect(decide(KeyStroke(.upArrow), showing: several) == .passThrough)
        #expect(!KeyRouting.arming(showing: several).contains(.upArrow))
    }

    @Test("Up after Down moves back a line.")
    func upMovesBack() {
        let moved = SuggestionSelection(index: 2, hasMoved: true)
        #expect(
            decide(KeyStroke(.upArrow), showing: several, selection: moved)
                == .moveSelection(SuggestionSelection(index: 1, hasMoved: true)))
    }

    @Test("Up from the leader wraps to the last line.")
    func upWraps() {
        let moved = SuggestionSelection(index: 0, hasMoved: true)
        #expect(
            decide(KeyStroke(.upArrow), showing: several, selection: moved)
                == .moveSelection(SuggestionSelection(index: 2, hasMoved: true)))
    }

    @Test("A single suggestion has nothing to walk, so both arrows are left alone.")
    func aLoneSuggestionIsNotWalkable() {
        #expect(decide(KeyStroke(.downArrow), showing: one) == .passThrough)
        let moved = SuggestionSelection(index: 0, hasMoved: true)
        #expect(decide(KeyStroke(.upArrow), showing: one, selection: moved) == .passThrough)
    }

    @Test("An arrow carrying a modifier moves by word or to the end, which is the application's job.")
    func modifiedArrowsPassThrough() {
        #expect(decide(KeyStroke(.downArrow, modifiers: .command), showing: several) == .passThrough)
    }

    @Test("Nothing has been walked to start with.")
    func untouchedIsTheStartingPoint() {
        #expect(SuggestionSelection.untouched == SuggestionSelection(index: 0, hasMoved: false))
    }
}

@Suite("The escape ladder")
struct DismissKeyRoutingTests {
    @Test("Escape minimises what is on screen.")
    func escapeMinimises() {
        #expect(decide(KeyStroke(.escape), showing: one) == .dismiss(.minimise))
        #expect(decide(KeyStroke(.escape), showing: several) == .dismiss(.minimise))
    }

    @Test("Escape again, with only the dot left, silences the field.")
    func escapeTwiceSilencesTheField() {
        #expect(decide(KeyStroke(.escape), showing: .minimised) == .dismiss(.silenceField))
    }

    @Test("Option-Escape turns the whole feature off, from either rung.")
    func optionEscapeTurnsItOff() {
        let stroke = KeyStroke(.escape, modifiers: .option)
        #expect(decide(stroke, showing: one) == .dismiss(.turnOff))
        #expect(decide(stroke, showing: several) == .dismiss(.turnOff))
        #expect(decide(stroke, showing: .minimised) == .dismiss(.turnOff))
    }

    @Test("An escape carrying anything else is the application's own.")
    func otherEscapesPassThrough() {
        #expect(decide(KeyStroke(.escape, modifiers: .command), showing: one) == .passThrough)
        #expect(
            decide(KeyStroke(.escape, modifiers: .shift), showing: .minimised) == .passThrough)
    }

    @Test("With only the dot left there is nothing to accept or walk.")
    func minimisedClaimsOnlyEscape() {
        #expect(decide(KeyStroke(.tab), showing: .minimised) == .passThrough)
        #expect(decide(KeyStroke(.downArrow), showing: .minimised) == .passThrough)
        #expect(decide(KeyStroke(.return), showing: .minimised) == .passThrough)
        #expect(KeyRouting.arming(showing: .minimised) == [.escape, .optionEscape])
    }
}

@Suite("What the tap is armed with")
struct ArmingTests {
    @Test("One suggestion claims its accept key and the escape ladder, and nothing else.")
    func aLoneSuggestion() {
        #expect(KeyRouting.arming(showing: one) == [.tab, .escape, .optionEscape])
    }

    @Test("A list additionally claims Down, which is what opens it.")
    func aList() {
        #expect(KeyRouting.arming(showing: several) == [.tab, .downArrow, .escape, .optionEscape])
    }

    @Test("Walking the list claims Up and Return as well.")
    func aWalkedList() {
        let moved = SuggestionSelection(index: 1, hasMoved: true)
        #expect(
            KeyRouting.arming(showing: several, selection: moved)
                == [.tab, .downArrow, .upArrow, .return, .escape, .optionEscape])
    }

    @Test("The accept key that is armed is the one the application uses.")
    func armingFollowsTheAcceptKey() {
        #expect(KeyRouting.arming(showing: one, acceptKey: .rightArrow).contains(.rightArrow))
        #expect(!KeyRouting.arming(showing: one, acceptKey: .rightArrow).contains(.tab))
        #expect(KeyRouting.arming(showing: one, acceptKey: .optionTab).contains(.optionTab))
        #expect(!KeyRouting.arming(showing: one, acceptKey: .optionTab).contains(.tab))
    }

    /// A slot armed without a rule behind it is a keystroke the user silently loses.
    @Test(
        "A slot is armed exactly when the rules claim its keystroke.",
        arguments: [Suggestion.silent, .minimised, one, several],
        [SuggestionSelection.untouched, SuggestionSelection(index: 1, hasMoved: true)])
    func armingAgreesWithTheRules(suggestion: Suggestion, selection: SuggestionSelection) {
        for key in AcceptKey.allCases {
            let armed = KeyRouting.arming(
                showing: suggestion, selection: selection, acceptKey: key)
            for entry in ArmedKeys.slots {
                let claimed =
                    decide(entry.stroke, showing: suggestion, selection: selection, acceptKey: key)
                    != .passThrough
                #expect(armed.contains(entry.slot) == claimed, "\(entry.stroke) under \(key)")
            }
        }
    }
}
