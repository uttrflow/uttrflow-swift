import Testing

@testable import UttrflowCore

@Suite("The quality layer registry")
struct QualityLayerTests {
    @Test("With no override every layer takes its default.")
    func defaults() {
        let layers = QualityLayers()
        for layer in QualityLayer.allCases {
            #expect(layers.isOn(layer) == layer.defaultOn)
        }
    }

    @Test("The persona layer starts off until its measurement turns it on.")
    func personaStartsOff() {
        #expect(!QualityLayers().isOn(.personaVocabulary))
        #expect(
            QualityLayers { $0 == QualityLayer.personaVocabulary.defaultsKey ? true : nil }.isOn(
                .personaVocabulary))
    }

    @Test("A defaults key turns one layer off and leaves the rest alone.")
    func overrideOne() {
        let layers = QualityLayers { $0 == QualityLayer.scoring.defaultsKey ? false : nil }
        #expect(!layers.isOn(.scoring))
        #expect(layers.isOn(.formatting) == QualityLayer.formatting.defaultOn)
    }

    @Test("Every layer has a distinct key, a summary and a budget.")
    func everyLayerIsDescribed() {
        let keys = Set(QualityLayer.allCases.map(\.defaultsKey))
        #expect(keys.count == QualityLayer.allCases.count)
        for layer in QualityLayer.allCases {
            #expect(!layer.summary.isEmpty)
            #expect(layer.stageBudget > .zero)
        }
    }

    @Test("Only and without compose into one ablation, and the names keep declaration order.")
    func ablation() {
        let layers = QualityLayers.ablation(only: "formatting, scoring,override-gate", without: "scoring")
        #expect(layers?.names == ["override-gate", "formatting"])
        #expect(QualityLayers.ablation(only: nil, without: "formatting")?.isOn(.formatting) == false)
    }

    @Test("An unknown layer name is refused rather than ignored.")
    func unknownName() {
        #expect(QualityLayers.ablation(only: "spelling", without: nil) == nil)
        #expect(QualityLayers.ablation(only: nil, without: "nope") == nil)
    }
}
