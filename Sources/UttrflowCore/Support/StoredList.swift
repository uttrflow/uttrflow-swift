// Reads one of this build's JSON files, telling a missing file apart from one that is there and cannot be read.

import os

public import struct Foundation.Data
public import struct Foundation.Date
public import struct Foundation.UUID
public import typealias Foundation.TimeInterval
public import struct Foundation.URL
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONSerialization
public import struct Foundation.CocoaError

/// What reading a stored file found: its value, nothing at all, or a file that could not be read.
public enum StoredList<Value: Decodable & Sendable>: Sendable {
    /// No file is there, which is an honest empty store.
    case missing
    /// The file decoded.
    case read(Value)
    /// Readable entries were returned with the number and locations of records this build could not decode.
    case recovered(
        Value, droppedCount: Int, quarantineRecords: [URL], preservedOriginal: URL?,
        preservationSucceeded: Bool)
    /// The file uses an encrypted envelope version this build cannot read; its bytes stay in place.
    case unsupportedVersion(UInt8)
    /// The file is there and could not be read or decoded; it was moved to `setAside`, or left in place when `nil`.
    case unreadable(setAside: URL?)

    /// The value, or `nil` when the file is missing or unreadable.
    public var value: Value? {
        switch self {
        case .read(let value), .recovered(let value, _, _, _, _): return value
        case .missing, .unsupportedVersion, .unreadable: return nil
        }
    }

    /// The number of individual JSON entries this build could not decode.
    public var droppedRecordCount: Int {
        guard case .recovered(_, let droppedCount, _, _, _) = self else { return 0 }
        return droppedCount
    }

    /// The preserved whole-file copy when some list entries were skipped.
    public var preservedOriginal: URL? {
        guard case .recovered(_, _, _, let preservedOriginal, _) = self else { return nil }
        return preservedOriginal
    }

    /// One private JSON artifact for each record this build could not decode.
    public var quarantineRecords: [URL] {
        guard case .recovered(_, _, let quarantineRecords, _, _) = self else { return [] }
        return quarantineRecords
    }

    /// Whether every undecodable record was safely preserved before the source may be replaced.
    public var preservationSucceeded: Bool {
        guard case .recovered(_, _, _, _, let succeeded) = self else { return true }
        return succeeded
    }

    /// Whether the file was there and could not be read, which is never evidence that it was empty.
    public var isUnreadable: Bool {
        guard case .unreadable = self else { return false }
        return true
    }

    /// Whether an unreadable file is still under its own name, so writing there would destroy it.
    public var isLeftInPlace: Bool {
        switch self {
        case .unsupportedVersion, .unreadable(setAside: nil), .recovered(_, _, _, _, false): return true
        case .missing, .read(_), .unreadable(setAside: .some), .recovered(_, _, _, _, true): return false
        }
    }
}

/// A stored list that can be decoded one element at a time, so an entry written by a newer build costs only itself.
package protocol ElementwiseDecodable {
    /// The elements this build can decode and the exact raw JSON bytes of entries it could not.
    static func decodeEachElement(from data: Data) throws -> (value: Any, rejected: [Data])
}

extension Array: ElementwiseDecodable where Element: Decodable {
    package static func decodeEachElement(from data: Data) throws -> (value: Any, rejected: [Data]) {
        let records = try RawJSONArray.elements(from: data)
        var kept: [Element] = []
        var rejected: [Data] = []
        for record in records {
            guard
                (try? JSONSerialization.jsonObject(with: record, options: .fragmentsAllowed)) != nil
            else { throw CocoaError(.fileReadCorruptFile) }
            if let element = try? JSONDecoder().decode(Element.self, from: record) {
                kept.append(element)
            } else {
                rejected.append(record)
            }
        }
        return (kept, rejected)
    }
}

