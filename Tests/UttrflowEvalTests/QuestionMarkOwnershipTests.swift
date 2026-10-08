// Tests for the question-mark ownership score: precision, recall, false questions and their intervals.
import Testing
import UttrflowEval

@Suite("Who owns the question mark")
struct QuestionMarkOwnershipTests {
    private func sentence(_ isQuestion: Bool, decoder: Bool, rules: Bool) -> QuestionMarkCase {
        QuestionMarkCase(
            isQuestion: isQuestion, decoderAsks: decoder, decoderQuestionProbability: nil, rulesAsk: rules)
    }

    @Test("scores each owner against the truth, and both together")
    func scoresEachOwner() {
        let cases = [
            sentence(true, decoder: true, rules: true),
            sentence(true, decoder: false, rules: true),
            sentence(false, decoder: true, rules: false),
            sentence(false, decoder: false, rules: false),
        ]
        let ownership = QuestionMarkOwnership(cases)

        #expect(ownership.decoder.precision == Proportion(hits: 1, of: 2))
        #expect(ownership.decoder.recall == Proportion(hits: 1, of: 2))
        #expect(ownership.decoder.falseQuestionRate == Proportion(hits: 1, of: 2))
        #expect(ownership.rules.precision == Proportion(hits: 2, of: 2))
        #expect(ownership.rules.falseQuestionRate == Proportion(hits: 0, of: 2))
        #expect(ownership.both.recall == Proportion(hits: 1, of: 2))
        #expect(ownership.agreement == Proportion(hits: 2, of: 4))
    }

    @Test("the Wilson interval holds the share and stays inside zero to one")
    func wilsonInterval() throws {
        let all = try #require(Proportion(hits: 10, of: 10).interval)
        #expect(abs(all.upperBound - 1) < 1e-9)
        #expect(abs(all.lowerBound - 0.7225) < 0.001)
        let half = try #require(Proportion(hits: 5, of: 10).interval)
        #expect(half.contains(0.5))
        #expect(abs(half.lowerBound - 0.2366) < 0.001)
    }

    @Test("an empty share has no value and no interval, and prints as n/a")
    func emptyShare() {
        #expect(Proportion(hits: 0, of: 0).value == nil)
        #expect(Proportion(hits: 0, of: 0).interval == nil)
        #expect(QuestionMarkOwnership([]).table.contains("n/a"))
    }

    @Test("the table has a row per owner and the agreement")
    func table() {
        let table = QuestionMarkOwnership([sentence(true, decoder: true, rules: false)]).table
        #expect(table.contains("| decoder | 1.00"))
        #expect(table.contains("| rules | n/a"))
        #expect(table.contains("Agreement: 0.00"))
    }
}
