import Testing
import UttrflowCore
@testable import UttrflowAI
@testable import UttrflowDictionary

@Suite("Homophone candidates")
struct HomophoneCandidatesTests {
    @Test("Offers the partners of a three-way class, ordinary words first")
    func offersEveryPartnerInOrder() async {
        let source = HomophoneCandidates()
        let offered = await source.candidates(for: Draft.Word("there", evidence: .score(0.8)), in: .unknown)
        #expect(offered.map(\.spelling).contains("their"))
        #expect(offered.count <= HomophoneCandidates.maximumOffered)
    }

    @Test(
        "Offers only ordinary words the lexicon lists as said exactly alike, at most the cap",
        arguments: ["hear", "know", "write", "buy", "hour"])
    func offersOnlySameSound(word: String) async {
        let source = HomophoneCandidates()
        let offered = await source.candidates(for: Draft.Word(word, evidence: .score(0.8)), in: .unknown)
        #expect(!offered.isEmpty)
        #expect(offered.count <= HomophoneCandidates.maximumOffered)
        #expect(offered.allSatisfy { PhonemeLexicon.shared.soundsSame($0.spelling, word) })
    }

    @Test("Offers nothing for a word the lexicon lists with no homophone")
    func offersNothingWithoutAPartner() async {
        let offered = await HomophoneCandidates().candidates(
            for: Draft.Word("keyboard", evidence: .score(0.8)), in: .unknown)
        #expect(offered.isEmpty)
    }
}
