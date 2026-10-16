import Testing

@testable import UttrflowCore
@testable import UttrflowDictionary

/// The Hindi words for hours are romanised Hindi, so no lexicon term replaces them. See `Docs/latin-output.md`.
@Suite("Hindi hours are not restored")
struct HindiHoursRestorationTests {
    @Test(
        "keeps the romanised word for hours when restoring loanwords",
        arguments: [("घंटे", "ghante"), ("घंटों", "ghanton"), ("घंटा", "ghanta")]
    )
    func hoursStayHindi(devanagari: String, romanised: String) {
        let draft = Draft(romanising: Transcription(text: devanagari))
        let restored = LoanwordRestoration().restoring(draft)
        #expect(restored.words.map(\.text) == [romanised])
    }
}
