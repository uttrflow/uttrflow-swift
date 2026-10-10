import Testing

@testable import UttrflowAI

/// A spoken unit word written as the symbol or abbreviation beside its number is the same word.
@Suite("Meaning guard unit words written as symbols")
struct GuardUnitSymbolTests {
    @Test(
        "accepts a currency, percent or meridiem written as its symbol or dotted form beside the same number",
        arguments: [
            ("revenue was 1.2 million dollars up 8 percent", "Revenue was $1.2 million, up 8%."),
            ("a fixed fee of 12500 dollars", "A fixed fee of $12,500."),
            ("churn fell to 3.6 per cent", "Churn fell to 3.6%."),
            ("landing at 6:10 pm local time", "Landing at 6:10 p.m. local time."),
            ("at 10:30 am pacific time", "At 10:30 a.m. Pacific time."),
        ]
    )
    func acceptsUnitWrittenAsSymbol(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
    }

    @Test("refuses a unit word whose symbol stands beside another amount")
    func refusesSymbolOnAnotherAmount() {
        #expect(
            MeaningPreservationGuard.grammarVerdict(
                kept: "the fee is 12500 dollars and 40 more", rewritten: "The fee is 12500 and $40 more.")
                == .rejected(reason: "the rewrite lost or replaced 'dollars'", kind: .lostWord))
    }

    @Test("credits one symbol to one amount, so a unit said twice needs two symbols")
    func creditsEachSymbolOnce() {
        #expect(
            !MeaningPreservationGuard.grammarVerdict(
                kept: "it costs 5 dollars or 5 dollars", rewritten: "It costs $5 or 5."
            ).isAccepted)
    }
}
