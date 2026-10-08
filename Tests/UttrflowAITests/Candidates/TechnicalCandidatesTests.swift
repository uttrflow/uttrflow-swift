import Testing
import UttrflowAI
import UttrflowCore

@Suite("Technical candidates: shipped terms that sound like a doubted word")
struct TechnicalCandidatesTests {
    private let source = TechnicalCandidates()

    @Test("offers OAuth for a doubted Oath")
    func offersOAuth() async {
        let found = await source.candidates(for: Draft.Word("Oath", evidence: .score(0.32)), in: .unknown)
        #expect(found.map(\.spelling).contains("OAuth"), "\(found)")
    }

    @Test("offers nothing for a term only ever spelt out letter by letter")
    func offersNoLetterSpeltTerm() async {
        let found = await source.candidates(for: Draft.Word("ape", evidence: .score(0.3)), in: .unknown)
        #expect(!found.map(\.spelling).contains("API"), "\(found)")
    }

    @Test("never offers a word its own spelling back, and never more than its budget")
    func staysWithinBudget() async {
        for heard in ["OAuth", "Jason", "the", "here", "made"] {
            let found = await source.candidates(for: Draft.Word(heard, evidence: .score(0.3)), in: .unknown)
            #expect(found.count <= TechnicalCandidates.maximumOffered)
            #expect(!found.contains { $0.spelling.lowercased() == heard.lowercased() }, "\(heard) → \(found)")
        }
    }

    @Test("reaches the model as a doubtful span through the standard sources")
    func reachesASpan() async {
        let spans = await DoubtfulWords.standard.spans(
            in: .heard("add ?Oath login", unsure: 0.32), for: .unknown)
        #expect(spans.flatMap(\.candidates).map(\.spelling).contains("OAuth"), "\(spans)")
    }
}
