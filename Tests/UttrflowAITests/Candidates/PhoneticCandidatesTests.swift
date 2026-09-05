import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Phonetic candidates: ordinary words that sound alike")
struct PhoneticCandidatesTests {
    private let source = PhoneticCandidates()

    @Test("offers the homophone a recogniser confuses a word with")
    func offersAHomophone() async {
        let found = await source.candidates(for: Draft.Word("there", confidence: 0.3), in: .unknown)
        #expect(found.contains("their"))
    }

    @Test("offers nothing for a word whose only rhymes open differently")
    func offersNoRhymes() async {
        #expect(await source.candidates(for: Draft.Word("cash", confidence: 0.3), in: .unknown).isEmpty)
        #expect(await source.candidates(for: Draft.Word("reader", confidence: 0.3), in: .unknown).isEmpty)
    }

    @Test("offers at most two, so the screen and the dictionary keep their places on the line")
    func capsWhatItOffers() async {
        let found = await source.candidates(for: Draft.Word("there", confidence: 0.3), in: .unknown)
        #expect(found.count <= PhoneticCandidates.maximumOffered)
    }
}
