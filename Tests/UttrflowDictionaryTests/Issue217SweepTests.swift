import UttrflowCore
import UttrflowTestSupport
import Testing

@testable import UttrflowDictionary

/// Regression for issue 217: what the dictionary learns off a screen asks the restraint too.
@Suite("Issue 217 sweep: LearnableWords asks more than the bare key")
struct Issue217LearnableSweepTests {
    @Test("refuses a screen term that only collides with a spoken ordinary word")
    func refusesACollision() {
        let found = LearnableWords.seenAndSaid(
            heard: "i made a change to the layout",
            seeing: .fixture(documentName: "MDT dashboard"))
        #expect(found.isEmpty)
    }

    @Test("refuses the same collision however many dictations it turns up in")
    func refusesItThreeSightingsIn() {
        var ledger = SightingLedger()
        var learnt: [String] = []
        for _ in 1...3 {
            let terms = LearnableWords.seenAndSaid(
                heard: "i made a change to the layout",
                seeing: .fixture(documentName: "MDT dashboard"))
            learnt = ledger.record(terms)
        }
        #expect(learnt.isEmpty)
    }

    @Test("still learns the term the path exists for")
    func keepsWhatThePathIsFor() {
        let found = LearnableWords.seenAndSaid(
            heard: "add a total to the payment sheet",
            seeing: .fixture(documentName: "PaymentSheet.swift — Acme"))
        #expect(found == ["PaymentSheet"])
    }

    @Test("refuses a multi-word span that only collides")
    func refusesAMultiWordCollision() {
        let found = LearnableWords.seenAndSaid(
            heard: "the meeting ran late", seeing: .fixture(documentName: "MTNGRN report"))
        #expect(found.isEmpty)
    }
}

/// Regression for issue 217: the same bare key deciding that a replacement is a correction.
@Suite("Issue 217 sweep: corrected() asks more than the bare key")
struct Issue217CorrectedSweepTests {
    @Test(
        "refuses an unrelated replacement that only shares the sound skeleton",
        arguments: [("mood", "MDT"), ("but", "Bittl"), ("mad", "Modo"), ("boot", "Bitly")])
    func refusesAnUnrelatedReplacement(selected: String, wrote: String) {
        #expect(LearnableWords.corrected(over: selected, wrote: wrote) == nil)
    }

    @Test("still learns the spelling that replaced a homophone of itself")
    func keepsARealCorrection() {
        #expect(LearnableWords.corrected(over: "utter flow", wrote: "Uttrflow") == "Uttrflow")
        #expect(LearnableWords.corrected(over: "payment sheet", wrote: "PaymentSheet") == "PaymentSheet")
    }
}
