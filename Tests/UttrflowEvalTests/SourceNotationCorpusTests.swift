import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Spoken operators and brackets in source code, written as the caret's language writes them.
@Suite("The source notation corpus")
struct SourceNotationCorpusTests {
    /// The languages the corpus covers, each the second part of its case ids.
    static let languages = ["swift", "python", "javascript", "typescript"]

    @Test("holds thirty cases for each language family")
    func coversEachLanguage() {
        let ids = EvaluationCorpus.sourceNotation.map(\.id)
        #expect(ids.count { $0.hasPrefix("source-swift-") } == 30)
        #expect(ids.count { $0.hasPrefix("source-python-") } == 30)
        #expect(ids.count { $0.hasPrefix("source-javascript-") || $0.hasPrefix("source-typescript-") } == 30)
        #expect(Set(ids.map { $0.split(separator: "-")[1] }) == Set(Self.languages.map { Substring($0) }))
    }

    @Test("writes every case exactly under the rules", arguments: EvaluationCorpus.sourceNotation)
    func writesExactly(testCase: EvaluationCase) async throws {
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        #expect(result.text == testCase.expectedExact, "\(testCase.id)")
    }

    @Test("adds no word: every word written is a word spoken", arguments: EvaluationCorpus.sourceNotation)
    func addsNoWord(testCase: EvaluationCase) async throws {
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        let spoken = Set(Self.words(testCase.spoken))
        for word in Self.words(result.text) {
            #expect(spoken.contains(word) || Int(word) != nil, "\(testCase.id) wrote \"\(word)\"")
        }
    }

    /// The lower-cased letter runs of a text, which notation never writes.
    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
