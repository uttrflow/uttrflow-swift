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

    /// The engine's lookup is recall; what this source offers is that list restrained, never more than it.
    @Test("offers a restrained part of what the correction engine's lookup recalls")
    func restrainsTheEngineLookup() async {
        let found = await source.candidates(for: Draft.Word("kestral", confidence: 0.3), in: .unknown)
        let engine = WordCorrectionEngine.spellings(of: "kestral", in: CorrectionFixtures.index).map(\.word)
        #expect(found.allSatisfy(engine.contains))
        #expect(found.count <= DictionaryCandidates.maximumOffered)
        #expect(found.contains("Kestrel"))
    }
}
