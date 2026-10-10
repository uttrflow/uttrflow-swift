import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The rules floor scored on transcripts shaped the way the default recogniser emits them.
@Suite("The rules over recogniser-shaped input")
struct InputShapeCorpusTests {
    @Test("capitalises the first letter and closes with the mark the expected text ends in")
    func shapesFromExpected() throws {
        let question = try #require(
            EvaluationCorpus.all.first { $0.takesRecogniserShape && $0.expected.hasSuffix("?") })
        let shaped = question.shaped(.recogniser)
        #expect(shaped.spoken.first?.isUppercase == true)
        #expect(shaped.spoken.hasSuffix("?"))
        #expect(shaped.expected == question.expected)
        #expect(String(shaped.spoken.dropFirst().dropLast()) == String(question.spoken.dropFirst()))
    }

    @Test("leaves a case the recogniser shape does not apply to exactly as written")
    func leavesUnshapeableCases() {
        for testCase in EvaluationCorpus.all where !testCase.takesRecogniserShape {
            #expect(testCase.shaped(.recogniser) == testCase)
        }
        for testCase in EvaluationCorpus.all {
            #expect(testCase.shaped(.bare) == testCase)
        }
    }

    @Test("passes shaped every case the rules pass bare")
    func shapedKeepsBarePasses() async throws {
        var regressed: [String] = []
        for testCase in EvaluationCorpus.all where testCase.takesRecogniserShape {
            let bare = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            guard Scorer.score(bare.text, against: testCase).passed else { continue }
            let shaped = testCase.shaped(.recogniser)
            let output = try await RuleBasedTransformer().transform(shaped.transformationRequest())
            if !Scorer.score(output.text, against: testCase).passed {
                regressed.append("\(testCase.id): \(shaped.spoken) -> \(output.text)")
            }
        }
        #expect(regressed.isEmpty, "\(regressed.joined(separator: "\n"))")
    }
}
