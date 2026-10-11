import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

/// Synthetic errors may join a fit only when they look like the errors the recogniser really makes.
@Suite("Synthetic errors")
struct SyntheticErrorsTests {
    private let provenance = HarvestProvenance(
        dataset: "example", version: "1", licence: "CC0", engine: "test", seed: 1)

    private var table: ConfusionTable {
        func line(_ reference: String, _ recognised: String, times: Int) -> [HarvestUtterance] {
            (0..<times).map {
                HarvestUtterance(
                    reference: [reference], recognised: [recognised], group: "hi", speaker: "s\($0)")
            }
        }
        let utterances =
            line("vest", "west", times: 6) + line("think", "tink", times: 3) + line("long", "wrong", times: 2)
            + line("light", "right", times: 1)
        return ConfusionHarvest.table(utterances, provenance: provenance, minimumSpeakers: 1)
    }

    /// Real spans with all four kinds, one to two words, and confidences spread over the unit interval.
    private var real: [ErrorSpan] {
        (0..<120).map { index in
            let kind = ErrorSpanKind.allCases[index % 4]
            return ErrorSpan(
                kind: kind, spanClass: index % 10 == 0 ? .name : .commonWord,
                referenceWords: kind == .merge ? 2 : 1, editDistance: Self.edits(kind, index),
                confidence: Double(index % 17) / 17, features: [Double(index % 17) / 17, Double(index % 5)])
        }
    }

    private static func edits(_ kind: ErrorSpanKind, _ index: Int) -> Int {
        switch kind {
        case .drop: (index / 4) % 3 == 0 ? 5 : 4
        case .substitution: (index / 4) % 6 == 0 ? 2 : 1
        case .split, .merge: 1
        }
    }

    private func generated(seed: UInt64 = 7, count: Int = 400) -> [ErrorSpan] {
        SyntheticErrorGenerator(table: table, real: real, names: ["light"], seed: seed).generate(count: count)
    }

    @Test("The same seed gives the same errors and another seed gives others")
    func seeded() {
        #expect(generated() == generated())
        #expect(generated(seed: 8) != generated())
    }

    @Test("Every kind is drawn and each carries the length and edits its shape implies")
    func kindsAndShapes() {
        let spans = generated()
        #expect(Set(spans.map(\.kind)) == Set(ErrorSpanKind.allCases))
        #expect(spans.filter { $0.kind == .merge }.allSatisfy { $0.referenceWords == 2 })
        #expect(spans.filter { $0.kind != .merge }.allSatisfy { $0.referenceWords == 1 })
        #expect(spans.filter { $0.kind == .split }.allSatisfy { $0.editDistance == 1 })
        #expect(spans.allSatisfy { $0.editDistance >= 1 })
    }

    @Test("Substitution pairs are drawn in proportion to their counts")
    func weightedByCounts() {
        let only = real.filter { $0.kind == .substitution }
        let spans = SyntheticErrorGenerator(table: table, real: only, seed: 3).generate(count: 1200)
        let single = spans.filter { $0.editDistance == 2 }.count
        // "long" to "wrong" is two edits and holds 2 of the 12 counts; every other pair is one edit.
        #expect(abs(Double(single) / 1200 - 2.0 / 12) < 0.04)
    }

    @Test("Evidence is a real span's own vector, drawn from spans of the same kind and class")
    func evidenceIsDonated() {
        let donors = Set(real.map(\.features))
        #expect(generated().allSatisfy { donors.contains($0.features) })
    }

    @Test("Nothing is generated without a table or without real spans")
    func emptyInputs() {
        #expect(SyntheticErrorGenerator(table: table, real: [], seed: 1).generate(count: 5).isEmpty)
        #expect(SyntheticErrorGenerator(table: table, real: real, seed: 1).generate(count: 0).isEmpty)
        let empty = ConfusionHarvest.table([], provenance: provenance, minimumSpeakers: 1)
        #expect(SyntheticErrorGenerator(table: empty, real: real, seed: 1).generate(count: 5).isEmpty)
    }

    @Test("A generator that follows the table passes the realism report")
    func realisticPasses() {
        let report = RealismReport(real: real, synthetic: generated(), bounds: RealismBounds())
        #expect(report.passes, "\(report.lines)")
        #expect(report.measures.map(\.name) == ["length", "edit distance", "confidence", "class mix"])
    }

