import Testing

@testable import UttrflowCore

@Suite("Where each quality layer runs relative to key-up")
struct QualityLayerPlacementTests {
    @Test("every layer is allowed where it declares itself", arguments: QualityLayer.allCases)
    func allowed(layer: QualityLayer) {
        #expect(
            QualityLayer.tailViolation(
                phase: layer.phase, costClass: layer.costClass, isIncremental: layer.isIncremental,
                degradedResult: layer.degradedResult) == nil)
    }

    @Test("a layer that runs after key-up has a degraded result", arguments: QualityLayer.allCases)
    func degraded(layer: QualityLayer) {
        #expect(layer.phase == .perPiece || !(layer.degradedResult ?? "").isEmpty)
    }

    @Test("a whole-text layer that is not incremental is refused in the tail")
    func wholeText() {
        #expect(
            QualityLayer.tailViolation(
                phase: .wholeText, costClass: .fixed, isIncremental: false, degradedResult: "x")
                == "reads the whole text and is not incremental")
        #expect(
            QualityLayer.tailViolation(
                phase: .wholeText, costClass: .fixed, isIncremental: true, degradedResult: "x") == nil)
    }

    @Test("a layer that grows with the whole dictation is refused unless incremental")
    func perDictation() {
        #expect(
            QualityLayer.tailViolation(
                phase: .finalPiece, costClass: .perWordOfDictation, isIncremental: false,
                degradedResult: "x") == "grows with the whole dictation")
    }

    @Test("a layer in the tail with no degraded result is refused")
    func noDegraded() {
        #expect(
            QualityLayer.tailViolation(
                phase: .finalPiece, costClass: .fixed, isIncremental: false, degradedResult: nil)
                == "has no degraded result")
        #expect(
            QualityLayer.tailViolation(
                phase: .perPiece, costClass: .fixed, isIncremental: false, degradedResult: nil) == nil)
    }
}
