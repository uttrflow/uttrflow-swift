// Tests that a model already whole on disk loads without the hub, and that anything less still reaches it.

import Foundation
import MLXLMCommon
import Testing
import os

@testable import UttrflowLocalModel

/// A downloader that records every call and refuses it, standing in for the network.
private final class RefusingDownloader: MLXLMCommon.Downloader {
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    /// How many times anything asked the hub for a snapshot.
    var count: Int { calls.withLock { $0 } }

    /// What the stand-in hub throws, so a test can tell it from a real failure.
    struct Refused: Error {}

    func download(
        id: String, revision: String?, matching patterns: [String], useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        calls.withLock { $0 += 1 }
        throw Refused()
    }
}

/// Every fraction a load reported, from whichever thread reported it.
private final class Fractions: Sendable {
    private let seen = OSAllocatedUnfairLock<[Double]>(initialState: [])

    var reported: [Double] { seen.withLock { $0 } }

    func record(_ fraction: Double) { seen.withLock { $0.append(fraction) } }
}

/// A Hugging Face cache laid out as the hub leaves it: blobs, a ref and a snapshot of links.
struct FakeCache {
    let root: URL
    let identifier = "example-org/tiny-model"
    let commit = String(repeating: "a1", count: 20)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cached-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repository.appending(path: "refs"), withIntermediateDirectories: true)
        try Data((commit + "\n").utf8).write(to: repository.appending(path: "refs/main"))
    }

    var repository: URL { root.appending(path: "models--example-org--tiny-model") }
    var blobs: URL { repository.appending(path: "blobs") }
    var snapshot: URL { repository.appending(path: "snapshots/\(commit)") }

    /// Writes `data` as a blob and links it into the snapshot under `name`, the way the hub does.
    func add(_ name: String, _ data: Data) throws {
        let blob = blobs.appending(path: UUID().uuidString)
        try data.write(to: blob)
        try FileManager.default.createSymbolicLink(
            atPath: snapshot.appending(path: name).path,
            withDestinationPath: "../../blobs/\(blob.lastPathComponent)")
    }

    /// Everything but the weights: the architecture and the tokenizer.
    func addConfiguration() throws {
        for name in CachedSnapshot.requiredFiles { try add(name, Data("{}".utf8)) }
    }

    /// A safetensors file whose header claims `bytes` of tensor data, cut to `keeping` of them.
    static func weights(bytes: Int, keeping: Int? = nil) -> Data {
        let header = Data(#"{"w":{"dtype":"U8","shape":[\#(bytes)],"data_offsets":[0,\#(bytes)]}}"#.utf8)
        var length = UInt64(header.count).littleEndian
        var file = Data(bytes: &length, count: 8)
        file.append(header)
        file.append(Data(repeating: 7, count: keeping ?? bytes))
        return file
    }

    /// The weights a whole snapshot is allowed to weigh no less than.
    static let minimum: UInt64 = 256

    func complete() -> URL? {
        CachedSnapshot.complete(identifier: identifier, in: root, minimumWeightBytes: Self.minimum)
    }

    func model() -> LocalModel { Self.model(identifier: identifier) }

    static func model(identifier: String, downloadBytes: Int64 = 256) -> LocalModel {
        LocalModel(
            identifier: identifier, family: "Tiny", version: "1", parameterBillions: 0.1,
            quantisation: .fourBit, downloadBytes: downloadBytes, isMultilingual: true)
    }
}

