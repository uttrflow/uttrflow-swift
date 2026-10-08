// Tests that homophone repair and harm are read from the word at the slot, per decider tag.
import Testing
import UttrflowEval

@Suite("HomophoneRepairRates")
struct HomophoneRepairRatesTests {
    static let carrier = HomophoneCarrier("their", .role, "they parked _ car outside")
    static let theCase = HomophoneCaseSet.cases(
        classes: [["their", "there", "they're"]], carriers: [carrier])[0]

    @Test func aRepairIsTheMeantSpellingAtTheSlotDespiteCapitalsAndMarks() {
        let outcome = HomophoneOutcome(
            Self.theCase, fromInput: "They parked their car outside.",
            fromExpected: "they parked their car outside")
        #expect(outcome.repaired)
        #expect(!outcome.harmed)
    }

    @Test func leavingTheWrongSpellingIsNoRepair() {
        let outcome = HomophoneOutcome(
            Self.theCase, fromInput: Self.theCase.input, fromExpected: Self.theCase.expected)
        #expect(!outcome.repaired)
        #expect(!outcome.harmed)
    }

    @Test func changingTheMeantSpellingIsHarm() {
        let outcome = HomophoneOutcome(
            Self.theCase, fromInput: Self.theCase.input, fromExpected: Self.theCase.input)
        #expect(outcome.harmed)
    }

    @Test func aChangedWordCountNeedsTheWholeSentence() {
        let dropped = HomophoneOutcome(
            Self.theCase, fromInput: "they parked their car", fromExpected: "they parked their car")
        #expect(!dropped.repaired)
        #expect(dropped.harmed)
    }

    @Test func rowsCoverEveryTagAndCountOnlyTheirOwnCases() {
        let rows = HomophoneRepairRates.rows([
            HomophoneOutcome(Self.theCase, fromInput: Self.theCase.expected, fromExpected: Self.theCase.input)
        ])
        #expect(rows.map(\.decider) == HomophoneDecider.allCases)
        let role = rows[0]
        #expect(role.cases == 1 && role.repairRate == 1 && role.harmRate == 1)
        #expect(rows.dropFirst().allSatisfy { $0.cases == 0 && $0.repairRate == 0 && $0.harmRate == 0 })
    }
}
