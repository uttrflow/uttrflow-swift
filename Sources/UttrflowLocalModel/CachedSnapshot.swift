// Finds a model already whole in the local Hugging Face cache, so loading it asks nothing of the network.
import Foundation
import Darwin
import HuggingFace
import MLXLMCommon

/// A model's snapshot in the local Hugging Face cache, trusted only when every file it needs is whole.
enum CachedSnapshot {
    private enum CacheRemovalError: Error { case unsafePath, unreadableCache, sharedBlob }
    /// The files every snapshot needs besides its weights: the architecture and the tokenizer.
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]

    /// The largest safetensors header believed, so a corrupt length cannot ask for gigabytes.
    static let largestHeader: UInt64 = 100_000_000

    /// A corrupt metadata length cannot make a cache check read unbounded data.
    private static let largestConfiguration: UInt64 = 100_000_000

    /// The snapshot of `identifier` in `cache` when its files are whole and its weights heavy enough.
    static func complete(
        identifier: String, revision: String, in cache: URL, minimumWeightBytes: UInt64
    ) -> URL? {
        guard isCommitHash(revision) else { return nil }
        guard let repository = repository(identifier: identifier, in: cache) else { return nil }
        guard isDirectory(repository) else { return nil }
        let snapshots = repository.appending(path: "snapshots", directoryHint: .isDirectory)
        guard isDirectory(snapshots) else { return nil }
        let snapshot = snapshots.appending(
            path: revision, directoryHint: .isDirectory)
        guard isDirectory(snapshot) else { return nil }
        guard requiredFiles.allSatisfy({ validConfiguration(snapshot.appending(path: $0)) }),
            let weights = weightFiles(in: snapshot)
        else { return nil }
        guard let weighed = total(weights.map { wholeSize(of: snapshot.appending(path: $0)) }),
            weighed >= minimumWeightBytes
        else { return nil }
        return snapshot
    }

    private static func repository(identifier: String, in cache: URL) -> URL? {
        guard
            identifier.range(
                of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
        else { return nil }
        return cache.appending(
            path: "models--" + identifier.replacingOccurrences(of: "/", with: "--"),
            directoryHint: .isDirectory)
    }
    static func diskUsage(identifier: String, in cache: URL) -> Int64? {
        guard let repository = repository(identifier: identifier, in: cache) else { return nil }
        guard let exists = pathExistsIncludingDanglingSymlink(repository) else { return nil }
        guard exists else { return 0 }
        guard isDirectory(repository) else { return nil }
        var directories = [repository]
        var bytes: Int64 = 0
        while let directory = directories.popLast() {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            else { return nil }
            for file in files {
                guard let values = metadata(file) else { return nil }
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true { directories.append(file); continue }
                guard values.isRegularFile == true, let size = values.fileSize else { return nil }
                let (sum, overflow) = bytes.addingReportingOverflow(Int64(size))
                guard !overflow else { return nil }
                bytes = sum
            }
        }
        return bytes
    }
    static func remove(identifier: String, in cache: URL) throws {
        guard canonical(cache) == cache.standardizedFileURL else { throw CacheRemovalError.unsafePath }
        guard let repository = repository(identifier: identifier, in: cache) else { return }
        guard let repositoryExists = pathExistsIncludingDanglingSymlink(repository) else {
            throw CacheRemovalError.unreadableCache
        }
        guard repositoryExists else { return }
        guard
            isDirectory(repository), FileManager.default.isWritableFile(atPath: repository.path)
        else { throw CacheRemovalError.unsafePath }
        let snapshots = repository.appending(path: "snapshots", directoryHint: .isDirectory)
        guard let snapshotsExist = pathExistsIncludingDanglingSymlink(snapshots) else {
            throw CacheRemovalError.unreadableCache
        }
        guard !snapshotsExist || isDirectory(snapshots) else { throw CacheRemovalError.unsafePath }
        guard
            let referenced = snapshotBlobReferences(
                in: canonical(cache), excluding: canonical(repository))
        else {
            throw CacheRemovalError.unreadableCache
        }
        let blobRoot = canonical(repository.appending(path: "blobs")).pathComponents
        let sharesBlob = referenced.contains { reference in
            let components = URL(fileURLWithPath: reference).pathComponents
            return components.count > blobRoot.count && components.starts(with: blobRoot)
        }
        guard !sharesBlob else {
            throw CacheRemovalError.sharedBlob
        }
        if snapshotsExist {
            try FileManager.default.removeItem(at: snapshots)
        }
        try FileManager.default.removeItem(at: repository)
    }
    @discardableResult
    static func removeSuperseded(
        identifier: String, revision: String, in cache: URL, minimumWeightBytes: UInt64
    ) -> Bool {
        guard
            complete(
                identifier: identifier, revision: revision, in: cache,
                minimumWeightBytes: minimumWeightBytes) != nil,
            let repository = repository(identifier: identifier, in: cache)
        else { return false }
        let snapshots = repository.appending(path: "snapshots", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else {
            return false
        }
        let cacheRoot = canonical(cache)
        let stale = names.filter { $0 != revision && isCommitHash($0) }
        guard stale.allSatisfy({ isDirectory(snapshots.appending(path: $0)) }) else { return false }
        var staleBlobs: Set<String> = []
        for name in stale {
            let snapshot = snapshots.appending(path: name, directoryHint: .isDirectory)
            guard let blobs = blobReferences(in: snapshot, cacheRoot: cacheRoot) else { return false }
            staleBlobs.formUnion(blobs)
        }
        let staleSnapshots = Set(stale.map { snapshots.appending(path: $0).standardizedFileURL.path })
        guard
            let referenced = snapshotBlobReferences(
                in: cacheRoot, excludingSnapshots: staleSnapshots)
        else { return false }
        for name in stale {
            do { try FileManager.default.removeItem(at: snapshots.appending(path: name)) } catch {
                return false
            }
        }
        let repositoryRoot = canonical(repository)
        let blobs = repository.appending(path: "blobs", directoryHint: .isDirectory)
        guard isDirectory(blobs), canonical(blobs) == blobs.standardizedFileURL else {
            return true
        }
        let blobRoot = canonical(blobs)
        for path in staleBlobs.subtracting(referenced) {
            let blob = URL(fileURLWithPath: path)
            let candidate = canonical(blob)
            guard candidate == blob.standardizedFileURL,
                candidate.pathComponents.starts(with: blobRoot.pathComponents),
                candidate.pathComponents.count > blobRoot.pathComponents.count,
                candidate.pathComponents.starts(with: repositoryRoot.pathComponents),
                isRegularFile(candidate)
            else { continue }
            try? FileManager.default.removeItem(at: blob)
        }
        return true
    }
    static func isDirectory(_ url: URL) -> Bool {
        metadata(url).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
    }
    static func pathExistsIncludingDanglingSymlink(_ url: URL) -> Bool? {
        var metadata = stat(); return lstat(url.path, &metadata) == 0 ? true : (errno == ENOENT ? false : nil)
    }
    private static func isRegularFile(_ url: URL) -> Bool {
        metadata(url).map { $0.isRegularFile == true && $0.isSymbolicLink != true } ?? false
    }
    private static func metadata(_ url: URL) -> URLResourceValues? {
        try? url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        ])
    }
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
    /// Whether a required model metadata file is a bounded, nonempty JSON object.
    private static func validConfiguration(_ file: URL) -> Bool {
        guard let length = size(of: file), length > 0, length <= largestConfiguration,
            let handle = try? FileHandle(forReadingFrom: file.resolvingSymlinksInPath())
        else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(length)), data.count == Int(length),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return !object.isEmpty
    }

    /// Whether `text` is a full commit hash, the only name a snapshot directory is given.
    static func isCommitHash(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }

    /// The weight files in `snapshot`, or nil when there are none or a numbered shard is missing.
    static func weightFiles(in snapshot: URL) -> [String]? {
        guard let listed = try? FileManager.default.contentsOfDirectory(atPath: snapshot.path) else {
            return nil
        }
        let weights = listed.filter { $0.hasSuffix(".safetensors") }.sorted()
        guard !weights.isEmpty else { return nil }
        for name in weights {
            // A shard such as `model-00001-of-00002.safetensors` needs every sibling its count names.
            guard let match = name.wholeMatch(of: /(.+)-\d+-of-(\d+)\.safetensors/), let count = Int(match.2)
            else { continue }
            let width = match.2.count
            for number in 1...max(1, count) {
                let digits = String(number)
                let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
                guard listed.contains("\(match.1)-\(padded)-of-\(match.2).safetensors") else { return nil }
            }
        }
        return weights
    }

    /// The bytes one element of each safetensors dtype takes; a dtype not listed is checked by offsets alone.
    static let elementBytes: [String: UInt64] = [
        "BOOL": 1, "U8": 1, "I8": 1, "F8_E5M2": 1, "F8_E4M3": 1, "U16": 2, "I16": 2, "F16": 2, "BF16": 2,
        "U32": 4, "I32": 4, "F32": 4, "U64": 8, "I64": 8, "F64": 8,
    ]

    /// The sum of `sizes`, or nil when any is missing or the total does not fit.
    static func total(_ sizes: [UInt64?]) -> UInt64? {
        var sum: UInt64 = 0
        for size in sizes {
            guard let size else { return nil }
            let (added, overflow) = sum.addingReportingOverflow(size)
            guard !overflow else { return nil }
            sum = added
        }
        return sum
    }

    /// A safetensors file's header, the name of every tensor with its type, shape and offsets.
    static func header(of file: URL) -> [String: Any]? {
        parsed(file)?.tensors
    }

    /// A safetensors file's length when it matches its own header, which a cut-off or corrupt file never does.
    static func wholeSize(of file: URL) -> UInt64? {
        guard let (tensors, length, headerLength) = parsed(file),
            tile(tensors, payload: length - 8 - headerLength)
        else { return nil }
        return length
    }

    /// The header of a safetensors file with the file's length and the header's, or nil when the header cannot be read.
    private static func parsed(_ file: URL) -> (tensors: [String: Any], length: UInt64, headerLength: UInt64)?
    {
        guard let length = size(of: file), length > 8,
            let handle = try? FileHandle(forReadingFrom: file.resolvingSymlinksInPath())
        else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return nil }
        let headerLength = prefix.enumerated().reduce(UInt64(0)) {
            $0 | UInt64($1.element) << (8 * $1.offset)
        }
        // Compared against `length - 8`, which `length > 8` keeps from wrapping, so no sum can overflow.
        guard headerLength > 0, headerLength <= largestHeader, headerLength <= length - 8,
            let header = try? handle.read(upToCount: Int(headerLength)), header.count == Int(headerLength),
            let tensors = try? JSONSerialization.jsonObject(with: header) as? [String: Any]
        else { return nil }
        return (tensors, length, headerLength)
    }

    /// Whether the header's tensors cover exactly `payload` bytes, end to end, each as long as its shape says.
    static func tile(_ tensors: [String: Any], payload: UInt64) -> Bool {
        var ranges: [(begin: UInt64, end: UInt64)] = []
        for (name, value) in tensors where name != "__metadata__" {
            guard let tensor = value as? [String: Any], let dtype = tensor["dtype"] as? String,
                let shape = unsignedIntegers(tensor["shape"]),
                let offsets = unsignedIntegers(tensor["data_offsets"]), offsets.count == 2,
                offsets[0] <= offsets[1], offsets[1] <= payload,
                spans(offsets[1] - offsets[0], dtype: dtype, shape: shape)
            else { return false }
            ranges.append((offsets[0], offsets[1]))
        }
        var next: UInt64 = 0
        for range in ranges.sorted(by: { ($0.begin, $0.end) < ($1.begin, $1.end) }) {
            guard range.begin == next else { return false }
            next = range.end
        }
        return next == payload
    }

    /// Whether `bytes` is what `shape` elements of `dtype` take, false when that count does not fit in 64 bits.
    static func spans(_ bytes: UInt64, dtype: String, shape: [UInt64]) -> Bool {
        guard let width = elementBytes[dtype] else { return true }
        var product = width
        for dimension in shape {
            let (multiplied, overflow) = product.multipliedReportingOverflow(by: dimension)
            guard !overflow else { return false }
            product = multiplied
        }
        return product == bytes
    }

    /// A JSON array of whole numbers from zero to `UInt64.max`, or nil for anything else, booleans included.
    static func unsignedIntegers(_ value: Any?) -> [UInt64]? {
        guard let array = value as? [Any] else { return nil }
        var numbers: [UInt64] = []
        for element in array {
            guard let number = element as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                let whole = element as? UInt64
            else { return nil }
            numbers.append(whole)
        }
        return numbers
    }

    /// The byte length of the regular file `url` names, through any symbolic link.
    static func size(of url: URL) -> UInt64? {
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey,
        ])
        guard values?.isRegularFile == true, let size = values?.fileSize else { return nil }
        return UInt64(size)
    }
}