@Suite("A model whole on disk loads without the network")
struct CachedSnapshotTests {
    @Test("A whole cached model is loaded from its snapshot, and the hub is never asked")
    func wholeCacheNeverAsksTheHub() async throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let hub = RefusingDownloader()
        let fractions = Fractions()
        let directory = try await cache.model().weightsDirectory(
            cache: cache.root, downloader: { hub }, onProgress: fractions.record)
        #expect(hub.count == 0)
        #expect(directory.standardizedFileURL == cache.snapshot.standardizedFileURL)
        #expect(fractions.reported == [1])
    }

    @Test("A cache missing its tokenizer still goes to the hub, so a first download keeps working")
    func incompleteCacheAsksTheHub() async throws {
        let cache = try FakeCache()
        try cache.add("config.json", Data("{}".utf8))
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let hub = RefusingDownloader()
        await #expect(throws: RefusingDownloader.Refused.self) {
            _ = try await cache.model().weightsDirectory(
                cache: cache.root, downloader: { hub }, onProgress: { _ in })
        }
        #expect(hub.count == 1)
    }

    @Test(
        "With no downloader, an incomplete cache throws rather than reaching the hub, which is how a reload stays offline"
    )
    func noDownloaderNeverFetches() async throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 16))
        await #expect(throws: WeightsNotOnDisk(identifier: cache.model().identifier)) {
            _ = try await cache.model().weightsDirectory(
                cache: cache.root, downloader: nil, onProgress: { _ in })
        }
        let whole = try FakeCache()
        try whole.addConfiguration()
        try whole.add("model.safetensors", FakeCache.weights(bytes: 256))
        let directory = try await whole.model().weightsDirectory(
            cache: whole.root, downloader: nil, onProgress: { _ in })
        #expect(directory.standardizedFileURL == whole.snapshot.standardizedFileURL)
    }

    @Test("An empty cache goes to the hub")
    func emptyCacheAsksTheHub() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "no-cache-\(UUID().uuidString)")
        let hub = RefusingDownloader()
        await #expect(throws: RefusingDownloader.Refused.self) {
            _ = try await FakeCache.model(identifier: "example-org/tiny-model").weightsDirectory(
                cache: root, downloader: { hub }, onProgress: { _ in })
        }
        #expect(hub.count == 1)
    }

    @Test("Weights cut short of what their header promises are not trusted")
    func truncatedWeightsAreNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256, keeping: 200))
        #expect(cache.complete() == nil)
    }

    @Test("Weights lighter than the model is known to weigh are not trusted")
    func lightWeightsAreNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 16))
        #expect(cache.complete() == nil)
    }

    @Test("A split model missing one shard is not trusted, and one with every shard is")
    func everyShardIsNeeded() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model-00001-of-00002.safetensors", FakeCache.weights(bytes: 128))
        #expect(cache.complete() == nil)
        try cache.add("model-00002-of-00002.safetensors", FakeCache.weights(bytes: 128))
        #expect(cache.complete()?.standardizedFileURL == cache.snapshot.standardizedFileURL)
    }

    @Test("A snapshot with no weights at all is not trusted")
    func noWeightsIsNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        #expect(cache.complete() == nil)
    }

    @Test("A ref that names no commit is not followed")
    func badReferenceIsNotFollowed() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        try Data("main".utf8).write(to: cache.repository.appending(path: "refs/main"))
        #expect(cache.complete() == nil)
        try FileManager.default.removeItem(at: cache.repository.appending(path: "refs/main"))
        #expect(cache.complete() == nil)
    }

    @Test("A header that is absurdly long, not JSON, or longer than the file is not believed")
    func corruptHeadersAreNotBelieved() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "headers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func size(of bytes: [UInt8]) throws -> UInt64? {
            let file = root.appending(path: UUID().uuidString)
            try Data(bytes).write(to: file)
            return CachedSnapshot.wholeSize(of: file)
        }
        #expect(try size(of: [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 1, 2]) == nil)
        #expect(try size(of: [2, 0, 0, 0, 0, 0, 0, 0] + Array("no".utf8)) == nil)
        #expect(try size(of: [0, 0, 0, 0, 0, 0, 0, 0, 1]) == nil)
        #expect(try size(of: [1, 2, 3]) == nil)
        #expect(CachedSnapshot.wholeSize(of: root.appending(path: "absent")) == nil)
        #expect(CachedSnapshot.size(of: root) == nil)
    }

    @Test(
        "A cached file whose tensor ends near UInt64.max is refused, and the hub is asked instead of trapping"
    )
    func hugeEndOffsetGoesToTheHub() async throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        try cache.add(
            "extra.safetensors",
            HostileHeader.file(
                #"{"w":{"dtype":"U8","shape":[1],"data_offsets":[0,18446744073709551615]}}"#, payload: 16))
        let hub = RefusingDownloader()
        await #expect(throws: RefusingDownloader.Refused.self) {
            _ = try await cache.model().weightsDirectory(
                cache: cache.root, downloader: { hub }, onProgress: { _ in })
        }
        #expect(hub.count == 1)
    }

    @Test("A hostile header is read as an incomplete file, never a trap", arguments: HostileHeader.refused)
    func hostileHeadersAreRefused(_ hostile: HostileHeader) throws {
        #expect(try hostile.wholeSize() == nil)
    }

    @Test(
        "A well-formed header is still believed, however its tensors are ordered",
        arguments: HostileHeader.believed)
    func wellFormedHeadersAreBelieved(_ header: HostileHeader) throws {
        #expect(try header.wholeSize() == UInt64(header.bytes.count))
    }

    @Test("Weight sizes that cannot be summed in 64 bits are not trusted")
    func totalsRefuseOverflow() {
        #expect(CachedSnapshot.total([UInt64.max, 1]) == nil)
        #expect(CachedSnapshot.total([UInt64.max / 2 + 1, UInt64.max / 2 + 1]) == nil)
        #expect(CachedSnapshot.total([1, nil]) == nil)
        #expect(CachedSnapshot.total([UInt64.max - 1, 1]) == UInt64.max)
        #expect(CachedSnapshot.total([]) == 0)
    }

    @Test("A shape whose byte count wraps past 64 bits never matches a range")
    func shapesRefuseOverflow() {
        #expect(!CachedSnapshot.spans(0, dtype: "F32", shape: [1 << 62]))
        #expect(!CachedSnapshot.spans(0, dtype: "U8", shape: [1 << 32, 1 << 32]))
        #expect(CachedSnapshot.spans(0, dtype: "F32", shape: [0, UInt64.max]))
        #expect(CachedSnapshot.spans(8, dtype: "F16", shape: [2, 2]))
        #expect(CachedSnapshot.spans(3, dtype: "F4", shape: [7]))
    }

    @Test("Only a full forty-character hexadecimal name counts as a commit")
    func commitHashes() {
        #expect(CachedSnapshot.isCommitHash(String(repeating: "0f", count: 20)))
        #expect(!CachedSnapshot.isCommitHash("main"))
        #expect(!CachedSnapshot.isCommitHash(String(repeating: "zz", count: 20)))
    }

    @Test("A model's cached weights must reach nine tenths of its recorded download")
    func minimumIsNineTenths() {
        #expect(LocalModel.gemma3.minimumWeightBytes == 2_727_000_000)
        #expect(FakeCache.minimum > 0)
    }
}

