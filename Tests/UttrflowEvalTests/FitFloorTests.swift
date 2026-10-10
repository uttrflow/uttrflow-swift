import Foundation
import Testing

@testable import UttrflowEval

/// A fit refuses a table below its layer's data floor, and the floors and yield the docs state are the ones the code holds.
@Suite("Fit floor")
struct FitFloorTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static func grouped(_ count: Int) -> String {
        count.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    /// A table with `wrong` and `right` rows in every split-and-language cell, over `features` features.
    static func table(wrong: Int, right: Int, features: Int = 3) -> FitTable {
        var rows: [FitTableRow] = []
        for split in CorpusSplit.allCases {
            for language in TranscriptionCase.Language.allCases {
                for index in 0..<(wrong + right) {
                    rows.append(
                        FitTableRow(
                            ordinal: rows.count, split: split, language: language,
                            label: index < wrong ? .wrong : .right,
                            features: Array(repeating: Double(index % 7) / 7, count: features)))
                }
            }
        }
        return FitTable(featureSpecVersion: 1, rows: rows)
    }

    @Test(
        "The committed invented table is below the reranker floor, and each short cell is named with its count"
    )
    func inventedTableRefused() throws {
        let table = try FitTable.read(Data(contentsOf: FitTableTests.url))
        let shortfalls = table.shortfalls(for: .spanReranker)
        #expect(
            shortfalls.map(\.description) == [
                "wrong rows in development english: 27, needs 30 (3 short)",
                "wrong rows in development hindi: 28, needs 30 (2 short)",
                "wrong rows in heldout english: 8, needs 30 (22 short)",
                "wrong rows in heldout hindi: 9, needs 30 (21 short)",
                "wrong rows in heldout hinglish: 8, needs 30 (22 short)",
            ])
    }

    @Test("A table that meets every count of the reranker floor has no shortfall")
    func floorMet() {
        #expect(Self.table(wrong: 30, right: 30).shortfalls(for: .spanReranker).isEmpty)
        #expect(Self.table(wrong: 29, right: 30).shortfalls(for: .spanReranker).count == 6)
    }

    @Test("Too few development rows for the parameters is a shortfall of its own")
    func perParameter() {
        let shortfalls = Self.table(wrong: 30, right: 0, features: 9).shortfalls(for: .spanReranker)
        #expect(shortfalls == [FloorShortfall(count: .developmentRows(parameters: 10), have: 90, need: 100)])
        #expect(
            shortfalls.first?.description == "development rows for 10 parameters: 90, needs 100 (10 short)")
    }

    @Test("A floor on rows of either label counts both labels in each cell")
    func rowsPerCell() {
        let shortfalls = Self.table(wrong: 30, right: 200).shortfalls(for: .overrideGate)
        #expect(shortfalls.count == CorpusSplit.allCases.count * TranscriptionCase.Language.allCases.count)
        #expect(
            shortfalls.first
                == FloorShortfall(count: .rows(split: .development, language: .english), have: 230, need: 300)
        )
        #expect(shortfalls.first?.description == "rows in development english: 230, needs 300 (70 short)")
        #expect(Self.table(wrong: 30, right: 270).shortfalls(for: .overrideGate).isEmpty)
    }

    @Test("Each layer counts its parameters from the floor's own shape")
    func parameterCounts() {
        let counts = FittedLayer.allCases.map { $0.floor.parameters(featureCount: 4) }
        #expect(counts == [5, 15, 0, 0, 2, 1])
    }

    @Test("Docs/dictation-quality.md states every fitted layer's floor as the code holds it")
    func documented() throws {
        let page = try String(
            contentsOf: Self.root.appending(path: "Docs/dictation-quality.md"), encoding: .utf8)
        for layer in FittedLayer.allCases {
            let floor = layer.floor
            let row =
                "| `\(layer.rawValue)` | \(floor.unit.rawValue) | \(floor.rowsPerParameter) | "
                + "\(Self.grouped(floor.wrongPerCell)) | \(Self.grouped(floor.rowsPerCell)) |"
            #expect(page.contains(row), "missing: \(row)")
        }
    }

    @Test("The committed baseline's yield is the one the docs record")
    func baselineYield() throws {
        let baseline = try AccuracyBaseline.read(
            from: Self.root.appending(path: "Scripts/accuracy_baseline.json"))
        let yields = LabelYield.measure(baseline)
        #expect(yields.map(\.language) == [.english])
        let english = try #require(yields.first)
        #expect(english.errors == 11)
        #expect(english.words == 305)
        #expect(abs(english.perThousandWords - 36.07) < 0.01)
        let interval = try #require(english.interval)
        #expect(abs(interval.lowerBound * 1_000 - 6.90) < 0.01)
        #expect(abs(interval.upperBound * 1_000 - 71.21) < 0.01)
        let minutes = try #require(english.minutesOfReading(toCollect: 60))
        #expect(abs(minutes - 13.86) < 0.01)
    }

    @Test("A baseline with no errors yields no reading cost, and an empty one no yield")
    func noErrors() {
        let clean = LabelYield(language: .hindi, errors: 0, words: 100, interval: nil)
        #expect(clean.minutesOfReading(toCollect: 30) == nil)
        #expect(clean.perThousandWords == 0)
        #expect(LabelYield(language: .hindi, errors: 0, words: 0, interval: nil).perThousandWords == 0)
    }
}
