// Tests capitalisation scored per class and against the do-nothing floors.
import Testing

@testable import UttrflowEval

@Suite("Capitalisation score")
struct CapitalisationScoreTests {
    private func reference(_ expected: String, spoken: String = "spoken") -> EvaluationCase {
        EvaluationCase(id: "case", category: .everyday, spoken: spoken, expected: expected)
    }

    @Test("classes each reference word by why it has its case")
    func classesWords() {
        let words = ClassifiedWord.words(of: "Then I met NASA staff at 3 p.m. Their iPhone died.\nok Paris")
        #expect(
            words.map(\.wordClass) == [
                .sentenceStart, .pronounI, .lowerCase, .acronym, .lowerCase, .lowerCase, .uncased,
                .lowerCase, .lowerCase, .sentenceStart, .innerCapital, .lowerCase, .sentenceStart,
                .capitalised,
            ])
    }

    @Test("lower-casing the mid-sentence capitals lowers exactly one class")
    func seededRegressionMovesOneClass() {
        let expected = "Yesterday I sent the NASA brief to Lisbon and the iPhone team."
        let right = Scorer.score(expected, against: reference(expected)).capitalisation
        let seeded = Scorer.score(
            "Yesterday I sent the NASA brief to lisbon and the iPhone team.", against: reference(expected)
        ).capitalisation
        let moved = CapitalisationClass.allCases.filter { right.accuracy(of: $0) != seeded.accuracy(of: $0) }
        #expect(moved == [.capitalised])
        #expect(seeded.mostDegraded(comparedWith: right) == .capitalised)
    }

    @Test("the mean keeps its old definition: the share of aligned words whose case matches")
    func meanUnchanged() {
        let score = Scorer.score("YOY increased today", against: reference("YoY increased today."))
        #expect(score.caseAccuracy == 2.0 / 3.0)
        #expect(score.capitalisation.accuracy == score.caseAccuracy)
    }

    @Test("scores the all-lower-case and recogniser floors on the same words")
    func floors() {
        let score = Scorer.score(
            "I met Lisbon.", against: reference("I met Lisbon.", spoken: "i met Lisbon"))
        #expect(score.lowerCaseBaseline.accuracy(of: .capitalised) == 0)
        #expect(score.lowerCaseBaseline.accuracy(of: .lowerCase) == 1)
        #expect(score.spokenBaseline.accuracy(of: .pronounI) == 0)
        #expect(score.spokenBaseline.accuracy(of: .capitalised) == 1)
    }

    @Test("the corpus floor gets lower-case words right and capitals wrong")
    func corpusFloor() {
        let scores = EvaluationCorpus.all.map { Scorer.score($0.expected, against: $0) }
        let lower = EvaluationReport(label: "floor", scores: scores, durations: []).lowerCaseBaseline
        #expect(lower.accuracy(of: .lowerCase) == 1)
        #expect(lower.accuracy(of: .capitalised) == 0)
    }
}
