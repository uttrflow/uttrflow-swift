// Tests the budgeted recall and precision the doubtful-word strip is decided on.
import Testing
import UttrflowEval

@Suite("DoubtStripFloor")
struct DoubtStripFloorTests {
    static func words(right: Int, rightScore: Double, wrong: [Double?]) -> [GradedWord] {
        Array(repeating: GradedWord(group: "g", score: rightScore, isRight: true), count: right)
            + wrong.map { GradedWord(group: "g", score: $0, isRight: false) }
    }

    @Test func flagsOnlyTheLowestScoredWordsWithinTheBudget() {
        let words = Self.words(right: 96, rightScore: 0.9, wrong: [0.1, 0.2, 0.3, 0.95])
        let result = DoubtStripFloor.evaluate(words)
        #expect(result.flags == 3)
        #expect(result.recall.count == 3)
        #expect(result.recall.total == 4)
        #expect(result.precision.value == 1)
        #expect(result.clears)
    }

    @Test func confidentErrorsAndDroppedWordsFailTheRecallFloor() {
        let words = Self.words(right: 96, rightScore: 0.5, wrong: [0.97, 0.98, nil, nil])
        let result = DoubtStripFloor.evaluate(words)
        #expect(result.recall.count == 0)
        #expect(result.unflaggable.count == 2)
        #expect(!result.clears)
        #expect(DoubtStripFloor.summary(result).hasSuffix("does not clear"))
    }

    @Test func fewerThanOneHundredWordsAllowNoFlag() {
        let result = DoubtStripFloor.evaluate(Self.words(right: 20, rightScore: 0.9, wrong: [0.1]))
        #expect(result.flags == 0)
        #expect(!result.clears)
    }
}
