import Foundation
import Testing

@testable import UttrflowCore

@Suite("Learned-parameter writers honor the reader's encoded byte limit")
struct LearnedParametersWriterLimitTests {
    private let expectation = LearnedParametersExpectation(
        specVersion: 3, layer: "scoring-é", engine: "synthetic-é", features: ["φ"])
    private let arrays = [LearnedArray(name: "weights-é", lower: -2, upper: 2, values: [0.5, -1.25])]

    private func limits(bytes: Int) -> LearnedParametersLimits {
        let standard = LearnedParametersLimits.standard
        return LearnedParametersLimits(
            maxBytes: bytes, maxFeatures: standard.maxFeatures, maxArrays: standard.maxArrays,
            maxValues: standard.maxValues, maxNameBytes: standard.maxNameBytes)
    }

    private func parameters(
        arrays: [LearnedArray], limits: LearnedParametersLimits = .standard
    ) throws -> LearnedParameters {
        try LearnedParameters(
            specVersion: expectation.specVersion, layer: expectation.layer, engine: expectation.engine,
            features: expectation.features, arrays: arrays, limits: limits)
    }

    @Test("the aggregate standard byte limit refuses individually valid arrays")
    func standardAggregateLimit() throws {
        let arrays = (0..<4).map {
            LearnedArray(
                name: "weights-\($0)", lower: 0, upper: 1,
                values: Array(repeating: Float(0), count: LearnedParametersLimits.standard.maxValues))
        }
        let encoded = try parameters(arrays: arrays, limits: limits(bytes: 2 * 1_048_576)).encoded()
        #expect(encoded.count == 1_048_718)
        #expect(throws: LearnedParametersError.tooLarge(bytes: encoded.count)) {
            _ = try self.parameters(arrays: arrays)
        }
        #expect(throws: LearnedParametersError.tooLarge(bytes: encoded.count)) {
            _ = try LearnedParameters.decode(encoded, expecting: self.expectation)
        }
    }

    @Test("a custom limit one byte below the encoded file refuses construction")
    func customLimit() throws {
        let bytes = try parameters(arrays: arrays).encoded()
        #expect(throws: LearnedParametersError.tooLarge(bytes: bytes.count)) {
            _ = try self.parameters(arrays: self.arrays, limits: self.limits(bytes: bytes.count - 1))
        }
    }

    @Test("UTF-8 names at the exact byte limit keep their bytes and digest")
    func exactLimit() throws {
        let original = try parameters(arrays: arrays)
        let bytes = original.encoded()
        let saved = try #require(
            Data(
                base64Encoded:
                    "VVRUUkxQQVIBAAAAAwAAAAoAc2NvcmluZy3DqQwAc3ludGhldGljLcOpAQACAM+GAQAK"
                    + "AHdlaWdodHMtw6kAAADAAAAAQAIAAAAAAAA/AACgvw=="))
        #expect(bytes == saved)
        #expect(original.digest == "bb8441812bd63ce72f2098d5c71612ef5c821e48592548060ea5c4ee645e1aac")
        let limits = limits(bytes: bytes.count)
        let exact = try parameters(arrays: arrays, limits: limits)
        let decoded = try LearnedParameters.decode(
            bytes, expecting: expectation, digest: original.digest, limits: limits)
        #expect(exact.encoded() == bytes)
        #expect(exact.digest == original.digest)
        #expect(decoded == original)
    }

    @Test("an empty array payload honors its header's exact byte boundary")
    func emptyArrays() throws {
        let original = try parameters(arrays: [])
        let bytes = original.encoded()
        let exact = try parameters(arrays: [], limits: limits(bytes: bytes.count))
        #expect(exact.encoded() == bytes)
        #expect(exact.digest == original.digest)
        #expect(throws: LearnedParametersError.tooLarge(bytes: bytes.count)) {
            _ = try self.parameters(arrays: [], limits: self.limits(bytes: bytes.count - 1))
        }
    }
}
