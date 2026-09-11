import Testing
import UttrflowCore

@testable import UttrflowAI

/// Regression for issue 217 inside the guard: a lossy match is no longer the whole of what `survives` asks.
@Suite("Issue 217 sweep: a content word does not survive on three shared letters")
struct Issue217GuardSweepTests {
    @Test(
        "refuses a rewrite that swapped a content word for one that merely opens like it",
        arguments: [
            ("send the contract to the team", "Send the contact to the team."),
            ("check the deposit today", "Check the depot today."),
            ("the management said no", "The many said no."),
        ]
    )
    func refusesANearMiss(kept: String, rewritten: String) {
        #expect(!MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
    }

    @Test("a word is not read out of the middle of an unrelated one")
    func doesNotReadAWordOutOfAnother() {
        #expect(!MeaningPreservationGuard.survives("contract", in: ["contact"]))
        #expect(!MeaningPreservationGuard.survives("own", in: ["downtown"]))
        #expect(!MeaningPreservationGuard.survives("art", in: ["start"]))
    }

    /// What the loosened rules were written for still has to hold, or the guard refuses good rewrites.
    @Test("still sees a word spelled into an identifier, and a form of the same word")
    func keepsWhatTheRuleWasFor() {
        #expect(MeaningPreservationGuard.survives("invoices", in: ["fetchinvoices"]))
        #expect(MeaningPreservationGuard.survives("developer", in: ["developers"]))
        #expect(MeaningPreservationGuard.survives("running", in: ["run"]))
    }

    @Test("the whole guard refuses a rewrite that swapped a content word")
    func wholeGuardRefuses() {
        let verdict = MeaningPreservationGuard().verdict(
            draft: Draft.heard("send the contract to the team"),
            rewritten: "Send the contact to the team.")
        #expect(verdict == .rejected(reason: "the rewrite lost or replaced 'contract'"))
    }

    @Test("a reading has to be written where a word starts, not found inside one")
    func readingsStartWhereAWordStarts() {
        let span = DoubtfulSpan(heard: "in it", confidence: 0.3, candidates: ["init"])
        #expect(
            !MeaningPreservationGuard.candidateVerdict([span], rewritten: "Let me begin it tomorrow.")
                .isAccepted)

        let amount = DoubtfulSpan(heard: "a mount", confidence: 0.3, candidates: ["amount"])
        #expect(
            MeaningPreservationGuard.candidateVerdict([amount], rewritten: "The amount is fine.")
                .isAccepted)
    }
}
