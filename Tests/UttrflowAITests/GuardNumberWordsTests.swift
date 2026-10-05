import Testing

@testable import UttrflowAI
import UttrflowCore

/// `MeaningPreservationGuard` reads spoken numbers through `UttrflowCore.NumberWords`, scales composed.
@Suite("GuardNumberWords")
struct GuardNumberWordsTests {
    /// With the numbers step switched off the draft keeps "six hundred", and the guard still reads it as 600.
    @Test("a composed number survives the guard when the numbers step is off")
    func composedNumberWithTheNumbersStepOff() {
        let draft = CleaningPipeline.beforeModel(
            for: .standard(for: .plain), situation: .unknown,
            steps: CleaningSteps(switchedOff: [.numberForms])
        )
        .run(Draft(text: "we raised six hundred rupees")).text
        #expect(draft == "we raised six hundred rupees")
        let verdict = MeaningPreservationGuard()
            .verdict(original: draft, rewritten: "We raised 600 rupees.")
        #expect(verdict == .accepted)
    }

    /// Every scale the core table composes is a number the guard accepts the numeral for.
    @Test("the guard reads every scale the core table composes")
    func everyScaleTheCoreTableComposes() {
        let guardUnderTest = MeaningPreservationGuard()
        #expect(
            guardUnderTest.verdict(
                original: "we sold two million units", rewritten: "We sold 2,000,000 units.") == .accepted)
        #expect(
            guardUnderTest.verdict(
                original: "we raised three thousand rupees", rewritten: "We raised 3,000 rupees.")
                == .accepted)
    }

    /// Every word the guard reads as a number comes from `NumberWords`, so a key added only here fails.
    @Test("the guard's number words are exactly NumberWords, English and Hindi")
    func numberWordsHaveOneHome() {
        let expected = NumberWords.english.merging(NumberWords.hindi) { first, _ in first }.mapValues(
            String.init)
        #expect(MeaningPreservationGuard.numberWords == expected)
    }

    /// A model that turns a relative clock phrase into a clock time states a number nobody said, and is refused.
    @Test(
        "a relative clock phrase rewritten as a clock time is refused",
        arguments: [
            ("meet at half past two", "Meet at 2:30."),
            ("leave at quarter to six", "Leave at 5:45."),
            ("it is twenty past four", "It is 4:20."),
        ]
    )
    func relativeClockPhraseAsClockTime(original: String, rewritten: String) {
        #expect(MeaningPreservationGuard().verdict(original: original, rewritten: rewritten) != .accepted)
    }

    /// The scales above a thousand are the only words the guard gained when its own table went.
    @Test("a million spoken and a million written are the same number to the guard")
    func millionIsANumber() {
        #expect(MeaningPreservationGuard.numberWords["million"] == "1000000")
        #expect(
            MeaningPreservationGuard.inventedNumber(
                original: "one million rows", rewritten: "one million rows") == nil)
    }
}
