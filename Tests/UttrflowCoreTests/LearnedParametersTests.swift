// Tests for the learned-parameter file: the round trip, and every kind of file the reader refuses.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("A learned-parameter file is used only when it was fitted for this feature order, spec and engine")
struct LearnedParametersTests {
    private let features = ["lexical", "phonetic", "context"]
    private let expectation = LearnedParametersExpectation(
        specVersion: 3, layer: "scoring", engine: "engine-a", features: ["lexical", "phonetic", "context"])

    private func parameters(
        spec: UInt32 = 3, layer: String = "scoring", engine: String = "engine-a",
        features: [String]? = nil, arrays: [LearnedArray]? = nil
    ) throws -> LearnedParameters {
        try LearnedParameters(
            specVersion: spec, layer: layer, engine: engine, features: features ?? self.features,
            arrays: arrays ?? [LearnedArray(name: "weights", lower: -4, upper: 4, values: [0.5, -1.25, 2])])
    }

    private func failure(_ data: Data, digest: String? = nil) -> LearnedParametersError? {
        do {
            _ = try LearnedParameters.decode(data, expecting: expectation, digest: digest)
            return nil
        } catch {
            return error
        }
    }

    private func patched(_ data: Data, at offset: Int, to bytes: [UInt8]) -> Data {
        var copy = data
        for (index, byte) in bytes.enumerated() { copy[offset + index] = byte }
        return copy
    }

    @Test("a valid file round-trips with an identical digest")
    func roundTrip() throws {
        let original = try parameters()
        let bytes = original.encoded()
        let decoded = try LearnedParameters.decode(bytes, expecting: expectation, digest: original.digest)
        #expect(decoded == original)
        #expect(decoded.encoded() == bytes)
        #expect(decoded.digest == original.digest)
        #expect(decoded["weights"] == [0.5, -1.25, 2])
        #expect(decoded["missing"] == nil)
    }

    @Test("a reordered feature list is refused")
    func reorderedFeatures() throws {
        let file = try parameters(features: ["phonetic", "lexical", "context"]).encoded()
        #expect(failure(file) == .featuresMismatch)
    }

    @Test("a feature list with another length is refused")
    func shorterFeatures() throws {
        #expect(failure(try parameters(features: ["lexical", "phonetic"]).encoded()) == .featuresMismatch)
    }

    @Test("a spec version one off is refused")
    func specVersion() throws {
        #expect(
            failure(try parameters(spec: 4).encoded()) == .specVersionMismatch(expected: 3, found: 4))
        #expect(
            failure(try parameters(spec: 2).encoded()) == .specVersionMismatch(expected: 3, found: 2))
    }

    @Test("a different engine identity is refused")
    func engine() throws {
        #expect(
            failure(try parameters(engine: "engine-b").encoded())
                == .engineMismatch(expected: "engine-a", found: "engine-b"))
    }

    @Test("a file for another layer is refused")
    func layer() throws {
        #expect(
            failure(try parameters(layer: "override-gate").encoded())
                == .layerMismatch(expected: "scoring", found: "override-gate"))
    }

    @Test("a NaN or an infinity is refused by the writer and by the reader")
    func nonFinite() throws {
        for bad in [Float.nan, .infinity, -.infinity] {
            let array = LearnedArray(name: "weights", lower: -4, upper: 4, values: [1, bad])
            #expect(throws: LearnedParametersError.nonFinite(array: "weights", index: 1)) {
                _ = try self.parameters(arrays: [array])
            }
        }
        // The first value of the shipped layout starts after magic, format, spec, strings and the array head.
        let good = try parameters().encoded()
        let valueStart = good.count - 3 * 4
        for pattern in [Float.nan, .infinity].map(\.bitPattern) {
            let bytes = (0..<4).map { UInt8((pattern >> (8 * UInt32($0))) & 0xFF) }
            #expect(
                failure(patched(good, at: valueStart, to: bytes)) == .nonFinite(array: "weights", index: 0))
        }
    }

    @Test("a value outside the declared range is refused")
    func outOfRange() throws {
        let array = LearnedArray(name: "weights", lower: -1, upper: 1, values: [0.5, 2])
        #expect(throws: LearnedParametersError.outOfRange(array: "weights", index: 1)) {
            _ = try self.parameters(arrays: [array])
        }
    }

    @Test("a reversed or non-finite range is refused")
    func badRange() {
        for (lower, upper) in [(Float(2), Float(1)), (.nan, 1), (0, .infinity)] {
            let array = LearnedArray(name: "weights", lower: lower, upper: upper, values: [])
            #expect(throws: LearnedParametersError.invalidRange(array: "weights")) {
                _ = try self.parameters(arrays: [array])
            }
        }
    }

    @Test("duplicate and blank names are refused")
    func names() {
        let array = LearnedArray(name: "weights", lower: 0, upper: 1, values: [])
        #expect(throws: LearnedParametersError.duplicateArray("weights")) {
            _ = try self.parameters(arrays: [array, array])
        }
        #expect(throws: LearnedParametersError.invalidName) {
            _ = try self.parameters(arrays: [LearnedArray(name: " ", lower: 0, upper: 1, values: [])])
        }
    }

    @Test("a wrong magic, a newer container and an altered digest are refused")
    func container() throws {
        let good = try parameters().encoded()
        #expect(failure(patched(good, at: 0, to: [0x58])) == .badMagic)
        #expect(failure(patched(good, at: 8, to: [2])) == .unsupportedFormat(found: 2))
        #expect(failure(good, digest: String(repeating: "0", count: 64)) == .digestMismatch)
        #expect(failure(Data()) == .truncated)
    }

    @Test("every truncation and trailing byte is refused")
    func truncation() throws {
        let good = try parameters().encoded()
        for length in 0..<good.count { #expect(failure(good.prefix(length)) != nil) }
        #expect(failure(good + Data([0])) == .trailingBytes)
    }

    @Test("a file over the byte limit is refused before it is read")
    func tooLarge() throws {
        let limits = LearnedParametersLimits(
            maxBytes: 16, maxFeatures: 8, maxArrays: 8, maxValues: 8, maxNameBytes: 8)
        let good = try parameters().encoded()
        #expect(throws: LearnedParametersError.tooLarge(bytes: good.count)) {
            _ = try LearnedParameters.decode(good, expecting: self.expectation, limits: limits)
        }
    }

    @Test("a declared count past its limit is refused")
    func counts() throws {
        let limits = LearnedParametersLimits(
            maxBytes: 4_096, maxFeatures: 2, maxArrays: 8, maxValues: 2, maxNameBytes: 16)
        #expect(throws: LearnedParametersError.tooManyFeatures(count: 3)) {
            _ = try LearnedParameters.decode(
                try self.parameters().encoded(), expecting: self.expectation, limits: limits)
        }
    }

    @Test("a refused file leaves the layer dark, and an accepted one active")
    func state() throws {
        let good = try parameters()
        #expect(LearnedParametersState.resolve(good.encoded(), expecting: expectation) == .active(good))
        #expect(LearnedParametersState.resolve(nil, expecting: expectation) == .dark(.missing))
        let stale = try parameters(spec: 2).encoded()
        #expect(
            LearnedParametersState.resolve(stale, expecting: expectation)
                == .dark(.specVersionMismatch(expected: 3, found: 2)))
    }
}
