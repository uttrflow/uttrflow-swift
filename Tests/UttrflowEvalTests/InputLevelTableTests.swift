// Tests pooling word errors per input level and pairing each level against full scale.
import Testing
import UttrflowCore
import UttrflowEval

@Suite("InputLevelTable")
struct InputLevelTableTests {
    private let reference = ["move", "the", "blue", "folder", "onto", "the", "shelf", "now"]

    private func outcome(_ level: InputLevel, heard: [String], clipped: Double = 0) -> InputLevelOutcome {
        InputLevelOutcome(
            level: level, rate: .measure(reference: reference, hypothesis: heard), clippedFraction: clipped)
    }

    private func passage(clippedHeard: [String]) -> [InputLevelOutcome] {
        [
            outcome(.peak(decibels: -20), heard: reference),
            outcome(InputLevelTable.referenceLevel, heard: reference),
            outcome(.clipped(gain: 8), heard: clippedHeard, clipped: 0.15),
        ]
    }

    @Test func rowsFollowTheOrderTheLevelsFirstAppear() {
        let table = InputLevelTable(passages: [passage(clippedHeard: reference)])
        #expect(table.rows.map(\.level.description) == ["-20 dBFS", "0 dBFS", "8x clipped"])
    }

    @Test func aRowPoolsErrorsInsertionsAndClippingOverItsPassages() throws {
        let garbled = ["move", "the", "the", "blue", "folder", "on", "shelf", "now"]
        let table = InputLevelTable(passages: [
            passage(clippedHeard: garbled), passage(clippedHeard: reference),
        ])
        let clipped = try #require(table.rows.last)
        #expect(clipped.passages == 2)
        #expect(clipped.referenceWords == 16)
        #expect(clipped.insertions == 1)
        #expect(clipped.errors == 3)
        #expect(abs(clipped.wordErrorRate - 3.0 / 16) < 1e-9)
        #expect(abs(clipped.insertionRate - 1.0 / 16) < 1e-9)
        #expect(abs(clipped.meanClippedFraction - 0.15) < 1e-9)
    }

    @Test func theReferenceRowCarriesNoChange() throws {
        let table = InputLevelTable(passages: Array(repeating: passage(clippedHeard: []), count: 4))
        let full = try #require(table.rows.first { $0.level == InputLevelTable.referenceLevel })
        #expect(full.change == nil)
        #expect(!full.isMeasurablyWorse)
    }

    @Test func aLevelThatLosesWordsInEveryPassageIsMeasurablyWorse() throws {
        let table = InputLevelTable(passages: Array(repeating: passage(clippedHeard: ["move"]), count: 6))
        let clipped = try #require(table.rows.last)
        #expect(clipped.isMeasurablyWorse)
        let quiet = try #require(table.rows.first)
        #expect(!quiet.isMeasurablyWorse)
    }

    @Test func onePassageIsTooFewToCallALevelWorse() throws {
        let table = InputLevelTable(passages: [passage(clippedHeard: [])])
        let clipped = try #require(table.rows.last)
        #expect(clipped.change == nil)
        #expect(!clipped.isMeasurablyWorse)
    }

    @Test func aPassageWithoutTheReferenceLevelIsLeftOutOfThePairing() throws {
        let unpaired = [outcome(.clipped(gain: 8), heard: [])]
        let table = InputLevelTable(passages: [unpaired, unpaired])
        let clipped = try #require(table.rows.first)
        #expect(clipped.passages == 2)
        #expect(clipped.change == nil)
    }

    @Test func anEmptyRowRatesZero() {
        let empty = InputLevelOutcome(
            level: .peak(decibels: -40), rate: .measure(reference: [], hypothesis: []), clippedFraction: 0)
        let row = InputLevelTable(passages: [[empty]]).rows[0]
        #expect(row.wordErrorRate == 0)
        #expect(row.insertionRate == 0)
    }

    @Test func noPassagesMakeNoRows() {
        #expect(InputLevelTable(passages: []).rows.isEmpty)
    }
}
