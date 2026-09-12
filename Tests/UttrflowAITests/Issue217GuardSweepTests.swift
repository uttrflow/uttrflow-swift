import Testing
import UttrflowCore

@testable import UttrflowAI

/// Regression for issue 217 inside the guard: a lossy match is no longer the whole of what `survives` asks.
@Suite("Issue 217 sweep: a content word does not survive on three shared letters")
struct Issue217GuardSweepTests {
    private func survives(_ word: String, as candidate: String) -> Bool {
        MeaningPreservationGuard.grammarTokens(candidate)
            .contains { MeaningPreservationGuard.survives(word, as: $0) }
    }

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
        #expect(!survives("contract", as: "contact"))
        #expect(!survives("own", as: "downtown"))
        #expect(!survives("art", as: "start"))
    }

    /// What the loosened rules were written for still has to hold, or the guard refuses good rewrites.
    @Test("still sees a word spelled into an identifier, and a form of the same word")
    func keepsWhatTheRuleWasFor() {
        #expect(survives("invoices", as: "fetchInvoices"))
        #expect(survives("developer", as: "developers"))
        #expect(survives("running", as: "run"))
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
        #expect(survives("try", as: "tried"))
        #expect(survives("happy", as: "happier"))
        #expect(survives("cities", as: "city"))
        #expect(survives("take", as: "taking"))
        #expect(!survives("mad", as: "made"))
        #expect(!survives("depot", as: "deposit"))
        #expect(!survives("many", as: "management"))
        #expect(!survives("one", as: "on"))
    }

    /// The listed forms reach only the words listed, so a short word whose ending would make another word is still refused.
    @Test("refuses an unlisted short word whose ending makes another word")
    func listedFormsStayNarrow() {
        #expect(survives("go", as: "goes"))
        #expect(survives("happy", as: "happiest"))
        #expect(!survives("dry", as: "dryer"))
        #expect(!survives("corn", as: "corner"))
        #expect(
            !MeaningPreservationGuard.grammarVerdict(
                kept: "the corn is ripe", rewritten: "The corner is ripe."
            )
            .isAccepted)
    }

    /// Three letters is what `GeneralVocabulary` calls a word — "SQL or API" — so an identifier must not swallow one.
    @Test("sees a three-letter word spelled into an identifier the model wrote")
    func seesAShortWordInAnIdentifier() {
        #expect(MeaningPreservationGuard.identifierParts("fetchURL") == ["fetch", "url"])
        #expect(MeaningPreservationGuard.identifierParts("new_tab") == ["new", "tab"])
        let downTown = MeaningPreservationGuard.grammarTokens("down town")
        #expect(!MeaningPreservationGuard.isSpelled("downtown", from: downTown))
        let doNot = MeaningPreservationGuard.grammarTokens("do not")
        #expect(!MeaningPreservationGuard.isSpelled("don't", from: doNot))
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
            !MeaningPreservationGuard.candidateVerdict(
                [span], kept: "let me in it tomorrow", rewritten: "Let me begin it tomorrow."
            )
            .isAccepted)

        let amount = DoubtfulSpan(heard: "a mount", confidence: 0.3, candidates: ["amount"])
        #expect(
            MeaningPreservationGuard.candidateVerdict(
                [amount], kept: "the a mount is fine", rewritten: "The amount is fine."
            )
            .isAccepted)
    }
}
