import Foundation
import Testing
import UttrflowAI
import UttrflowTestSupport

@testable import UttrflowEval

/// Number cases scored without folding number words, with a wrong value and a false conversion counted apart.
@Suite("The number grammar score")
struct NumberGrammarScoreTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/number-grammar.md")

    @Test("counts a number word turned into a numeral as a false conversion, not a value error")
    func falseConversion() {
        let score = NumberGrammarScore(expected: "No one came.", output: "No 1 came.")
        #expect(!score.isExact)
        #expect(!score.isValueError)
        #expect(score.falseConversions == 1)
    }

    @Test("counts tens swapped for teens as a value error, not a false conversion")
    func tensForTeens() {
        let score = NumberGrammarScore(expected: "We need 50 chairs.", output: "We need 15 chairs.")
        #expect(score.isValueError)
        #expect(score.falseConversions == 0)
    }

    @Test("counts the right value in the wrong form as neither, only as inexact")
    func wrongForm() {
        let score = NumberGrammarScore(expected: "We need 12 chairs.", output: "We need twelve chairs.")
        #expect(!score.isExact)
        #expect(!score.isValueError)
        #expect(score.falseConversions == 0)
    }

    @Test("reads times, grouped thousands and ordinal suffixes as their values")
    func numeralShapes() {
        #expect(!NumberGrammarScore(expected: "At 4:30.", output: "At four thirty.").isValueError)
        #expect(!NumberGrammarScore(expected: "1,500 people", output: "1500 people").isValueError)
        #expect(!NumberGrammarScore(expected: "the 3rd row", output: "the 3 row").isValueError)
    }

    @Test("prints a row for every class under every place policy")
    func rowPerClass() {
        let report = NumberGrammarReport([])
        #expect(report.rows.count == SemioticClass.allCases.count * 2)
        #expect(SemioticClass.allCases.allSatisfy { $0.formattingClass == .numbers })
    }

    @Test("raises false conversions and not value errors when one becomes 1 in a seeded run")
    func seededFalseConversion() throws {
        let pronoun = try #require(EvaluationCorpus.all.first { $0.semiotic == .staysWords })
        let report = NumberGrammarReport([
            (pronoun, pronoun.expected.replacingOccurrences(of: "one", with: "1"))
        ])
        let row = try #require(report.rows.first { $0.semioticClass == .staysWords && $0.cases == 1 })
        #expect(row.falseConversions == 1)
        #expect(row.valueErrors == 0)
    }

    @Test("matches Docs/number-grammar.md, the rules engine's baseline over the tagged cases")
    func pageMatchesRules() async throws {
        var results: [(testCase: EvaluationCase, output: String)] = []
        for testCase in EvaluationCorpus.all where testCase.semiotic != nil {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            results.append((testCase, result.text))
        }
        let generated = NumberGrammarReport(results).markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
