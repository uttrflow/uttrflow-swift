import Foundation
import Testing
import UttrflowAI
import UttrflowTestSupport

@testable import UttrflowEval

/// The genre cases: every genre is filled, each case is a whole text, and the page matches the rules outputs.
@Suite("The genre coverage matrix")
struct GenreMatrixTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/genre-matrix.md")

    @Test("gives every genre at least the covered floor of cases")
    func everyGenreIsCovered() {
        for row in GenreMatrix().rows {
            #expect(row.isCovered, "\(row.genre) has \(row.caseIDs.count) cases")
        }
        #expect(EvaluationCorpus.genres.count >= 60)
    }

    @Test("makes every genre case a whole text of 40 to 150 spoken words")
    func casesAreWholeTexts() {
        for item in EvaluationCorpus.genres {
            let words = Scorer.tokens(item.spoken).count
            #expect((40...150).contains(words), "\(item.id) has \(words) spoken words")
        }
    }

    @Test("names what must not be added for every genre case, and keeps it out of the reference")
    func guardsAgainstInvention() {
        for item in EvaluationCorpus.genres {
            #expect(!item.mustNotAdd.isEmpty, "\(item.id)")
            for word in item.mustNotAdd {
                #expect(!item.expected.lowercased().contains(word.lowercased()), "\(item.id): \(word)")
            }
            #expect(item.expected.unicodeScalars.allSatisfy { $0.isASCII }, "\(item.id)")
        }
    }

    @Test("drops the break that opens a poem dictated into an empty field")
    func openingBreakInEmptyField() async throws {
        let poem = try #require(EvaluationCorpus.genres.first { $0.id == "genre-poem-harbour-morning" })
        let written = try await RuleBasedTransformer().transform(poem.transformationRequest()).text
        #expect(written.hasPrefix("The harbour wakes before the town\n"), "\(written)")
    }

    @Test("matches Docs/genre-matrix.md, generated from the genre cases and what the rules write for them")
    func pageMatchesCorpus() async throws {
        var outputs: [String: String] = [:]
        for item in EvaluationCorpus.genres {
            outputs[item.id] = try await RuleBasedTransformer().transform(item.transformationRequest()).text
        }
        let generated = GenreMatrix(outputs: outputs).markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
