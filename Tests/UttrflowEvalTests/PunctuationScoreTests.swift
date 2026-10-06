// Tests punctuation scored per mark over aligned words.
import Testing

@testable import UttrflowEval

@Suite("Mark score")
struct MarkScoreTests {
    @Test("a question ending in a full stop is a substitution, not a match")
    func questionWrittenAsStatement() {
        let tally = PunctuationTally.measure("Are you coming.", against: "Are you coming?")
        #expect(tally.substitutions[.question]?[.fullStop] == 1)
        #expect(tally.f1(of: .question) == 0)
        #expect(tally.f1(of: .fullStop) == 0)
        #expect(tally.accuracy == 0)
    }

    @Test("a dropped word moves no other mark's score")
    func droppedWordKeepsLaterMarks() {
        let tally = PunctuationTally.measure(
            "Yes, I come tomorrow: bring the notes; then lunch.",
            against: "Yes, I will come tomorrow: bring the notes; then lunch.")
        #expect(tally.accuracy == 1)
        #expect(tally.substitutions.isEmpty)
    }

    @Test("an inserted word moves no other mark's score")
    func insertedWordKeepsLaterMarks() {
        let tally = PunctuationTally.measure("Well, so we left, finally.", against: "Well, we left, finally.")
        #expect(tally.accuracy == 1)
    }

    @Test("each mark is scored on its own")
    func marksScoredSeparately() {
        let tally = PunctuationTally.measure("Wait now. Really!", against: "Wait, now. Really?")
        #expect(tally.f1(of: .comma) == 0)
        #expect(tally.f1(of: .fullStop) == 1)
        #expect(tally.recall(of: .comma) == 0)
        #expect(tally.precision(of: .comma) == nil)
        #expect(tally.substitutions[.question]?[.exclamation] == 1)
        #expect(tally.f1(of: .colon) == nil)
    }

    @Test("ellipses, dashes, quotes and brackets are classed, and word-internal marks are not")
    func classesEveryMark() {
        let tally = PunctuationTally.measure(
            "So... the well-known \"plan\" (again) — don't.",
            against: "So… the well-known “plan” (again) - don't.")
        for mark in [MarkClass.ellipsis, .dash, .quote, .bracket, .fullStop] {
            #expect(tally.f1(of: mark) == 1, "\(mark)")
        }
        #expect(tally.wanted[.dash] == 1)
        #expect(tally.wanted[.quote] == 2)
    }

    @Test("texts without marks agree perfectly and tallies add")
    func emptyAndSum() {
        #expect(PunctuationTally.measure("hello there", against: "hello there").accuracy == 1)
        let sum =
            PunctuationTally.measure("a, b.", against: "a, b.")
            + PunctuationTally.measure("a b", against: "a, b")
        #expect(sum.wanted[.comma] == 2)
        #expect(sum.correct[.comma] == 1)
        #expect(sum.recall(of: .comma) == 0.5)
    }
}
