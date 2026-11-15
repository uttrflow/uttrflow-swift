import Testing

@testable import UttrflowCore

@Suite("Every quality layer names the work limit that bounds it, not only a clock")
struct QualityLayerWorkBoundTests {
    @Test("a layer declares a work bound beyond its time budget", arguments: QualityLayer.allCases)
    func declaresAWorkBound(layer: QualityLayer) {
        #expect(!layer.workBound.isEmpty)
        #expect(!layer.workBound.localizedCaseInsensitiveContains("timeout"), "\(layer.rawValue)")
    }
}
