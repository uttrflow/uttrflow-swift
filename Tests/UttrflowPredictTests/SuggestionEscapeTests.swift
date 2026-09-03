import Foundation
import Testing

@testable import UttrflowPredict

private let noon = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("The escape ladder")
struct SuggestionEscapeLadderTests {
    @Test("The first press is about this suggestion and nothing else.")
    func theFirstPressDismisses() {
        var ladder = SuggestionEscapeLadder()
        #expect(ladder.escape() == .dismissSuggestion)
        #expect(!ladder.isFieldSilenced)
    }

    @Test("Each further press means one rung more, in the order the ladder is written.")
    func climbsOneRungPerPress() {
        var ladder = SuggestionEscapeLadder()
        #expect(ladder.escape() == .dismissSuggestion)
        #expect(ladder.escape() == .silenceField)
        #expect(ladder.escape() == .turnOffApplication)
        #expect(ladder.escape() == .pauseEverywhere)
        #expect(ladder.escape() == .offEverywhere)
    }

    @Test("Stays at the top rung however many more times Escape is pressed.")
    func stopsAtTheTop() {
        var ladder = SuggestionEscapeLadder()
        for _ in 0..<5 { ladder.escape() }
        #expect(ladder.escape() == .offEverywhere)
        #expect(ladder.escape() == .offEverywhere)
        #expect(ladder.reached == .offEverywhere)
    }

    @Test("Silences the field from the second press onwards, and not before it.")
    func silencesTheFieldOnTheSecondPress() {
        var ladder = SuggestionEscapeLadder()
        ladder.escape()
        #expect(!ladder.isFieldSilenced)
        ladder.escape()
        #expect(ladder.isFieldSilenced)
    }

    @Test("Gives a field its voice back when the caret leaves it and comes back.")
    func focusChangeClearsEverything() {
        var ladder = SuggestionEscapeLadder()
        ladder.escape()
        ladder.escape()
        ladder.focusChanged()
        #expect(!ladder.isFieldSilenced)
        #expect(ladder.reached == nil)
        #expect(ladder.escape() == .dismissSuggestion)
    }

    @Test("Starts the climb again once a suggestion has been taken.")
    func acceptingStartsTheClimbAgain() {
        var ladder = SuggestionEscapeLadder()
        ladder.escape()
        ladder.accepted()
        #expect(ladder.reached == nil)
        #expect(ladder.escape() == .dismissSuggestion)
    }

    @Test("Says which rungs change something that outlives the field they were pressed in.")
    func saysWhichRungsOutliveTheField() {
        #expect(!SuggestionEscape.dismissSuggestion.outlivesTheField)
        #expect(!SuggestionEscape.silenceField.outlivesTheField)
        #expect(SuggestionEscape.turnOffApplication.outlivesTheField)
        #expect(SuggestionEscape.pauseEverywhere.outlivesTheField)
        #expect(SuggestionEscape.offEverywhere.outlivesTheField)
    }

    @Test("Is ordered, so a rung reached later is a rung further up.")
    func isOrdered() {
        #expect(SuggestionEscape.allCases == SuggestionEscape.allCases.sorted())
        #expect(SuggestionEscape.dismissSuggestion < SuggestionEscape.offEverywhere)
    }
}

@Suite("What a rung of the ladder changes")
struct SuggestionEscapeOutcomeTests {
    private let on = SuggestionPreferences(isEnabled: true)

    @Test("Dismissing and silencing change nothing that outlives the field.")
    func theFirstTwoRungsChangeNothing() {
        for rung in [SuggestionEscape.dismissSuggestion, .silenceField] {
            let after = SuggestionEscapeLadder.carriedOut(
                rung, in: "com.apple.Notes", to: on, at: noon)
            #expect(after == on)
        }
    }

    @Test("The third rung switches this application off and leaves every other one alone.")
    func theThirdRungTurnsOffOneApplication() {
        let after = SuggestionEscapeLadder.carriedOut(
            .turnOffApplication, in: "com.apple.Notes", to: on, at: noon)
        #expect(after.state(of: "com.apple.Notes") == .turnedOff)
        #expect(after.state(of: "com.apple.Mail") == .on)
        #expect(after.isEnabled)
    }

    @Test("The fourth rung pauses everywhere for half an hour and leaves the feature on.")
    func theFourthRungPauses() {
        let after = SuggestionEscapeLadder.carriedOut(
            .pauseEverywhere, in: "com.apple.Notes", to: on, at: noon)
        #expect(after.isEnabled)
        #expect(after.isPaused(at: noon))
        #expect(!after.isPaused(at: noon.addingTimeInterval(SuggestionPreferences.pause)))
    }

    @Test("The fifth rung switches the feature off and touches no application's own answer.")
    func theFifthRungTurnsEverythingOff() {
        var before = on
        before.set("com.apple.Notes", isOn: true)
        let after = SuggestionEscapeLadder.carriedOut(
            .offEverywhere, in: "com.apple.Notes", to: before, at: noon)
        #expect(!after.isEnabled)
        #expect(after.turnedOn == before.turnedOn)
        #expect(after.turnedOff == before.turnedOff)
    }
}
