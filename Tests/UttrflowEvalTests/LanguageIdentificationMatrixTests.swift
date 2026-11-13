import Testing
import UttrflowEval

@Suite("Language identification scored by clip length")
struct LanguageIdentificationMatrixTests {
    private func clip(
        _ detected: String?, _ probability: Double? = 0.9, group: String = "hi", expected: String = "hi",
        seconds: Double = 0.5
    ) -> LanguageIdentification {
        LanguageIdentification(
            group: group, expected: expected, detected: detected, probability: probability, seconds: seconds)
    }

    @Test(
        "A clip falls in its length bucket, each boundary in the longer one except five seconds",
        arguments: [
            (0.0, ClipLengthBucket.underOne), (0.99, .underOne), (1.0, .oneToTwo), (1.99, .oneToTwo),
            (2.0, .twoToFive), (5.0, .twoToFive), (5.01, .overFive),
        ])
    func bucketsByLength(seconds: Double, bucket: ClipLengthBucket) {
        #expect(ClipLengthBucket(seconds: seconds) == bucket)
    }

    @Test("A cell counts its misses, and a clip with no detection is a miss")
    func countsMisses() throws {
        let matrix = LanguageIdentificationMatrix([
            clip("hi"), clip("en", 0.6), clip(nil, nil), clip("hi", 0.7),
        ])
        let cell = try #require(matrix.cells.first)
        #expect(matrix.cells.count == 1)
        #expect(cell.clips == 4 && cell.wrong == 2)
        #expect(cell.errorRate == 0.5)
        #expect(cell.detected == ["hi": 2, "en": 1, "none": 1])
    }

    @Test("A mean probability counts only the clips that reported one")
    func meanProbabilityIgnoresUnreported() throws {
        let matrix = LanguageIdentificationMatrix([
            clip("hi", 0.8), clip("hi", 0.6), clip("hi", nil), clip(nil, nil),
        ])
        let cell = try #require(matrix.cells.first)
        #expect(abs((cell.meanProbability["hi"] ?? 0) - 0.7) < 1e-9)
        #expect(cell.meanProbability["none"] == nil)
    }

    @Test("Groups keep their first-seen order, and buckets follow length within each group")
    func ordersCells() {
        let matrix = LanguageIdentificationMatrix([
            clip("en", group: "en, en-IN voice", expected: "en", seconds: 3), clip("hi", seconds: 6),
            clip("hi", seconds: 0.4),
            clip("en", group: "en, en-IN voice", expected: "en", seconds: 0.2),
        ])
        #expect(matrix.cells.map(\.group) == ["en, en-IN voice", "en, en-IN voice", "hi", "hi"])
        #expect(matrix.cells.map(\.bucket) == [.underOne, .twoToFive, .underOne, .overFive])
    }

    @Test("Only a cell above the five per cent limit is reported on its own")
    func reportsCellsOverTheLimit() {
        let right = (0..<19).map { _ in clip("hi", seconds: 3) }
        let atLimit = LanguageIdentificationMatrix(right + [clip("en", seconds: 3)])
        #expect(atLimit.cellsOverLimit.isEmpty)
        let over = LanguageIdentificationMatrix(Array(right.prefix(9)) + [clip("en", seconds: 3)])
        #expect(over.cellsOverLimit.map(\.bucket) == [.twoToFive])
    }

    @Test("The table has one row per cell, naming each detected language with its count and mean")
    func rendersMarkdown() {
        let table = LanguageIdentificationMatrix([clip("hi", 0.9), clip("en", 0.5), clip(nil, nil)]).markdown
        let rows = table.split(separator: "\n")
        #expect(rows.count == 3)
        #expect(rows[2] == "| hi | under 1 s | 3 | 2 | 66.7% | en (1, 0.50), hi (1, 0.90), none (1, n/a) |")
    }

    @Test("No clips make no cells and a table with only its header")
    func emptyInput() {
        let matrix = LanguageIdentificationMatrix([])
        #expect(matrix.cells.isEmpty && matrix.cellsOverLimit.isEmpty)
        #expect(matrix.markdown.split(separator: "\n").count == 2)
    }
}
