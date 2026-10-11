// Reads and writes the small fitted-parameter files a quality layer ships, refusing any file not fitted for this build.

import CryptoKit
import Foundation
import os

/// Why a learned-parameter file could not be used.
enum LearnedParametersError: Error, Equatable, Sendable {
    /// The layer has no file to read.
    case missing
    /// The file is longer than the reader's byte limit.
    case tooLarge(bytes: Int)
    /// The file ends before its declared content does.
    case truncated
    /// The file does not start with the format's magic.
    case badMagic
    /// The file declares a container version this build does not read.
    case unsupportedFormat(found: UInt32)
    /// The file was fitted against another feature specification.
    case specVersionMismatch(expected: UInt32, found: UInt32)
    /// The file was fitted for another recogniser or engine revision.
    case engineMismatch(expected: String, found: String)
    /// The file belongs to another layer.
    case layerMismatch(expected: String, found: String)
    /// The feature identifiers differ from the expected ones in content or order.
    case featuresMismatch
    /// The file names more features than the limit.
    case tooManyFeatures(count: Int)
    /// The file holds more arrays than the limit.
    case tooManyArrays(count: Int)
    /// An array holds more values than the limit.
    case tooManyValues(array: String, count: Int)
    /// A name is blank, too long or not valid text.
    case invalidName
    /// Two arrays share this name.
    case duplicateArray(String)
    /// The array's declared range is not finite or its bounds are reversed.
    case invalidRange(array: String)
    /// A value is NaN or infinite.
    case nonFinite(array: String, index: Int)
    /// A value lies outside the array's declared range.
    case outOfRange(array: String, index: Int)
    /// Bytes follow the last array.
    case trailingBytes
    /// The file's SHA-256 is not the one the data manifest lists.
    case digestMismatch
}

/// What a file must have been fitted for before its numbers are used.
struct LearnedParametersExpectation: Equatable, Sendable {
    /// The feature specification version the layer computes its features under.
    let specVersion: UInt32
    /// The layer id the file is for.
    let layer: String
    /// The recogniser or engine revision the file was fitted for.
    let engine: String
    /// The ordered feature identifiers the layer computes.
    let features: [String]
}

/// The size limits a learned-parameter file is checked against before any value is kept.
struct LearnedParametersLimits: Equatable, Sendable {
    /// The most bytes the file may hold.
    let maxBytes: Int
    /// The most feature identifiers the header may name.
    let maxFeatures: Int
    /// The most arrays the payload may hold.
    let maxArrays: Int
    /// The most values one array may hold.
    let maxValues: Int
    /// The most UTF-8 bytes in any one name.
    let maxNameBytes: Int

    /// Room for a reranker's weights or a threshold table; larger files are a different kind of asset.
    static let standard = LearnedParametersLimits(
        maxBytes: 1 << 20, maxFeatures: 256, maxArrays: 64, maxValues: 65_536, maxNameBytes: 64)
}

/// One named array of finite floats, each inside the range the array declares.
struct LearnedArray: Equatable, Sendable {
    /// The array's name, unique within its file.
    let name: String
    /// The smallest value the array may hold.
    let lower: Float
    /// The largest value the array may hold.
    let upper: Float
    /// The values, in file order.
    let values: [Float]
}

/// A layer's fitted numbers with the specification, engine and layer they were fitted for; layout in `Docs/learned-parameters.md`.
struct LearnedParameters: Equatable, Sendable {
    /// The feature specification version the numbers were fitted under.
    let specVersion: UInt32
    /// The layer id the numbers are for.
    let layer: String
    /// The recogniser or engine revision the numbers were fitted for.
    let engine: String
    /// The ordered feature identifiers the numbers are indexed by.
    let features: [String]
    /// The named arrays, in file order.
    let arrays: [LearnedArray]

    static let magic = Array("UTTRLPAR".utf8)
    static let formatVersion: UInt32 = 1

    /// Builds parameters, refusing a value or name the reader would refuse.
    init(
        specVersion: UInt32, layer: String, engine: String, features: [String], arrays: [LearnedArray],
        limits: LearnedParametersLimits = .standard
    ) throws(LearnedParametersError) {
        guard features.count <= limits.maxFeatures else { throw .tooManyFeatures(count: features.count) }
        guard arrays.count <= limits.maxArrays else { throw .tooManyArrays(count: arrays.count) }
        for name in [layer, engine] + features + arrays.map(\.name) {
            let size = name.utf8.count
            guard size > 0, size <= limits.maxNameBytes, !name.allSatisfy(\.isWhitespace) else {
                throw .invalidName
            }
        }
        var seen = Set<String>()
        for array in arrays {
            guard seen.insert(array.name).inserted else { throw .duplicateArray(array.name) }
            try Self.check(array, limits: limits)
        }
        self.specVersion = specVersion
        self.layer = layer
        self.engine = engine
        self.features = features
        self.arrays = arrays
    }

    /// The values of the array called `name`, or nil when the file holds none.
    subscript(name: String) -> [Float]? { arrays.first { $0.name == name }?.values }

    /// The SHA-256 of the encoded file as lowercase hex, the form the data manifest lists.
    var digest: String { Self.digest(of: encoded()) }

    /// The SHA-256 of `data` as lowercase hex.
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func check(
        _ array: LearnedArray, limits: LearnedParametersLimits
    ) throws(LearnedParametersError) {
        guard array.lower.isFinite, array.upper.isFinite, array.lower <= array.upper else {
            throw .invalidRange(array: array.name)
        }
        guard array.values.count <= limits.maxValues else {
            throw .tooManyValues(array: array.name, count: array.values.count)
        }
        for (index, value) in array.values.enumerated() {
            guard value.isFinite else { throw .nonFinite(array: array.name, index: index) }
            guard value >= array.lower, value <= array.upper else {
                throw .outOfRange(array: array.name, index: index)
            }
        }
    }
}