/// Slices an already-valid top-level JSON array without re-encoding its values.
private enum RawJSONArray {
    static func elements(from data: Data) throws -> [Data] {
        let bytes = [UInt8](data)
        var index = 0
        skipWhitespace(bytes, &index)
        guard index < bytes.count, bytes[index] == 0x5B else { throw CocoaError(.fileReadCorruptFile) }
        index += 1
        skipWhitespace(bytes, &index)
        if index < bytes.count, bytes[index] == 0x5D {
            index += 1
            skipWhitespace(bytes, &index)
            guard index == bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            return []
        }

        var elements: [Data] = []
        while index < bytes.count {
            let start = index
            var nesting = 0
            var inString = false
            var escaped = false
            var delimiter: UInt8?
            while index < bytes.count {
                let byte = bytes[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == 0x5C {
                        escaped = true
                    } else if byte == 0x22 {
                        inString = false
                    }
                } else {
                    switch byte {
                    case 0x22: inString = true
                    case 0x7B, 0x5B: nesting += 1
                    case 0x7D:
                        guard nesting > 0 else { throw CocoaError(.fileReadCorruptFile) }
                        nesting -= 1
                    case 0x5D where nesting > 0: nesting -= 1
                    case 0x2C, 0x5D:
                        if nesting == 0 { delimiter = byte }
                    default: break
                    }
                    if delimiter != nil { break }
                }
                index += 1
            }
            var end = index
            while end > start, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[end - 1]) { end -= 1 }
            guard end > start, !inString else { throw CocoaError(.fileReadCorruptFile) }
            elements.append(Data(bytes[start..<end]))
            guard let delimiter else { throw CocoaError(.fileReadCorruptFile) }
            index += 1
            if delimiter == 0x5D {
                skipWhitespace(bytes, &index)
                guard index == bytes.count else { throw CocoaError(.fileReadCorruptFile) }
                return elements
            }
            skipWhitespace(bytes, &index)
            guard index < bytes.count, bytes[index] != 0x5D else { throw CocoaError(.fileReadCorruptFile) }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private static func skipWhitespace(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }
}

extension LocalStore {
    private static let log = Logger(subsystem: productionIdentifier, category: "store")

    /// The suffix a set-aside file carries after the name it was read under.
    static let setAsideMarker = ".unreadable-"

    private static func quarantineRecord(
        _ data: Data, from url: URL, at now: Date, generation: String, index: Int
    ) -> URL? {
        let stamp = Int(now.timeIntervalSince1970)
        let name = "\(url.lastPathComponent).quarantine-\(stamp)-\(generation)-\(index).json"
        let destination = url.deletingLastPathComponent().appending(path: name, directoryHint: .notDirectory)
        do {
            try PrivateFile.write(data, to: destination)
            try? PrivateFile.excludeFromBackup(at: destination)
            pruneQuarantineRecords(url, now: now)
            return destination
        } catch {
            log.error("Could not quarantine malformed entry from \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    /// Reads a local JSON file through an injected authenticated-encryption layer.
    public static func read<Value: Decodable & Encodable & Sendable>(
        _ type: Value.Type, from url: URL, encryptedBy store: EncryptedStore, now: Date = Date()
    ) -> StoredList<Value> {
        store.read(type, from: url, now: now)
    }

    /// Reads and decodes a file, moving an unreadable one aside so the next write cannot replace it.
    public static func read<Value: Decodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date = Date()
    ) -> StoredList<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(setAside: setAside(url, now: now))
        }
        guard
            let decoded = decodeKeepingReadable(
                type, from: data, readFrom: url, now: now,
                onPreservedOriginal: nil)
        else {
            return .unreadable(setAside: setAside(url, now: now))
        }
        if decoded.droppedCount == 0 { return .read(decoded.value) }
        return .recovered(
            decoded.value, droppedCount: decoded.droppedCount, quarantineRecords: decoded.quarantineRecords,
            preservedOriginal: decoded.preservedOriginal, preservationSucceeded: decoded.preservationSucceeded
        )
    }

    /// A decoded list and the malformed JSON entries retained for recovery.
    struct Decoded<Value: Decodable & Sendable>: Sendable {
        let value: Value
        let droppedCount: Int
        let quarantineRecords: [URL]
        let preservedOriginal: URL?
        let preservationSucceeded: Bool
    }

