import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline
import UttrflowTestSupport

@testable import UttrflowEval

/// Every degraded path keeps the corpus above the floor, and the page matches what the paths write.
@Suite("The degraded-path matrix")
struct DegradedPathMatrixTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/degraded-path-matrix.md")

    /// The pipeline with no recogniser, screen or field behind it, on a clock that never runs a stage out of time.
    static let building: DegradedPathMatrix.Building = { layers, corrector, cleaner in
        DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: cleaner,
            context: FakeContextEngine(), inserter: FakeTextInserter(), corrector: corrector,
            clock: ManualClock(), layers: layers)
    }

    static let rules = TransformerRouter(
        engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock(),
        rulesAlone: .shortReplies)

    static let matrix = Task { await DegradedPathMatrix.measure(cleaner: rules, building: building) }

    @Test("runs each default-on layer off alone and with each layer it reads, once each")
    func pathsCoverEveryLayerAndPair() {
        let paths = QualityLayers.degradedPaths
        #expect(Set(paths).count == paths.count)
        for layer in QualityLayer.allCases where layer.defaultOn {
            #expect(paths.contains([layer]))
            for input in layer.inputs where input.defaultOn {
                #expect(paths.contains { Set($0) == [layer, input] })
            }
        }
        #expect(paths.allSatisfy { $0.allSatisfy(\.defaultOn) })
    }

    @Test("keeps every case above the floor on every degraded path")
    func everyPathKeepsTheFloor() async {
        let matrix = await Self.matrix.value
        #expect(matrix.rows.count == QualityLayers.degradedPaths.count + 1)
        for row in matrix.rows {
            #expect(row.cases == EvaluationCorpus.all.count)
            #expect(row.belowFloor.isEmpty, "\(row.name) is below the floor on \(row.belowFloor)")
        }
    }

    @Test("counts a floor failure only where neither the default set nor the words as heard have it")
    func floorIsRelativeToBothBounds() {
        let testCase = EvaluationCase(
            id: "floor", category: .everyday, spoken: "um send it", expected: "Send it.", mustNotAdd: ["um"])
        let heard = Scorer.score(testCase.spoken, against: testCase)
        let invents = Scorer.score("Send it, uh, um.", against: testCase)
        let floor = DegradedPathMatrix.floorFailures(heard)
        #expect(floor.contains("invented um"))
        #expect(DegradedPathMatrix.floorFailures(invents).subtracting(floor).isEmpty)
        let drops = Scorer.score("Send.", against: testCase)
        #expect(DegradedPathMatrix.floorFailures(drops).subtracting(floor) == ["deleted it"])
    }

    @Test("keeps a term only in the entry's own case and as whole words")
    func termsAreCaseAndWordExact() {
        #expect(
            DegradedPathMatrix.writes(
                "Harbour Street Credit Union", in: "Pay Harbour Street Credit Union today."))
        #expect(!DegradedPathMatrix.writes("eBay", in: "Sold it on ebay."))
        #expect(!DegradedPathMatrix.writes("tmux", in: "Run tmuxinator."))
        #expect(DegradedPathMatrix.writes("++", in: "Write C++ code."))
    }

    @Test("matches Docs/degraded-path-matrix.md, which is generated from the corpus")
    func pageMatchesCorpus() async throws {
        let generated = await Self.matrix.value.markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
