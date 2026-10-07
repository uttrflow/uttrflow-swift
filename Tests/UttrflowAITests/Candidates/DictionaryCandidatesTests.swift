import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Dictionary candidates: the user's own spellings")
struct DictionaryCandidatesTests {
    private let source = DictionaryCandidates(index: { CorrectionFixtures.index })

    /// The one source that knows which entry a spelling came from, so the count a taken reading earns reaches it.
    @Test("keeps the entry each spelling was taught by")
    func keepsTheEntry() async throws {
        let entry = try #require(CorrectionFixtures.entries.first { $0.word == "PaymentSheet" })

        let found = await source.candidates(
            for: Draft.Word("payment sheet", evidence: .score(0.3)), in: .unknown)

        #expect(found.first { $0.spelling == "PaymentSheet" }?.entryID == entry.id)
    }

    @Test("offers the user's spelling for a run that sounds like it")
    func offersASpelling() async {
        let found = await source.candidates(
            for: Draft.Word("payment sheet", evidence: .score(0.3)), in: .unknown)
        #expect(found.map(\.spelling).contains("PaymentSheet"))
    }

    @Test("offers nothing when the dictionary already spells the run exactly as it was heard")
    func offersNothingForItsOwnWord() async {
        let found = await source.candidates(for: Draft.Word("Claude", evidence: .score(0.3)), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("offers nothing for a word no entry sounds like")
    func offersNothingForAStranger() async {
        let found = await source.candidates(for: Draft.Word("elephant", evidence: .score(0.3)), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("answers the same question the correction engine asks of the same dictionary")
    func sharesTheEngineLookup() async {
        let found = await source.candidates(for: Draft.Word("kestral", evidence: .score(0.3)), in: .unknown)
        let engine = WordCorrectionEngine.spellings(of: "kestral", in: CorrectionFixtures.index)
        #expect(
            found.map(\.spelling)
                == Array(engine.map(\.word).prefix(DictionaryCandidates.maximumOffered)))
        #expect(found.map(\.spelling).contains("Kestrel"))
    }

    @Test("offers at most two, so the screen and the ordinary words keep their places on the line")
    func capsWhatItOffers() async {
        let found = await source.candidates(for: Draft.Word("kestral", evidence: .score(0.3)), in: .unknown)
        #expect(found.count <= DictionaryCandidates.maximumOffered)
    }

    @Test("does not offer an inferred spelling for an ordinary word without screen evidence")
    func restrainsInferredCandidatesForOrdinaryWords() async {
        let entry = DictionaryEntry(
            word: "mint", origin: .learned, firstSeen: Date(timeIntervalSince1970: 0))
        let dictionary = DictionaryCandidates { PhoneticIndex(entries: [entry]) }

        let found = await dictionary.candidates(
            for: Draft.Word("monday", evidence: .score(0.3)), in: .unknown)

        #expect(found.isEmpty)
    }

    @Test("allows an inferred candidate for an ordinary word when the screen confirms it")
    func acceptsScreenCorroboration() async {
        let entry = DictionaryEntry(
            word: "mint", origin: .learned, firstSeen: Date(timeIntervalSince1970: 0))
        let dictionary = DictionaryCandidates { PhoneticIndex(entries: [entry]) }
        let situation = Situation(
            app: AppContext(documentName: "mint notes"), insertion: .unknown, destination: .plain)

        let found = await dictionary.candidates(
            for: Draft.Word("monday", evidence: .score(0.3)), in: situation)

        #expect(found.map(\.spelling) == ["mint"])
    }
}