    @Test("A generator whose errors are all one word long with a fixed confidence fails the report")
    func unrealisticFails() {
        let flat = (0..<400).map { _ in
            ErrorSpan(
                kind: .substitution, spanClass: .commonWord, referenceWords: 1, editDistance: 1,
                confidence: 0.5, features: [0.5, 0])
        }
        let report = RealismReport(real: real, synthetic: flat, bounds: RealismBounds())
        #expect(!report.passes)
        let failed = Set(report.measures.filter { !$0.passes }.map(\.name))
        #expect(failed.isSuperset(of: ["length", "confidence"]))
        #expect(report.lines.contains { $0.contains("confidence") && $0.contains("fails") })
    }

    @Test("Nothing to compare fails rather than passes")
    func emptyFails() {
        #expect(!RealismReport(real: real, synthetic: [], bounds: RealismBounds()).passes)
        #expect(!RealismReport(real: [], synthetic: real, bounds: RealismBounds()).passes)
    }

    @Test("Classes read a name, a number or a common word from the reference")
    func classes() {
        #expect(ErrorSpanClass(reference: ["Utter"], names: ["utter"]) == .name)
        #expect(ErrorSpanClass(reference: ["forty", "two"], names: []) == .number)
        #expect(ErrorSpanClass(reference: ["room", "7"], names: []) == .number)
        #expect(ErrorSpanClass(reference: ["vest"], names: ["utter"]) == .commonWord)
    }

    private func fitTable() -> FitTable {
        let development = (0..<40).map {
            FitTableRow(
                ordinal: $0, split: .development, language: .english, label: $0 % 2 == 0 ? .right : .wrong,
                features: [Double($0 % 2), 0.5])
        }
        let heldOut = FitTableRow(
            ordinal: 40, split: .heldout, language: .english, label: .wrong, features: [1, 0.5])
        return FitTable(featureSpecVersion: 1, rows: development + [heldOut])
    }

    @Test("A realistic mix fits on development rows only and records its cap and bounds")
    func mixAccepted() throws {
        let spans = Array(generated().prefix(20))
        let table = fitTable()
        let rows = SyntheticMix.rows(spans, after: table, language: .english)
        #expect(rows.allSatisfy { $0.split == .development && $0.label == .wrong })
        #expect(rows.first?.ordinal == 41)
        let result = try SyntheticMix.fit(
            table: table, synthetic: rows, realSpans: real, syntheticSpans: generated())
        #expect(result.developmentRows == 60)
        #expect(result.syntheticRows == 20)
        #expect(abs(result.syntheticShare - 20.0 / 60) < 1e-9)
        #expect(result.lines.first?.hasPrefix("realism over") == true)
        #expect(result.lines.contains { $0.contains("cap 0.500") })
        #expect(result.lines.contains { $0.hasPrefix("bounds: length 0.200") })
    }

    @Test("An unrealistic mix is refused with the report")
    func mixUnrealistic() {
        let table = fitTable()
        let flat = (0..<20).map { _ in
            ErrorSpan(
                kind: .substitution, spanClass: .commonWord, referenceWords: 1, editDistance: 1,
                confidence: 0.5, features: [0.5, 0])
        }
        let rows = SyntheticMix.rows(flat, after: table, language: .english)
        #expect(throws: SyntheticMix.Refusal.self) {
            try SyntheticMix.fit(table: table, synthetic: rows, realSpans: real, syntheticSpans: flat)
        }
    }

    @Test("More synthetic rows than the cap allows are refused")
    func mixOverCap() {
        let table = fitTable()
        let rows = SyntheticMix.rows(generated(count: 41), after: table, language: .english)
        #expect(throws: SyntheticMix.Refusal.overCap(share: 41.0 / 81, maximum: 0.5)) {
            try SyntheticMix.fit(table: table, synthetic: rows, realSpans: real, syntheticSpans: generated())
        }
    }

    @Test("A synthetic row on the held-out side is refused")
    func mixOnTestSide() {
        let table = fitTable()
        let stray = FitTableRow(
            ordinal: 99, split: .heldout, language: .english, label: .wrong, features: [1, 0.5])
        #expect(throws: SyntheticMix.Refusal.onTestSide(count: 1)) {
            try SyntheticMix.fit(
                table: table, synthetic: [stray], realSpans: real, syntheticSpans: generated())
        }
    }
}