// MARK: - Writing

extension LearnedParameters {
    /// The file's bytes; the fit tool writes exactly these.
    func encoded() -> Data {
        var out = Data(Self.magic)
        out.append(le: Self.formatVersion)
        out.append(le: specVersion)
        out.append(string: layer)
        out.append(string: engine)
        out.append(le: UInt16(features.count))
        for feature in features { out.append(string: feature) }
        out.append(le: UInt16(arrays.count))
        for array in arrays {
            out.append(string: array.name)
            out.append(le: array.lower.bitPattern)
            out.append(le: array.upper.bitPattern)
            out.append(le: UInt32(array.values.count))
            for value in array.values { out.append(le: value.bitPattern) }
        }
        return out
    }
}

// MARK: - Reading

extension LearnedParameters {
    /// The parameters in `data`, or the first reason they cannot be used for `expectation`.
    static func decode(
        _ data: Data, expecting expectation: LearnedParametersExpectation,
        digest expectedDigest: String? = nil, limits: LearnedParametersLimits = .standard
    ) throws(LearnedParametersError) -> LearnedParameters {
        guard data.count <= limits.maxBytes else { throw .tooLarge(bytes: data.count) }
        if let expectedDigest, digest(of: data) != expectedDigest { throw .digestMismatch }
        var cursor = ByteCursor(bytes: Array(data))
        guard try cursor.take(magic.count) == magic else { throw .badMagic }
        let format = try cursor.uint32()
        guard format == formatVersion else { throw .unsupportedFormat(found: format) }
        let spec = try cursor.uint32()
        guard spec == expectation.specVersion else {
            throw .specVersionMismatch(expected: expectation.specVersion, found: spec)
        }
        let layer = try cursor.string(maxBytes: limits.maxNameBytes)
        guard layer == expectation.layer else {
            throw .layerMismatch(expected: expectation.layer, found: layer)
        }
        let engine = try cursor.string(maxBytes: limits.maxNameBytes)
        guard engine == expectation.engine else {
            throw .engineMismatch(expected: expectation.engine, found: engine)
        }
        let featureCount = Int(try cursor.uint16())
        guard featureCount <= limits.maxFeatures else { throw .tooManyFeatures(count: featureCount) }
        var features: [String] = []
        for _ in 0..<featureCount { features.append(try cursor.string(maxBytes: limits.maxNameBytes)) }
        guard features == expectation.features else { throw .featuresMismatch }
        let arrayCount = Int(try cursor.uint16())
        guard arrayCount <= limits.maxArrays else { throw .tooManyArrays(count: arrayCount) }
        var arrays: [LearnedArray] = []
        for _ in 0..<arrayCount {
            let name = try cursor.string(maxBytes: limits.maxNameBytes)
            let lower = Float(bitPattern: try cursor.uint32())
            let upper = Float(bitPattern: try cursor.uint32())
            let count = Int(try cursor.uint32())
            guard count <= limits.maxValues else { throw .tooManyValues(array: name, count: count) }
            var values: [Float] = []
            for _ in 0..<count { values.append(Float(bitPattern: try cursor.uint32())) }
            arrays.append(LearnedArray(name: name, lower: lower, upper: upper, values: values))
        }
        guard cursor.isAtEnd else { throw .trailingBytes }
        return try LearnedParameters(
            specVersion: spec, layer: layer, engine: engine, features: features, arrays: arrays,
            limits: limits)
    }
}

/// What a layer runs on after it asks for its file: the fitted numbers, or none and the reason.
enum LearnedParametersState: Equatable, Sendable {
    /// The file passed every check.
    case active(LearnedParameters)
    /// The file was refused, so the layer stays in its dark state, as if switched off.
    case dark(LearnedParametersError)

    private static var log: Logger {
        Logger(subsystem: LocalStore.productionIdentifier, category: "parameters")
    }

    /// Decodes `data`; a refusal is logged and returns `.dark`, never a partial result.
    static func resolve(
        _ data: Data?, expecting expectation: LearnedParametersExpectation,
        digest: String? = nil, limits: LearnedParametersLimits = .standard
    ) -> LearnedParametersState {
        let outcome: Result<LearnedParameters, LearnedParametersError>
        if let data {
            outcome = Result { () throws(LearnedParametersError) in
                try LearnedParameters.decode(data, expecting: expectation, digest: digest, limits: limits)
            }
        } else {
            outcome = .failure(.missing)
        }
        switch outcome {
        case .success(let parameters): return .active(parameters)
        case .failure(let error):
            log.fault(
                "Layer \(expectation.layer, privacy: .public) is dark: \(ErrorLog.failure(error), privacy: .public)"
            )
            return .dark(error)
        }
    }
}

private struct ByteCursor {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset == bytes.count }

    mutating func take(_ count: Int) throws(LearnedParametersError) -> [UInt8] {
        guard count <= bytes.count - offset else { throw .truncated }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func uint16() throws(LearnedParametersError) -> UInt16 {
        let part = try take(2)
        return UInt16(part[0]) | UInt16(part[1]) << 8
    }

    mutating func uint32() throws(LearnedParametersError) -> UInt32 {
        let part = try take(4)
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(part[$1]) << (8 * UInt32($1)) }
    }

    mutating func string(maxBytes: Int) throws(LearnedParametersError) -> String {
        let size = Int(try uint16())
        guard size <= maxBytes else { throw .invalidName }
        guard let text = String(bytes: try take(size), encoding: .utf8) else { throw .invalidName }
        return text
    }
}

extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(le value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(string: String) {
        append(le: UInt16(string.utf8.count))
        append(contentsOf: Array(string.utf8))
    }
}