    /// Decodes readable list entries and preserves the original bytes when entries are dropped.
    static func decodeKeepingReadable<Value: Decodable & Sendable>(
        _ type: Value.Type, from data: Data, readFrom url: URL, now: Date,
        onPreservedOriginal: ((URL, Bool) -> Bool)? = nil
    ) -> Decoded<Value>? {
        guard let list = type as? any ElementwiseDecodable.Type else {
            guard let value = try? JSONDecoder().decode(type, from: data) else { return nil }
            return Decoded(
                value: value, droppedCount: 0, quarantineRecords: [], preservedOriginal: nil,
                preservationSucceeded: true)
        }
        guard let (decoded, rejected) = try? list.decodeEachElement(from: data),
            let value = decoded as? Value
        else { return nil }
        var preservedOriginal: URL?
        var quarantineRecords: [URL] = []
        var preservationSucceeded = true
        if !rejected.isEmpty {
            let generationTime = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
            let generation =
                String(format: "%020llu", generationTime)
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            log.error(
                "Kept the readable entries of \(url.lastPathComponent, privacy: .public), dropping \(rejected.count)"
            )
            if let copy = putAside(url, now: now, keepingOriginal: true) {
                preservedOriginal = copy
                if onPreservedOriginal?(copy, false) == false {
                    preservationSucceeded = false
                }
            }
            for (index, record) in rejected.enumerated() {
                guard
                    let artifact = quarantineRecord(
                        record, from: url, at: now, generation: generation, index: index)
                else {
                    preservationSucceeded = false
                    break
                }
                if onPreservedOriginal?(artifact, true) == false {
                    try? FileManager.default.removeItem(at: artifact)
                    preservationSucceeded = false
                    break
                }
                quarantineRecords.append(artifact)
            }
            if quarantineRecords.count != rejected.count { preservationSucceeded = false }
            if !preservationSucceeded {
                for artifact in quarantineRecords { try? FileManager.default.removeItem(at: artifact) }
                quarantineRecords = []
                if let preservedOriginal { try? FileManager.default.removeItem(at: preservedOriginal) }
                preservedOriginal = nil
            }
        }
        return Decoded(
            value: value, droppedCount: rejected.count, quarantineRecords: quarantineRecords,
            preservedOriginal: preservedOriginal, preservationSucceeded: preservationSucceeded)
    }

