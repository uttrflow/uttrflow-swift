// Tests how dropped reference words are placed, classed and matched to uncovered voiced runs.
import Testing
import UttrflowEval

@Suite("OmissionCoverage")
struct OmissionCoverageTests {
    private let words = [
        TimedWord(text: "i", start: 0.0, end: 0.2),
        TimedWord(text: "do", start: 0.2, end: 0.4),
        TimedWord(text: "want", start: 0.8, end: 1.0),
        TimedWord(text: "it", start: 1.0, end: 1.2),
    ]

    @Test func aDroppedNegatorSitsBetweenItsRecognisedNeighbours() {
        let omissions = OmissionCoverage.omissions(
            reference: ["i", "do", "not", "want", "it"], hypothesis: words, clip: TimeSpan(start: 0, end: 1.2)
        )
        #expect(omissions == [Omission(word: "not", kind: .negator, window: TimeSpan(start: 0.4, end: 0.8))])
    }

    @Test func classesAreReadFromTheWordInItsSentence() {
        let sentence = [
            "she", "doesn't", "want", "an", "apple", "she", "was", "given", "42", "seven", "times",
        ]
        #expect(OmissionClass(at: 1, in: sentence) == .negator)
        #expect(OmissionClass(at: 3, in: sentence) == .article)
        #expect(OmissionClass(at: 6, in: sentence) == .auxiliary)
        #expect(OmissionClass(at: 8, in: sentence) == .number)
        #expect(OmissionClass(at: 9, in: sentence) == .number)
        #expect(OmissionClass(at: 4, in: sentence) == .other)
    }

    @Test func uncoveredRunsAreTheVoicedGapsAtLeastTheMinimum() {
        let runs = OmissionCoverage.uncoveredRuns(
            voiced: TimeSpan(start: 0, end: 1.5), words: words, minimum: 0.25)
        #expect(runs == [TimeSpan(start: 0.4, end: 0.8), TimeSpan(start: 1.2, end: 1.5)])
        #expect(
            OmissionCoverage.uncoveredRuns(voiced: TimeSpan(start: 0, end: 1.5), words: words, minimum: 0.5)
                .isEmpty)
    }

    @Test func aRunNearADeletionIsFoundAndAStrayRunIsAFalseAlarm() throws {
        let clip = OmissionCoverage.Clip(
            reference: ["i", "do", "not", "want", "it"], words: words, voiced: TimeSpan(start: 0, end: 1.5))
        let tally = OmissionCoverage.tally([clip], minimum: 0.25, tolerance: 0.05)
        let all = try #require(tally[nil])
        #expect(all.deletions == 1)
        #expect(all.found == 1)
        #expect(all.runs == 2)
        #expect(all.runsNearDeletion == 1)
        #expect(all.precision == 0.5)
        #expect(all.recall == 1)
        #expect(all.falseAlarmsPer100Words == 20)
        #expect(tally[.negator]?.found == 1)
        #expect(OmissionCoverage.isGo([all]))
    }

    @Test func aCleanDecodeHasNoDeletionsAndIsNoGo() throws {
        let clip = OmissionCoverage.Clip(
            reference: ["i", "do", "want", "it"], words: words, voiced: TimeSpan(start: 0, end: 1.2))
        let all = try #require(OmissionCoverage.tally([clip], minimum: 0.3, tolerance: 0.05)[nil])
        #expect(all.deletions == 0)
        #expect(all.recall == nil)
        #expect(!OmissionCoverage.isGo([all]))
    }
}
