// The developer dictations Docs/bakeoff.md describes, whose pass rate is their exact-match rate.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Developer genre dictations")
struct DeveloperGenreCorpusTests {
    private let cases = EvaluationCorpus.cases(in: .developerGenre)

    @Test("holds twenty-five whole dictations of twenty to a hundred and twenty words")
    func twentyFiveWholeDictations() {
        #expect(cases.count == 25)
        for testCase in cases {
            let words = WordTokens.words(testCase.spoken, .display).count
            #expect((20...120).contains(words), "\(testCase.id) has \(words) words")
        }
    }

    @Test("passes a case only when the output is its reference character for character")
    func passingIsExactMatch() {
        for testCase in cases {
            #expect(testCase.expectedExact == testCase.expected, "\(testCase.id)")
            #expect(Scorer.score(testCase.expected, against: testCase).passed, "\(testCase.id)")
            let oneCharacterShort = Scorer.score(String(testCase.expected.dropLast()), against: testCase)
            #expect(!oneCharacterShort.passed, "\(testCase.id)")
        }
    }
}
