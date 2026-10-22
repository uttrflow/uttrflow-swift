import Testing

@testable import UttrflowAI

/// A spoken "out of" is words the speaker said, so a tidier may not turn it into a slash.
@Suite("The guard on a spoken score")
struct GuardSpokenScoreTests {
    @Test("a score said as out of is not written as a fraction")
    func outOfStaysWords() {
        for (original, rewritten) in [
            ("She gave it a 9 out of 10.", "She gave it a 9/10."),
            ("He scored a 7 out of 10 on the test.", "He scored a 7/10 on the test."),
        ] {
            let verdict = MeaningPreservationGuard.symbolVerdict(original: original, rewritten: rewritten)
            #expect(!verdict.isAccepted, "\(rewritten)")
        }
    }

    @Test("a fraction the speaker wrote or a score kept in words is accepted")
    func keptFormsPass() {
        let guardCheck = MeaningPreservationGuard.symbolVerdict
        #expect(guardCheck("She gave it a 9 out of 10.", "She gave it a 9 out of 10.").isAccepted)
        #expect(guardCheck("It scored 3/5 and 4 out of 5.", "It scored 3/5 and 4 out of 5.").isAccepted)
    }
}
