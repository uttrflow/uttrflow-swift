// The staleness check over a chain of calibrations, against hand-written layers.
import Testing
import UttrflowCore

struct CalibrationGraphTests {
    typealias Layer = CalibrationRecord.Layer

    static func record(
        _ layer: Layer, _ value: String, under fittedUnder: [Layer: String]
    ) -> CalibrationRecord {
        CalibrationRecord(
            layer: layer, value: value, corpus: "fixture", metric: "fixture", fittedUnder: fittedUnder)
    }

    static let chain = [
        record(.overrideMargin, "2", under: [.certaintyThreshold: "0.5"]),
        record(.certaintyThreshold, "0.5", under: [.recogniser: "r1", .fallbackPlan: "5"]),
        record(.fallbackPlan, "5", under: [.recogniser: "r1", .phraseBias: "0.0"]),
    ]

    static let live: [Layer: String] = [
        .recogniser: "r1", .phraseBias: "0.0", .fallbackPlan: "5", .certaintyThreshold: "0.5",
        .overrideMargin: "2",
    ]

    @Test func aChainFittedUnderTheLiveLayersHasNoFinding() {
        #expect(CalibrationGraph.findings(Self.chain, live: Self.live).isEmpty)
        #expect(CalibrationGraph.findings([], live: [:]).isEmpty)
    }

    @Test func aMovedLayerStalesEveryCalibrationAboveItInFitOrder() {
        var live = Self.live
        live[.phraseBias] = "1.0"
        #expect(
            CalibrationGraph.findings(Self.chain, live: live) == [
                .upstreamMoved(.fallbackPlan, upstream: .phraseBias, recorded: "0.0", live: "1.0"),
                .upstreamStale(.certaintyThreshold, upstream: .fallbackPlan),
                .upstreamStale(.overrideMargin, upstream: .certaintyThreshold),
            ])
    }

    @Test func aChangedValueIsStaleUntilRecordedAgain() {
        var live = Self.live
        live[.certaintyThreshold] = "0.6"
        #expect(
            CalibrationGraph.findings(Self.chain, live: live) == [
                .valueMoved(.certaintyThreshold, recorded: "0.5", live: "0.6"),
                .upstreamMoved(.overrideMargin, upstream: .certaintyThreshold, recorded: "0.5", live: "0.6"),
            ])
    }

    @Test func aLayerWithNoLiveRevisionCountsAsMoved() {
        var live = Self.live
        live[.recogniser] = nil
        live[.overrideMargin] = nil
        let found = CalibrationGraph.findings([Self.chain[0], Self.chain[2]], live: live)
        #expect(
            found == [
                .upstreamMoved(.fallbackPlan, upstream: .recogniser, recorded: "r1", live: nil),
                .valueMoved(.overrideMargin, recorded: "2", live: nil),
            ])
    }

    @Test func aRecordReadingALaterLayerIsOutOfOrder() {
        let backwards = Self.record(.fallbackPlan, "5", under: [.fallbackPlan: "5", .overrideMargin: "2"])
        #expect(
            CalibrationGraph.findings([backwards], live: Self.live) == [
                .fittedOutOfOrder(.fallbackPlan, upstream: .fallbackPlan),
                .fittedOutOfOrder(.fallbackPlan, upstream: .overrideMargin),
            ])
    }

    @Test func layersCompareInFitOrder() {
        #expect(Layer.allCases == Layer.allCases.sorted())
        #expect(Layer.recogniser < Layer.overrideMargin)
    }
}
