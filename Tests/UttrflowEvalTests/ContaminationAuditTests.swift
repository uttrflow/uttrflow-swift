// Tests that no tuned-on asset carries a corpus passage.
import Foundation
import Testing
import UttrflowAI

@testable import UttrflowEval

@Suite("Contamination audit")
struct ContaminationAuditTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private struct Manifest: Decodable {
        struct Asset: Decodable { let path: String }
        let assets: [Asset]
    }

    /// Every text or table asset in `Resources/DataManifest.json`, by repository path.
    private static func dataAssets() throws -> [(path: String, lines: [String])] {
        let data = try Data(contentsOf: root.appending(path: "Resources/DataManifest.json"))
        return try JSONDecoder().decode(Manifest.self, from: data).assets.map(\.path)
            .filter { ["txt", "json"].contains(URL(filePath: $0).pathExtension) }
            // The corpus's own case files are the passages, not an asset that could leak them.
            .filter { !$0.hasPrefix("Sources/UttrflowEval/Resources/Corpus/") }
            .sorted()
            .map { path in
                let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
                return (path, text.components(separatedBy: .newlines))
            }
    }

    @Test("no bundled data asset carries a corpus passage")
    func dataAssetsAreClean() throws {
        let audit = ContaminationAudit.corpus
        let assets = try Self.dataAssets()
        #expect(assets.count >= 2, "the data manifest lists nothing to audit")
        let findings = assets.flatMap { audit.findings(in: $0.lines, asset: $0.path) }
        #expect(findings.isEmpty, "\(findings)")
    }

    @Test("no prompt rule, contract or worked example carries a corpus passage")
    func promptIsClean() {
        let builder = PromptBuilder.standard
        let fragments = [builder.contract] + builder.blocks.values.map(\.rules) + builder.allWorkedExamples
        let findings = ContaminationAudit.corpus.findings(in: fragments, asset: "prompt")
        #expect(findings.isEmpty, "\(findings)")
    }

    @Test("a lexicon line copied from a case is caught with the case id and the asset path")
    func copiedEntryIsCaught() throws {
        let copied = try #require(EvaluationCorpus.all.first { Scorer.tokens($0.expected).count >= 12 })
        let lexicon = ["kubernetes", "an unrelated line about nothing", "term: " + copied.expected]
        let findings = ContaminationAudit.corpus.findings(in: lexicon, asset: "Fixtures/lexicon.txt")
        #expect(findings.contains { $0.caseID == copied.id && $0.asset == "Fixtures/lexicon.txt" })
        let runLength = ContaminationAudit.sharedRunWords
        #expect(findings.allSatisfy { $0.words.split(separator: " ").count == runLength })
    }

    @Test("a short phrase counts only when whole, and shared function words alone do not")
    func thresholds() {
        let audit = ContaminationAudit(passages: [("case", "please send the report to the team by friday")])
        #expect(audit.findings(in: "send the report", asset: "a").isEmpty)
        #expect(audit.findings(in: "the report to the", asset: "a").map(\.caseID) == ["case"])
        #expect(audit.findings(in: "to the team by the end of the week", asset: "a").isEmpty)
        #expect(
            audit.findings(in: "Please send the report to the team by Friday!", asset: "a").map(\.words)
                == ["please send the report to the team by", "send the report to the team by friday"])
    }

    @Test("a transcription passage is read in every form it is written in")
    func transcriptionPassagesAreRead() throws {
        let passage = try #require(TranscriptionCorpus.all.first { $0.devanagari != nil })
        let ids = Set(ContaminationAudit.corpusPassages.filter { $0.caseID == passage.id }.map(\.text))
        #expect(ids == Set(passage.forms))
    }
}
