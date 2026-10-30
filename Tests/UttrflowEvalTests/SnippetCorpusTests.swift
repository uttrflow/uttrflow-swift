import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline
import UttrflowTestSupport

@testable import UttrflowEval

/// Snippet cases pass only once the pipeline's own expansion stage has run, never on a tidier alone.
@Suite("The snippet corpus")
struct SnippetCorpusTests {
    static let rules = TransformerRouter(
        engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock(),
        rulesAlone: .shortReplies)

    @Test("guards the snippet issue and stays out of the corpus every tidier is scored on alone")
    func casesAreNamedAndSeparate() {
        #expect(!EvaluationCorpus.snippet.isEmpty)
        for testCase in EvaluationCorpus.snippet {
            #expect(testCase.category == .snippet)
            #expect(testCase.id.hasSuffix("-2368"))
            #expect(!testCase.snippets.isEmpty)
        }
        #expect(!EvaluationCorpus.all.contains { $0.category == .snippet })
    }

    @Test("passes written through the pipeline with its snippets", arguments: EvaluationCorpus.snippet)
    func passesThroughThePipeline(_ testCase: EvaluationCase) async {
        let written = await testCase.written(through: Self.rules)
        let score = Scorer.score(written, against: testCase)
        #expect(score.passed, "\(testCase.id) wrote: \(written)")
    }

    @Test("fails when the tidier's text is scored with no expansion", arguments: EvaluationCorpus.snippet)
    func failsWithoutExpansion(_ testCase: EvaluationCase) async throws {
        let tidied = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
        #expect(!Scorer.score(tidied, against: testCase).passed)
    }

    @Test("reads a case's snippets from its file")
    func snippetsAreDecoded() throws {
        let only = try #require(
            try CorpusFile.decode(
                Data(
                    #"[{"id": "s", "spoken": "my sign off", "expected": "Bye.", "snippets": {"my sign off": "Bye"}}]"#
                        .utf8),
                as: .snippet
            ).first)
        #expect(only.snippets == ["my sign off": "Bye"])
        #expect(only.shaped(.recogniser).snippets == only.snippets)
    }
}
