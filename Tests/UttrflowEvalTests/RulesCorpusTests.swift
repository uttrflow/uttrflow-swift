import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The corpus cases the deterministic passes must pass on their own, with no model anywhere near them.
@Suite("The rules over the corpus")
struct RulesCorpusTests {
    /// Every case the passes are answerable for; one leaving this list is a regression, not a tuning choice.
    static let rulesMustPass: Set<String> = [
        "false-start", "self-correction", "filler-heavy", "pronoun-i", "number-words", "short-yes",
        "repeated-phrase", "i-mean-correction", "actually-between-numbers", "false-no-stays", "spoken-comma",
        "comma-as-a-word", "new-paragraph", "time-of-day", "percentage", "period-as-a-word", "spoken-period",
        "period-after-new-line",
        "version-number", "port-number", "acronyms", "kubernetes", "function-name", "sql-terms",
        "dictated-question", "dictated-instruction", "injection", "asks-for-help", "sounds-like-a-prompt",
    ]

    private func score(_ testCase: EvaluationCase) async throws -> CaseScore {
        let request = TransformationRequest(
            transcription: Transcription(text: testCase.spoken), context: testCase.context)
        let result = try await RuleBasedTransformer().transform(request)
        return Scorer.score(result.text, against: testCase)
    }

    @Test(
        "passes every case the passes are answerable for",
        arguments: EvaluationCorpus.all.filter { rulesMustPass.contains($0.id) })
    func passes(testCase: EvaluationCase) async throws {
        let score = try await score(testCase)
        #expect(
            score.passed,
            "\(testCase.id): \(Int(score.similarity * 100))%, lost \(score.lost), invented \(score.invented)")
    }

    @Test("names only cases that exist")
    func namesRealCases() {
        let ids = Set(EvaluationCorpus.all.map(\.id))
        #expect(
            Self.rulesMustPass.isSubset(of: ids),
            "\(Self.rulesMustPass.subtracting(ids)) are not in the corpus")
    }

    @Test(
        "writes the exact reference for the cases that have one right answer",
        arguments: [
            ("self-correction", "Let's meet at five on tuesday."),
            ("version-number", "We're on postgres 16.2 right now."),
            ("spoken-comma", "We still need milk, eggs, and bread from the shop."),
            ("new-paragraph", "Thanks for the update\n\nThe second issue is the login timeout"),
            ("time-of-day", "The dentist moved my appointment to 2:30 pm tomorrow."),
            ("port-number", "The gateway listens on port 8080 in staging."),
            ("percentage", "Conversion dropped by 5% after the redesign."),
            ("actually-between-numbers", "Let's get coffee at three."),
            ("period-as-a-word", "The trial period ended last week."),
            ("spoken-period", "Ship it."),
            ("period-after-new-line", "First line\nsecond line."),
        ])
    func exactText(id: String, expected: String) async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == id })
        let request = TransformationRequest(transcription: Transcription(text: testCase.spoken))
        #expect(try await RuleBasedTransformer().transform(request).text == expected)
    }
}
