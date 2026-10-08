// Tests the per-group calibration table the accent-calibration probe prints.
import Testing
import UttrflowEval

@Suite("GroupCalibration")
struct GroupCalibrationTests {
    static func words(_ group: String, right: [Double], wrong: [Double?]) -> [GradedWord] {
        right.map { GradedWord(group: group, score: $0, isRight: true) }
            + wrong.map { GradedWord(group: group, score: $0, isRight: false) }
    }

    @Test func splitsErrorsIntoSeenAndConfidentAndCountsDoubtedRightWords() throws {
        let rows = GroupCalibration.rows(
            Self.words("en-IN", right: [0.9, 0.95, 0.4, 0.5], wrong: [0.3, 0.7, nil]), threshold: 0.5)
        let row = try #require(rows.first)
        #expect(row.words == 7)
        #expect(row.errors == 3)
        #expect(row.seen.count == 1)
        #expect(row.confident.count == 1)
        #expect(row.seen.total == 3)
        #expect(row.falselyDoubted == GroupCalibration.Share(count: 1, total: 4))
    }

    @Test func binsEveryScoredWordOnceWithAScoreOfOneInTheLastBin() {
        let row = GroupCalibration.rows(
            Self.words("g", right: [0.1, 0.45, 1.0, 0.95], wrong: [0.85, nil]), threshold: 0.5)[0]
        #expect(row.bins.map(\.words).reduce(0, +) == 5)
        #expect(row.bins.last == GroupCalibration.Bin(upper: 1.0, words: 2, right: 2))
        #expect(row.bins.first == GroupCalibration.Bin(upper: 0.2, words: 1, right: 1))
    }

    @Test func wilsonIntervalHoldsTheShareAndNarrowsWithMoreWords() {
        let small = GroupCalibration.Share(count: 2, total: 10).interval
        let large = GroupCalibration.Share(count: 200, total: 1000).interval
        #expect(small.contains(0.2) && large.contains(0.2))
        #expect(large.upperBound - large.lowerBound < small.upperBound - small.lowerBound)
        #expect(GroupCalibration.Share(count: 0, total: 0).interval == 0...1)
    }

    @Test func aGroupStandsApartOnlyWhenTheIntervalsSeparate() {
        let best = Self.words(
            "best", right: [], wrong: Array(repeating: 0.2, count: 90) + Array(repeating: 0.9, count: 10))
        let apart = Self.words(
            "apart", right: [], wrong: Array(repeating: 0.2, count: 30) + Array(repeating: 0.9, count: 70))
        let close = Self.words(
            "close", right: [], wrong: Array(repeating: 0.2, count: 85) + Array(repeating: 0.9, count: 15))
        let rows = GroupCalibration.rows(best + apart + close, threshold: 0.5)
        #expect(GroupCalibration.standingApart(rows).map(\.group) == ["apart"])
    }

    @Test func markdownHasOneRowPerGroupInEachTable() {
        let rows = GroupCalibration.rows(
            Self.words("a", right: [0.9], wrong: [0.3]) + Self.words("b", right: [0.8], wrong: [0.9]),
            threshold: 0.5)
        let text = GroupCalibration.markdown(rows)
        #expect(text.components(separatedBy: "\n| a |").count == 3)
        #expect(text.components(separatedBy: "\n| b |").count == 3)
        #expect(text.contains("50.0%") || text.contains("100.0%"))
    }
}