    /// Whether a file read under this name has been set aside and is still waiting beside it.
    public static func hasSetAside(_ url: URL) -> Bool {
        let prefixes = [url.lastPathComponent + setAsideMarker, url.lastPathComponent + ".quarantine-"]
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path(percentEncoded: false))) ?? []
        return names.contains { name in prefixes.contains { name.hasPrefix($0) } }
    }

    /// Deletes every copy set aside from this name, or only those stamped inside `range` when one is given.
    public static func removeSetAside(_ url: URL, stamped range: Range<Date>? = nil) throws {
        let prefixes = [url.lastPathComponent + setAsideMarker, url.lastPathComponent + ".quarantine-"]
        let folder = url.deletingLastPathComponent()
        let doomed = try contents(of: folder).filter { name in
            guard let prefix = prefixes.first(where: { name.hasPrefix($0) }) else { return false }
            guard let range else { return true }
            // A stamp that does not parse is kept, since its age cannot be known.
            let stamp = name.dropFirst(prefix.count).split(separator: "-").first
            guard let seconds = stamp.flatMap({ Int($0) }) else { return false }
            return range.contains(Date(timeIntervalSince1970: Double(seconds)))
        }
        try removeEach(doomed.map { folder.appending(path: $0, directoryHint: .notDirectory) })
    }

    /// The names in a folder; a folder that is not there is empty, and one that cannot be listed throws.
    public static func contents(of folder: URL) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    /// Deletes every file it can, then throws the first refusal, so one stuck file cannot keep the rest.
    public static func removeEach(_ files: [URL]) throws {
        var refusal: (any Error)?
        for file in files {
            do { try FileManager.default.removeItem(at: file) } catch { refusal = refusal ?? error }
        }
        if let refusal { throw refusal }
    }

    /// How many set-aside copies of one file are kept; the oldest beyond this go when another is made.
    public static let setAsideLimit = 3

    /// How long a set-aside copy is kept before the next one made beside it removes it.
    public static let setAsideLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Removes copies set aside from this name past `setAsideLifetime`, then the oldest past `setAsideLimit`.
    static func pruneSetAside(_ url: URL, now: Date) {
        let prefix = url.lastPathComponent + setAsideMarker
        let folder = url.deletingLastPathComponent()
        let stamped: [(name: String, stamp: Int)] = ((try? contents(of: folder)) ?? []).compactMap { name in
            guard name.hasPrefix(prefix) else { return nil }
            // A stamp that does not parse is kept, since its age cannot be known.
            guard let stamp = name.dropFirst(prefix.count).split(separator: "-").first.flatMap({ Int($0) })
            else { return nil }
            return (name, stamp)
        }
        let newestFirst = stamped.sorted {
            ($0.stamp, collisionIndex(in: $0.name, prefix: prefix), $0.name)
                > ($1.stamp, collisionIndex(in: $1.name, prefix: prefix), $1.name)
        }
        let oldest = now.addingTimeInterval(-setAsideLifetime).timeIntervalSince1970
        let doomed = newestFirst.enumerated().filter { index, copy in
            index >= setAsideLimit || Double(copy.stamp) < oldest
        }
        try? removeEach(doomed.map { folder.appending(path: $0.element.name, directoryHint: .notDirectory) })
    }

    /// Retains only recent quarantine generations, with the same bound as full index copies.
    private static func pruneQuarantineRecords(_ url: URL, now: Date) {
        let prefix = url.lastPathComponent + ".quarantine-"
        let folder = url.deletingLastPathComponent()
        var groups: [String: (stamp: Int, names: [String])] = [:]
        for name in (try? contents(of: folder)) ?? [] where name.hasPrefix(prefix) {
            let components = name.dropFirst(prefix.count).split(separator: "-", maxSplits: 2)
            guard components.count == 3, let stamp = Int(components[0]) else { continue }
            let generation = components[1].count == 52 ? String(components[1]) : "legacy-\(stamp)"
            let key = "\(stamp)-\(generation)"
            var group = groups[key] ?? (stamp, [])
            group.names.append(name)
            groups[key] = group
        }
        let newest = groups.keys.sorted {
            (groups[$0]?.stamp ?? 0, $0) > (groups[$1]?.stamp ?? 0, $1)
        }
        let oldestAllowed = Int(now.addingTimeInterval(-setAsideLifetime).timeIntervalSince1970)
        let doomed = newest.enumerated().filter { offset, key in
            offset >= setAsideLimit || (groups[key]?.stamp ?? 0) < oldestAllowed
        }.flatMap { groups[$0.element]?.names ?? [] }
        try? removeEach(doomed.map { folder.appending(path: $0, directoryHint: .notDirectory) })
    }

    /// Renames an unreadable file to a timestamped name beside it, answering `nil` when it cannot be moved.
    public static func setAside(_ url: URL, now: Date) -> URL? {
        putAside(url, now: now, keepingOriginal: false)
    }

    /// Copies an unreadable file to a timestamped name, retaining the source until the copy is safe.
    static func copySetAside(_ url: URL, now: Date) -> URL? {
        putAside(url, now: now, keepingOriginal: true)
    }

    /// Moves a file, or copies it when the original stays in use, to a timestamped name beside it.
    private static func putAside(_ url: URL, now: Date, keepingOriginal: Bool) -> URL? {
        let name = url.lastPathComponent
        let stamp = "\(name)\(setAsideMarker)\(Int(now.timeIntervalSince1970))"
        let folder = url.deletingLastPathComponent()
        guard let firstAttempt = firstCollisionAttempt(for: stamp, in: folder) else { return nil }
        for offset in 0..<100 {
            let (attempt, overflow) = firstAttempt.addingReportingOverflow(offset)
            guard !overflow else { break }
            let candidate = attempt == 0 ? stamp : "\(stamp)-\(attempt)"
            let destination = folder.appending(path: candidate, directoryHint: .notDirectory)
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
            else { continue }
            do {
                if keepingOriginal {
                    try FileManager.default.copyItem(at: url, to: destination)
                } else {
                    try FileManager.default.moveItem(at: url, to: destination)
                }
                try? PrivateFile.excludeFromBackup(at: destination)
                pruneSetAside(url, now: now)
                log.error("Set aside an unreadable \(name, privacy: .public) instead of replacing it")
                return destination
            } catch {
                break
            }
        }
        log.fault("Could not set aside an unreadable \(name, privacy: .public)")
        return nil
    }

    private static func firstCollisionAttempt(for stamp: String, in folder: URL) -> Int? {
        let existing = ((try? contents(of: folder)) ?? []).filter {
            $0 == stamp || $0.hasPrefix(stamp + "-")
        }
        let suffixes = existing.compactMap { collisionSuffix(in: $0, stampedPrefix: stamp) }
        guard let largest = suffixes.max() else { return existing.contains(stamp) ? 1 : 0 }
        let (next, overflow) = largest.addingReportingOverflow(1)
        return overflow ? nil : next
    }

    private static func collisionIndex(in name: String, prefix: String) -> Int {
        let remainder = name.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: "-") else { return 0 }
        return Int(remainder[remainder.index(after: separator)...]) ?? 0
    }

    private static func collisionSuffix(in name: String, stampedPrefix: String) -> Int? {
        guard name.hasPrefix(stampedPrefix), name.count > stampedPrefix.count else { return nil }
        let suffixStart = name.index(name.startIndex, offsetBy: stampedPrefix.count)
        guard name[suffixStart] == "-" else { return nil }
        return Int(name[name.index(after: suffixStart)...])
    }
}