/// One safetensors file built byte by byte, named so a failing case says which.
struct HostileHeader: CustomTestStringConvertible, Sendable {
    let name: String
    let bytes: Data

    var testDescription: String { name }

    /// A file whose length prefix matches `header`, followed by `payload` bytes.
    static func file(_ header: String, payload: Int) -> Data {
        file(prefix: UInt64(header.utf8.count), header: Data(header.utf8), payload: payload)
    }

    /// A file with any length prefix and any header bytes, followed by `payload` bytes.
    static func file(prefix: UInt64, header: Data, payload: Int) -> Data {
        var length = prefix.littleEndian
        var data = Data(bytes: &length, count: 8)
        data.append(header)
        data.append(Data(repeating: 3, count: payload))
        return data
    }

    init(_ name: String, _ header: String, payload: Int) {
        self.name = name
        bytes = Self.file(header, payload: payload)
    }

    init(_ name: String, bytes: Data) {
        self.name = name
        self.bytes = bytes
    }

    /// What `CachedSnapshot.wholeSize` makes of these bytes on disk.
    func wholeSize() throws -> UInt64? {
        let file = FileManager.default.temporaryDirectory.appending(path: "hostile-\(UUID().uuidString)")
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return CachedSnapshot.wholeSize(of: file)
    }

    /// A tensor entry of `dtype` and `shape` at `offsets`, written as JSON.
    static func tensor(_ name: String, _ dtype: String, _ shape: String, _ offsets: String) -> String {
        #""\#(name)":{"dtype":"\#(dtype)","shape":\#(shape),"data_offsets":\#(offsets)}"#
    }

