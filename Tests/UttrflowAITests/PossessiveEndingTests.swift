import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// A possessive said after a name is a morpheme the dictionary spelling must keep. See Docs/ai-correction-thresholds.md.
@Suite("Possessive endings")
struct PossessiveEndingTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()

    /// An index over one word the user added.
    private static func index(_ word: String) -> PhoneticIndex {
        PhoneticIndex(
            entries: [DictionaryEntry(word: word, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))])
    }

    @Test(
        "never deletes the possessive of a name it respells",
        arguments: ["Kubernetes", "Redis", "Postgres", "Grafana", "Nikhil"])
    func keepsThePossessive(entry: String) {
        let heard = "\(entry.lowercased())'s"
        let sentence = "we asked about the \(heard) status today"
        for context in [AppContext.unknown, CorrectionFixtures.showing("\(entry) notes")] {
            let proposals = engine.proposals(
                for: CorrectionFixtures.doubting(sentence), against: Self.index(entry), seeing: context)
            #expect(
                proposals.allSatisfy { $0.replacement.hasSuffix("'s") },
                "\(heard) → \(proposals.map(\.replacement))")
        }
    }

    @Test("leaves the possessive of a name already spelled as the dictionary spells it")
    func leavesASpelledName() {
        let utterance = CorrectionFixtures.doubting("we asked about the Kubernetes's status today")
        #expect(engine.proposals(for: utterance, against: Self.index("Kubernetes")).isEmpty)
    }

    @Test("keeps a plural ending the same way it always did")
    func keepsAPluralEnding() throws {
        let utterance = CorrectionFixtures.spoken("we asked about the figmas status today")
        let proposals = engine.proposals(for: utterance, against: Self.index("Figma"))
        #expect(try #require(proposals.first).replacement == "Figmas")
    }
}