extension LocalModel {
    /// The least cached weights may weigh to be believed whole: nine tenths of the recorded download.
    var minimumWeightBytes: UInt64 { UInt64(max(0, downloadBytes)) / 10 * 9 }

    func cachedBytes(in cache: URL) -> Int64? {
        CachedSnapshot.diskUsage(identifier: identifier, in: cache)
    }
    package var cachedBytes: Int64? { cachedBytes(in: HubCache.default.cacheDirectory) }
    func removeCachedFiles(in cache: URL) throws {
        try CachedSnapshot.remove(identifier: identifier, in: cache)
    }
    package func removeCachedFiles() throws {
        try removeCachedFiles(in: HubCache.default.cacheDirectory)
    }
    /// Where the weights load from: the cache's copy when whole, otherwise what `downloader` fetches, or a throw with no downloader.
    func weightsDirectory(
        cache: URL, downloader: (@Sendable () -> any MLXLMCommon.Downloader)?,
        onProgress: @escaping @Sendable (Double) -> Void,
        capacityForDownload: (@Sendable (URL) -> Int64?)? = nil,
        downloadHeadroomBytes: Int64 = 0
    ) async throws -> URL {
        if let snapshot = CachedSnapshot.complete(
            identifier: identifier, revision: revision, in: cache,
            minimumWeightBytes: minimumWeightBytes)
        {
            CachedSnapshot.removeSuperseded(
                identifier: identifier, revision: revision, in: cache,
                minimumWeightBytes: minimumWeightBytes)
            onProgress(1)
            return snapshot
        }
        guard let downloader else { throw WeightsNotOnDisk(identifier: identifier) }
        let (sum, overflow) = max(downloadBytes, 0).addingReportingOverflow(max(downloadHeadroomBytes, 0))
        let neededBytes = overflow ? Int64.max : sum
        if let capacityForDownload, let available = capacityForDownload(cache), available < neededBytes {
            throw InsufficientModelSpace(neededBytes: neededBytes)
        }
        let resolved = try await resolve(
            configuration: ModelConfiguration(id: identifier, revision: revision),
            from: downloader(), useLatest: false,
            progressHandler: { onProgress($0.fractionCompleted) })
        if let complete = CachedSnapshot.complete(
            identifier: identifier, revision: revision, in: cache,
            minimumWeightBytes: minimumWeightBytes),
            complete.standardizedFileURL == resolved.modelDirectory.standardizedFileURL
        {
            CachedSnapshot.removeSuperseded(
                identifier: identifier, revision: revision, in: cache,
                minimumWeightBytes: minimumWeightBytes)
        }
        return resolved.modelDirectory
    }
}

/// The volume cannot hold a complete model download.
public struct InsufficientModelSpace: Error, Equatable, Sendable {
    /// The pinned model's complete download size.
    public let neededBytes: Int64

    public init(neededBytes: Int64) {
        self.neededBytes = neededBytes
    }
}

/// The weights are not whole on disk and nothing was allowed to fetch them.
public struct WeightsNotOnDisk: Error, Equatable {
    /// The model whose weights are missing.
    public let identifier: String
}
