import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Dictionary candidates: the user's own spellings")
struct DictionaryCandidatesTests {
    private let source = DictionaryCandidates(index: { CorrectionFixtures.index })

    @Test("offers the user's spelling for a run that sounds like it")
    func offersASpelling() async {
        let found = await source.candidates(
            for: Draft.Word("payment sheet", confidence: 0.3), in: .unknown)
        #expect(found.contains("PaymentSheet"))
    }

    @Test("offers nothing when the dictionary already spells the run exactly as it was heard")
    func offersNothingForItsOwnWord() async {
        let found = await source.candidates(for: Draft.Word("Claude", confidence: 0.3), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("offers nothing for a word no entry sounds like")
    func offersNothingForAStranger() async {
        let found = await source.candidates(for: Draft.Word("elephant", confidence: 0.3), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("answers the same question the correction engine asks of the same dictionary")
    func sharesTheEngineLookup() async {
        let found = await source.candidates(for: Draft.Word("kestral", confidence: 0.3), in: .unknown)
        let engine = WordCorrectionEngine.spellings(of: "kestral", in: CorrectionFixtures.index)
        #expect(found == engine.map(\.word))
        #expect(found.contains("Kestrel"))
    }
}
