import Testing

@testable import UttrflowAI
import UttrflowCore

/// `MeaningPreservationGuard` reads spoken numbers through `UttrflowCore.NumberWords`, scales composed.
@Suite("GuardNumberWords")
struct GuardNumberWordsTests {
    /// With the numbers step switched off the draft keeps "six hundred", and the guard still reads it as 600.
    @Test("a composed number survives the guard when the numbers step is off")
    func composedNumberWithTheNumbersStepOff() {
        let draft = CleaningPipeline.beforeModel(steps: CleaningSteps(switchedOff: [.numberForms]))
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
}
