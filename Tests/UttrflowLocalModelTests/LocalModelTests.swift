import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowLocalModel

extension LocalModel {
    /// A minimal model for tests that only care about one field.
    fileprivate static func stub(identifier: String, isMultilingual: Bool = true) -> LocalModel {
        LocalModel(
            identifier: identifier, family: "Stub", version: "1", parameterBillions: 1,
            quantisation: .fourBit, downloadBytes: 1, isMultilingual: isMultilingual
        )
    }
}

@Suite("LocalModel")
struct LocalModelTests {
    @Test("lists candidates smallest first, so the ladder is readable")
    func candidatesAreOrdered() {
        let sizes = LocalModel.candidates.map(\.downloadBytes)
        #expect(sizes == sizes.sorted())
        #expect(LocalModel.candidates.count == 5)
    }

    /// The reason a local model is in this product at all.
    @Test("every candidate claims languages beyond English")
    func allMultilingual() {
        for model in LocalModel.candidates {
            #expect(model.isMultilingual, "\(model.shortName) would not help with Hindi")
            #expect(model.supports(.hindi))
        }
    }

    @Test("finds a model by full identifier or short name")
    func lookup() {
        for model in LocalModel.candidates {
            #expect(LocalModel.named(model.identifier) == model)
            #expect(LocalModel.named(model.shortName) == model)
        }
        #expect(LocalModel.named("not-a-model") == nil)
    }

    @Test("describes each candidate well enough to compare them")
    func carriesIdentifyingDetail() {
        for model in LocalModel.candidates {
            #expect(!model.family.isEmpty)
            #expect(!model.version.isEmpty)
            #expect(model.parameterBillions > 0)
        }
        #expect(LocalModel.gemma3Small.displayName == "Gemma 3")
        #expect(LocalModel.qwen3.displayName == "Qwen 3 (2507)")
    }

    @Test(
        "writes parameter counts the way people do",
        arguments: [(1.0, "1B"), (3.0, "3B"), (4.0, "4B"), (3.8, "3.8B"), (0.5, "0.5B")]
            as [(Double, String)]
    )
    func parameterLabels(billions: Double, expected: String) {
        let model = LocalModel(
            identifier: "x", family: "F", version: "1", parameterBillions: billions,
            quantisation: .fourBit, downloadBytes: 1, isMultilingual: true)
        #expect(model.parameterLabel == expected)
    }

    @Test("names each quantisation the way its makers do")
    func quantisationNames() {
        #expect(Quantisation.fourBit.rawValue == "4-bit")
        #expect(Quantisation.fourBitQAT.rawValue == "4-bit QAT")
        #expect(LocalModel.gemma3.quantisation == .fourBitQAT)
        #expect(LocalModel.llama32.quantisation == .fourBit)
    }

    @Test("shortens the repository identifier for reports")
    func shortName() {
        #expect(LocalModel.qwen3.shortName == "Qwen3-4B-Instruct-2507-4bit")
        #expect(LocalModel.stub(identifier: "bare").shortName == "bare")
    }

    @Test("falls back to the identifier when there is no name to shorten", arguments: ["", "/"])
    func shortNameFallback(identifier: String) {
        let model = LocalModel.stub(identifier: identifier)
        #expect(model.shortName == identifier)
    }

    /// A model too large for a 16 GB laptop has not won whatever it scores.
    @Test("keeps every candidate small enough for a laptop")
    func sizesArePlausible() {
        for model in LocalModel.candidates {
            #expect(model.downloadBytes > 500_000_000, "\(model.shortName) looks too small to be real")
            #expect(model.downloadBytes < 5_000_000_000, "\(model.shortName) is too big to ship")
        }
    }

    @Test("treats an English-only model as unable to help other languages")
    func englishOnly() {
        let englishOnly = LocalModel.stub(identifier: "x", isMultilingual: false)
        #expect(englishOnly.supports(.english))
        #expect(!englishOnly.supports(.hindi))
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let decoded = try JSONDecoder().decode(
            LocalModel.self, from: JSONEncoder().encode(LocalModel.qwen3))
        #expect(decoded == .qwen3)
    }
}
