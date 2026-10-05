import Testing
@testable import uttrflow_bakeoff

struct SpeechShapeTests {
    @Test("a sound, a restart and marks are each counted in their own class")
    func countsEachClass() async {
        let stats = await SpeechShapeStatistics.measure([
            "um the bus was late.", "send it to Tom, no wait to Ana", "",
        ])
        #expect(stats.lines == 2)
        #expect(stats.words == 13)
        #expect(stats.disfluent["sound"] == 1)
        #expect((stats.disfluent["retraction"] ?? 0) > 0)
        #expect(stats.linesWithRestart == 1)
        #expect(stats.marks["."] == 1)
        #expect(stats.marks[","] == 1)
        #expect(stats.sentences == 2)
    }

    @Test("an empty set reports zero rates rather than dividing by zero")
    func emptyIsZero() async {
        let stats = await SpeechShapeStatistics.measure([])
        #expect(stats.rows.allSatisfy { $0.1 == 0 })
    }

    @Test("a line's unfinished tail counts as one more sentence")
    func sentenceTail() {
        #expect(SpeechShapeStatistics.sentenceCount(["a.", "b"]) == 2)
        #expect(SpeechShapeStatistics.sentenceCount(["a", "b?"]) == 1)
    }
}
