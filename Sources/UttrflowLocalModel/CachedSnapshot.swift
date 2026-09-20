// Finds a model already whole in the local Hugging Face cache, so loading it asks nothing of the network.
import Foundation
import MLXLMCommon

/// A model's snapshot in the local Hugging Face cache, trusted only when every file it needs is whole.
enum CachedSnapshot {
    /// The files every snapshot needs besides its weights: the architecture and the tokenizer.
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]

    /// The largest safetensors header believed, so a corrupt length cannot ask for gigabytes.
    static let largestHeader: UInt64 = 100_000_000

    /// The snapshot of `identifier` in `cache` when its files are whole and its weights heavy enough.
    static func complete(identifier: String, in cache: URL, minimumWeightBytes: UInt64) -> URL? {
        let repository = cache.appending(
            path: "models--" + identifier.replacingOccurrences(of: "/", with: "--"),
            directoryHint: .isDirectory)
        guard
            let reference = try? String(
                contentsOf: repository.appending(path: "refs").appending(path: "main"), encoding: .utf8),
            case let commit = reference.trimmingCharacters(in: .whitespacesAndNewlines),
            isCommitHash(commit)
        else { return nil }
        let snapshot = repository.appending(path: "snapshots").appending(
            path: commit, directoryHint: .isDirectory)
        guard requiredFiles.allSatisfy({ (size(of: snapshot.appending(path: $0)) ?? 0) > 0 }),
            let weights = weightFiles(in: snapshot)
        else { return nil }
        guard let weighed = total(weights.map { wholeSize(of: snapshot.appending(path: $0)) }),
            weighed >= minimumWeightBytes
        else { return nil }
        return snapshot
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

    /// Where the weights load from: the cache's copy when whole, otherwise what `downloader` fetches, or a throw with no downloader.
    func weightsDirectory(
        cache: URL, downloader: (@Sendable () -> any MLXLMCommon.Downloader)?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let snapshot = CachedSnapshot.complete(
            identifier: identifier, in: cache, minimumWeightBytes: minimumWeightBytes)
        {
            onProgress(1)
            return snapshot
        }
        guard let downloader else { throw WeightsNotOnDisk(identifier: identifier) }
        let resolved = try await resolve(
            configuration: ModelConfiguration(id: identifier), from: downloader(), useLatest: false,
            progressHandler: { onProgress($0.fractionCompleted) })
        return resolved.modelDirectory
    }
}

/// The weights are not whole on disk and nothing was allowed to fetch them.
public struct WeightsNotOnDisk: Error, Equatable {
    /// The model whose weights are missing.
    public let identifier: String
}
