// Reads one of this build's JSON files, telling a missing file apart from one that is there and cannot be read.

import os

public import struct Foundation.Data
public import struct Foundation.Date
public import typealias Foundation.TimeInterval
public import struct Foundation.URL
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import struct Foundation.CocoaError

/// What reading a stored file found: its value, nothing at all, or a file that could not be read.
public enum StoredList<Value: Decodable & Sendable>: Sendable {
    /// No file is there, which is an honest empty store.
    case missing
    /// The file decoded.
    case read(Value)
    /// The file is there and could not be read or decoded; it was moved to `setAside`, or left in place when `nil`.
    case unreadable(setAside: URL?)

    /// The value, or `nil` when the file is missing or unreadable.
    public var value: Value? {
        guard case .read(let value) = self else { return nil }
        return value
    }

    /// Whether the file was there and could not be read, which is never evidence that it was empty.
    public var isUnreadable: Bool {
        guard case .unreadable = self else { return false }
        return true
    }

    /// Whether an unreadable file is still under its own name, so writing there would destroy it.
    public var isLeftInPlace: Bool {
        guard case .unreadable(setAside: nil) = self else { return false }
        return true
    }
}

/// A stored list that can be decoded one element at a time, so an entry written by a newer build costs only itself.
protocol ElementwiseDecodable {
    /// The elements this build can decode, and how many it could not.
    static func decodeEachElement(from data: Data) throws -> (value: Any, dropped: Int)
}

extension Array: ElementwiseDecodable where Element: Decodable {
    static func decodeEachElement(from data: Data) throws -> (value: Any, dropped: Int) {
        let attempts = try JSONDecoder().decode([Attempt].self, from: data)
        let kept = attempts.compactMap(\.element)
        return (kept, attempts.count - kept.count)
    }

    /// One element, or `nil` when this build cannot decode it.
    private struct Attempt: Decodable {
        let element: Element?

        init(from decoder: any Decoder) throws {
            element = try? Element(from: decoder)
        }
    }
}

extension LocalStore {
    private static let log = Logger(subsystem: productionIdentifier, category: "store")

    /// The suffix a set-aside file carries after the name it was read under.
    static let setAsideMarker = ".unreadable-"

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
        guard let value = decodeKeepingReadable(type, from: data, readFrom: url, now: now) else {
            return .unreadable(setAside: setAside(url, now: now))
        }
        return .read(value)
    }

    /// Decodes a stored value; a list keeps every element this build can read, copying the file's original bytes aside once when one is dropped.
    static func decodeKeepingReadable<Value: Decodable>(
        _ type: Value.Type, from data: Data, readFrom url: URL, now: Date,
        onPreservedOriginal: ((URL) -> Void)? = nil
    ) -> Value? {
        guard let list = type as? any ElementwiseDecodable.Type else {
            return try? JSONDecoder().decode(type, from: data)
        }
        guard let (decoded, droppedCount) = try? list.decodeEachElement(from: data),
            let value = decoded as? Value
        else { return nil }
        if droppedCount > 0 {
            log.error(
                "Kept the readable entries of \(url.lastPathComponent, privacy: .public), dropping \(droppedCount)"
            )
            if !hasSetAside(url), let copy = putAside(url, now: now, keepingOriginal: true) {
                onPreservedOriginal?(copy)
            }
        }
        return value
    }

    /// Whether a file read under this name has been set aside and is still waiting beside it.
    public static func hasSetAside(_ url: URL) -> Bool {
        let prefix = url.lastPathComponent + setAsideMarker
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path(percentEncoded: false))) ?? []
        return names.contains { $0.hasPrefix(prefix) }
    }

    /// Deletes every copy set aside from this name, or only those stamped inside `range` when one is given.
    public static func removeSetAside(_ url: URL, stamped range: Range<Date>? = nil) throws {
        let prefix = url.lastPathComponent + setAsideMarker
        let folder = url.deletingLastPathComponent()
        let doomed = try contents(of: folder).filter { name in
            guard name.hasPrefix(prefix) else { return false }
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
        let newestFirst = stamped.sorted { ($0.stamp, $0.name) > ($1.stamp, $1.name) }
        let oldest = now.addingTimeInterval(-setAsideLifetime).timeIntervalSince1970
        let doomed = newestFirst.enumerated().filter { index, copy in
            index >= setAsideLimit || Double(copy.stamp) < oldest
        }
        try? removeEach(doomed.map { folder.appending(path: $0.element.name, directoryHint: .notDirectory) })
    }

    /// Renames an unreadable file to a timestamped name beside it, answering `nil` when it cannot be moved.
    public static func setAside(_ url: URL, now: Date) -> URL? {
        putAside(url, now: now, keepingOriginal: false)
    }

    /// Moves a file, or copies it when the original stays in use, to a timestamped name beside it.
    private static func putAside(_ url: URL, now: Date, keepingOriginal: Bool) -> URL? {
        let name = url.lastPathComponent
        let stamp = "\(name)\(setAsideMarker)\(Int(now.timeIntervalSince1970))"
        let folder = url.deletingLastPathComponent()
        for attempt in 0..<100 {
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
}
