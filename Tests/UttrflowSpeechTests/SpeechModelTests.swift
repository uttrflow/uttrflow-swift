import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("SpeechModel")
struct SpeechModelTests {
    @Test("ships a multilingual model by default, because Hindi is required")
    func defaultIsMultilingual() {
        #expect(SpeechModel.default.isMultilingual)
        #expect(SpeechModel.default.supports(.hindi))
        #expect(SpeechModel.default == .largeV3Turbo)
    }

    @Test("lists every model smallest first, so the catalogue reads as a ladder")
    func catalogueIsOrdered() {
        let sizes = SpeechModel.catalogue.map(\.downloadBytes)
        #expect(sizes == sizes.sorted())
        #expect(SpeechModel.catalogue.count == 3)
    }

    @Test("finds a model by its repository identifier")
    func lookup() {
        for model in SpeechModel.catalogue {
            #expect(SpeechModel.named(model.variant) == model)
        }
        #expect(SpeechModel.named("not-a-model") == nil)
    }

    @Test("quotes a real download size for every model")
    func sizesArePlausible() {
        for model in SpeechModel.catalogue {
            #expect(model.downloadBytes > 100_000_000, "\(model.variant) size looks wrong")
            #expect(model.downloadBytes < 2_000_000_000, "\(model.variant) size looks wrong")
        }
    }

    @Test("treats an English-only model as unable to handle other languages")
    func englishOnlySupport() {
        let englishOnly = SpeechModel(
            variant: "x", downloadBytes: 1, isMultilingual: false,
            tokenizerRepository: "openai/whisper-tiny.en")
        #expect(englishOnly.supports(.english))
        #expect(!englishOnly.supports(.hindi))
    }

    /// The install fetches the tokenizer from here, and the recogniser then reads it off
    /// disk. A model that named the wrong repository would install a vocabulary that
    /// decodes its output into nonsense, so every entry has to name a real one.
    @Test("names the repository publishing its tokenizer, for every model")
    func everyModelNamesItsTokenizer() {
        for model in SpeechModel.catalogue {
            #expect(
                model.tokenizerRepository.hasPrefix("openai/whisper-"),
                "\(model.variant) names \(model.tokenizerRepository), which is not a Whisper tokenizer"
            )
        }
    }

    @Test("round-trips through Codable so a chosen model survives relaunch")
    func codable() throws {
        let decoded = try JSONDecoder().decode(
            SpeechModel.self, from: JSONEncoder().encode(SpeechModel.default)
        )
        #expect(decoded == .default)
    }
}

@Suite("SpeechEngineFactory")
struct SpeechEngineFactoryTests {
    @Test("builds the recogniser the configuration names", arguments: SpeechEngineKind.allCases)
    func buildsRequestedKind(kind: SpeechEngineKind) {
        let engine = SpeechEngineFactory.make(
            kind: kind, modelFolder: URL(fileURLWithPath: "/tmp/uttrflow-test")
        )
        #expect(engine.kind == kind)
    }
}
