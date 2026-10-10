// Tests the per-seam count of stops, capitals and words that joining pieces changed.
import Testing
import UttrflowEval

@Suite("SeamScore")
struct SeamScoreTests {
    @Test func aCleanJoinScoresNothing() {
        let score = SeamScore(
            whole: "We can ship it today, I think.", pieces: ["We can ship it", "today, I think."])
        #expect(score.seams.count == 1)
        #expect(score.total.total == 0)
    }

    @Test func aStopAndCapitalAfterAMidClauseCutAreCounted() {
        let score = SeamScore(
            whole: "We can ship it without any delay.", pieces: ["We can ship it without any.", "Delay."])
        #expect(score.seams == [tally(strayStops: 1, wrongCapitals: 1)])
    }

    @Test func aWordWrittenByBothPiecesIsDuplicated() {
        let score = SeamScore(whole: "send the report now", pieces: ["send the report", "report now"])
        #expect(score.total.duplicated == 1)
        #expect(score.total.dropped == 0)
    }

    @Test func aWordNeitherPieceWroteIsDropped() {
        let score = SeamScore(whole: "send the final report now", pieces: ["send the", "report now"])
        #expect(score.total.dropped == 1)
        #expect(score.total.duplicated == 0)
    }

    @Test func anErrorAwayFromTheSeamIsNotTheSeams() {
        let score = SeamScore(
            whole: "please send the final report now", pieces: ["please the final", "report now"])
        #expect(score.total.total == 0)
    }

    @Test func eachSeamIsTalliedOnItsOwn() {
        let score = SeamScore(
            whole: "one two three four five six", pieces: ["one two.", "Three four", "five six"])
        #expect(score.seams == [tally(strayStops: 1, wrongCapitals: 1), SeamTally()])
    }

    @Test func oneUnbrokenClipHasNoSeam() {
        #expect(SeamScore(whole: "one two", pieces: ["one two"]).seams.isEmpty)
    }

    @Test func aJoinedTextIsScoredWhereItsPiecesMet() {
        let score = SeamScore(
            whole: "We can ship it without any delay.", written: "We can ship it without any. Delay.",
            pieces: ["we can ship it without any", "delay"])
        #expect(score.seams == [tally(strayStops: 1, wrongCapitals: 1)])
    }

    @Test func aJoinThatWritesTheWholeScoresNothing() {
        let score = SeamScore(
            whole: "We can ship it today, I think.", written: "We can ship it today, I think.",
            pieces: ["We can ship it.", "Today, I think."])
        #expect(score.seams.count == 1)
        #expect(score.total.total == 0)
    }

    @Test func aPieceWordTheJoinDroppedKeepsTheSeamOnTheNextWord() {
        let score = SeamScore(
            whole: "send the report now", written: "send the report. Now",
            pieces: ["send the report um", "now"])
        #expect(score.seams == [tally(strayStops: 1, wrongCapitals: 1)])
    }

    private func tally(strayStops: Int = 0, wrongCapitals: Int = 0) -> SeamTally {
        var tally = SeamTally()
        tally.strayStops = strayStops
        tally.wrongCapitals = wrongCapitals
        return tally
    }
}
