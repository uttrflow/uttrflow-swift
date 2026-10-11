import Testing
import UttrflowAI

@testable import UttrflowEval

@Suite("Registry version formatting from the corpus")
struct RegistryTagCorpusTests {
    @Test("the YAML case preserves key spacing and keeps its image version joined")
    func yamlImageTagMatchesSpokenCase() async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == "probe-yaml-keys" })
        let output = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
        #expect(output == testCase.expected)
        #expect(Scorer.score(output, against: testCase).passed)
    }
}
