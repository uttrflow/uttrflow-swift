import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Phonetic candidates: ordinary words that sound alike")
struct PhoneticCandidatesTests {
    private let source = PhoneticCandidates()

    @Test("offers the homophone a recogniser confuses a word with")
    func offersAHomophone() async {
        let found = await source.candidates(for: Draft.Word("hear", confidence: 0.3), in: .unknown)
        #expect(found.contains("here"))
    }

    /// A there/their or on/one swap changes what the sentence says, so no reading is offered for either.
    @Test(
        "offers nothing where the word or its homophone is a function word",
        arguments: ["there", "their", "then", "one"])
    func offersNoFunctionWordHomophone(heard: String) async {
        let found = await source.candidates(for: Draft.Word(heard, confidence: 0.3), in: .unknown)
        #expect(found.allSatisfy { !FunctionWords.holds($0) }, "\(heard) → \(found)")
        #expect(!found.contains { ["there", "their", "than", "on"].contains($0) })
    }

    @Test("offers nothing for a word whose only rhymes open differently")
    func offersNoRhymes() async {
        #expect(await source.candidates(for: Draft.Word("cash", confidence: 0.3), in: .unknown).isEmpty)
        #expect(await source.candidates(for: Draft.Word("reader", confidence: 0.3), in: .unknown).isEmpty)
    }

    @Test("offers nothing at all for a doubted function word", arguments: ["there", "their", "than", "on"])
    func offersNothingForAFunctionWord(heard: String) async {
        #expect(await source.candidates(for: Draft.Word(heard, confidence: 0.3), in: .unknown).isEmpty)
    }

    @Test("offers at most two, so the screen and the dictionary keep their places on the line")
    func capsWhatItOffers() async {
        let found = await source.candidates(for: Draft.Word("hear", confidence: 0.3), in: .unknown)
        #expect(found.count <= PhoneticCandidates.maximumOffered)
    }
}