    static let refused: [HostileHeader] = [
        HostileHeader(
            "the reported end at UInt64.max", "{\(tensor("w", "U8", "[1]", "[0,18446744073709551615]"))}",
            payload: 16),
        HostileHeader(
            "an end one below UInt64.max", "{\(tensor("w", "U8", "[1]", "[0,18446744073709551614]"))}",
            payload: 16),
        HostileHeader(
            "a begin at UInt64.max", "{\(tensor("w", "U8", "[1]", "[18446744073709551615,16]"))}", payload: 16
        ),
        HostileHeader("a begin after its end", "{\(tensor("w", "U8", "[0]", "[16,0]"))}", payload: 16),
        HostileHeader("an end past the payload", "{\(tensor("w", "U8", "[32]", "[0,32]"))}", payload: 16),
        HostileHeader("an end short of the payload", "{\(tensor("w", "U8", "[8]", "[0,8]"))}", payload: 16),
        HostileHeader("a negative end", "{\(tensor("w", "U8", "[1]", "[0,-1]"))}", payload: 16),
        HostileHeader("a negative begin", "{\(tensor("w", "U8", "[16]", "[-16,0]"))}", payload: 16),
        HostileHeader(
            "an end beyond 64 bits", "{\(tensor("w", "U8", "[1]", "[0,18446744073709551616]"))}", payload: 16),
        HostileHeader("a fractional end", "{\(tensor("w", "U8", "[16]", "[0,16.5]"))}", payload: 16),
        HostileHeader("an exponent end", "{\(tensor("w", "U8", "[16]", "[0,1e30]"))}", payload: 16),
        HostileHeader(
            "offsets written as booleans", "{\(tensor("w", "U8", "[1]", "[false,true]"))}", payload: 1),
        HostileHeader(
            "offsets written as strings", "{\(tensor("w", "U8", "[16]", #"["0","16"]"#))}", payload: 16),
        HostileHeader("three offsets", "{\(tensor("w", "U8", "[16]", "[0,8,16]"))}", payload: 16),
        HostileHeader("one offset", "{\(tensor("w", "U8", "[16]", "[16]"))}", payload: 16),
        HostileHeader("offsets that are not an array", "{\(tensor("w", "U8", "[16]", "16"))}", payload: 16),
        HostileHeader(
            "overlapping ranges",
            "{\(tensor("a", "U8", "[12]", "[0,12]")),\(tensor("b", "U8", "[8]", "[8,16]"))}", payload: 16),
        HostileHeader(
            "two tensors on the same range",
            "{\(tensor("a", "U8", "[16]", "[0,16]")),\(tensor("b", "U8", "[16]", "[0,16]"))}", payload: 16),
        HostileHeader(
            "a hole between ranges",
            "{\(tensor("a", "U8", "[8]", "[0,8]")),\(tensor("b", "U8", "[4]", "[12,16]"))}", payload: 16),
        HostileHeader(
            "a shape that disagrees with its range", "{\(tensor("w", "F32", "[3]", "[0,16]"))}", payload: 16),
        HostileHeader(
            "a shape whose byte count wraps to zero",
            "{\(tensor("w", "F32", "[4611686018427387904]", "[0,0]"))}", payload: 0),
        HostileHeader(
            "a shape past 64 bits", "{\(tensor("w", "U8", "[4294967296,4294967296]", "[0,0]"))}", payload: 0),
        HostileHeader("a negative dimension", "{\(tensor("w", "U8", "[-16]", "[0,16]"))}", payload: 16),
        HostileHeader("a missing dtype", #"{"w":{"shape":[16],"data_offsets":[0,16]}}"#, payload: 16),
        HostileHeader("a tensor that is a number", #"{"w":16}"#, payload: 16),
        HostileHeader("a header that is an array", "[0,16]", payload: 16),
        HostileHeader(
            "JSON nested far past any parser's depth",
            "{\"w\":" + String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000) + "}",
            payload: 0),
        HostileHeader(
            "a header that is not UTF-8",
            bytes: file(prefix: 4, header: Data([0x7B, 0xFF, 0xFE, 0x7D]), payload: 0)),
        HostileHeader(
            "a header length longer than the file",
            bytes: file(prefix: 1_000, header: Data("{}".utf8), payload: 0)),
        HostileHeader(
            "a header length of UInt64.max",
            bytes: file(prefix: UInt64.max, header: Data("{}".utf8), payload: 16)),
        HostileHeader(
            "a header length just below UInt64.max",
            bytes: file(prefix: UInt64.max - 7, header: Data("{}".utf8), payload: 16)),
        HostileHeader(
            "a header length over the cap",
            bytes: file(prefix: CachedSnapshot.largestHeader + 1, header: Data("{}".utf8), payload: 16)),
    ]

    static let believed: [HostileHeader] = [
        HostileHeader("one tensor", "{\(tensor("w", "U8", "[16]", "[0,16]"))}", payload: 16),
        HostileHeader(
            "tensors listed out of order, with metadata",
            #"{"__metadata__":{"format":"mlx"},"#
                + "\(tensor("b", "F16", "[2,2]", "[4,12]")),\(tensor("a", "F32", "[]", "[0,4]"))}",
            payload: 12),
        HostileHeader(
            "an empty tensor beside a full one",
            "{\(tensor("e", "U32", "[0]", "[0,0]")),\(tensor("w", "U32", "[2]", "[0,8]"))}", payload: 8),
        HostileHeader(
            "a dtype without a known width", "{\(tensor("w", "F4", "[31]", "[0,16]"))}", payload: 16),
        HostileHeader("no tensors at all", "{}", payload: 0),
    ]
}
