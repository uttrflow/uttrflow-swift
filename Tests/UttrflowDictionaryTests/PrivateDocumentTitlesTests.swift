// Tests for the document categories whose window titles are never mined.

import Testing
import UttrflowTestSupport

@testable import UttrflowDictionary

@Suite("Private document titles")
struct PrivateDocumentTitlesTests {
    @Test(
        "Names the category of a sensitive title",
        arguments: [
            ("Lab results pgvector.pdf", PrivateDocumentTitles.Category.medical),
            ("Divorce settlement draft", .legal),
            ("Bank Statement - March", .financial),
            ("Tax return 2025", .tax),
            ("Passport scan", .identity),
        ])
    func namesCategory(title: String, category: PrivateDocumentTitles.Category) {
        #expect(PrivateDocumentTitles.category(of: title) == category)
    }

    @Test("Leaves an ordinary title alone and matches whole words only")
    func ordinaryTitles() {
        #expect(PrivateDocumentTitles.category(of: "pgvector migration") == nil)
        #expect(PrivateDocumentTitles.category(of: "Patients portal redesign") == nil)
        #expect(PrivateDocumentTitles.category(of: "Standalone notes") == nil)
    }

    @Test("A sensitive title yields no sighting even when a term is spoken")
    func noSighting() {
        let heard = "migrate the pgvector table"
        let ordinary = LearnableWords.seenAndSaid(
            heard: heard, seeing: .fixture(documentName: "pgvector migration"))
        #expect(ordinary == ["pgvector"])
        let medical = LearnableWords.seenAndSaid(
            heard: heard, seeing: .fixture(documentName: "pgvector medical records"))
        #expect(medical.isEmpty)
    }

    @Test("Every category ships at least one phrase")
    func everyCategoryHasPhrases() {
        for category in PrivateDocumentTitles.Category.allCases {
            #expect(!(PrivateDocumentTitles.phrases[category] ?? []).isEmpty)
        }
    }
}
