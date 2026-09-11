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

    /// The repairs `Docs/cleanup.md` says the formatter makes — a tense that drifts, agreement — change a word's form.
    @Test(
        "accepts the grammar repairs the tidier is asked for",
        arguments: [
            ("yesterday i try to fix the build", "Yesterday I tried to fix the build."),
            ("we apply the patch last week", "We applied the patch last week."),
            ("she carry the box upstairs", "She carried the box upstairs."),
            ("i study the logs all morning", "I studied the logs all morning."),
            ("three city are on the list", "Three cities are on the list."),
            ("he go to the standup", "He goes to the standup."),
            ("i was take notes", "I was taking notes."),
            ("they was use the old build", "They were using the old build."),
        ]
    )
    func acceptsAFormRepair(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
    }

    /// A y-stem or a dropped "e" is a spelling change English makes before an ending, not a different word.
    @Test("reads a form written over a stem, and still refuses a word that only shares one")
    func readsAStemmedForm() {
        #expect(MeaningPreservationGuard.survives("try", in: ["tried"]))
        #expect(MeaningPreservationGuard.survives("happy", in: ["happier"]))
        #expect(MeaningPreservationGuard.survives("cities", in: ["city"]))
        #expect(MeaningPreservationGuard.survives("take", in: ["taking"]))
        #expect(!MeaningPreservationGuard.survives("mad", in: ["made"]))
        #expect(!MeaningPreservationGuard.survives("depot", in: ["deposit"]))
        #expect(!MeaningPreservationGuard.survives("many", in: ["management"]))
        #expect(!MeaningPreservationGuard.survives("one", in: ["on"]))
    }

    /// Three letters is what `GeneralVocabulary` calls a word — "SQL or API" — so an identifier must not swallow one.
    @Test("sees a three-letter word spelled into an identifier the model wrote")
    func seesAShortWordInAnIdentifier() {
        #expect(MeaningPreservationGuard.identifierParts(of: "fetchURL") == ["fetch", "url"])
        #expect(MeaningPreservationGuard.identifierParts(of: "new_tab") == ["new", "tab"])
        #expect(MeaningPreservationGuard.identifierParts(of: "downtown").isEmpty)
        #expect(MeaningPreservationGuard.identifierParts(of: "don't").isEmpty)
    }

    @Test(
        "accepts a rewrite that spelled a short word into an identifier",
        arguments: [
            ("the fetch url is wrong", "The fetchURL is wrong."),
            ("call api after the retry", "callAPI after the retry."),
            ("open a new tab first", "Open a newTab first."),
        ]
    )
    func acceptsAShortWordInAnIdentifier(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
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
