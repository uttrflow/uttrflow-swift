// Reads one of this build's JSON files, telling a missing file apart from one that is there and cannot be read.

import os

public import struct Foundation.Data
public import struct Foundation.Date
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
}

extension LocalStore {
    private static let log = Logger(subsystem: productionIdentifier, category: "store")

    /// The suffix a set-aside file carries after the name it was read under.
    static let setAsideMarker = ".unreadable-"

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
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            return .unreadable(setAside: setAside(url, now: now))
        }
        return .read(value)
    }

    /// Whether a file read under this name has been set aside and is still waiting beside it.
    public static func hasSetAside(_ url: URL) -> Bool {
        let prefix = url.lastPathComponent + setAsideMarker
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path(percentEncoded: false))) ?? []
        return names.contains { $0.hasPrefix(prefix) }
    }

    /// Deletes every copy set aside from this name, or only those stamped before `cutoff` when one is given.
    public static func removeSetAside(_ url: URL, stampedBefore cutoff: Date? = nil) throws {
        let prefix = url.lastPathComponent + setAsideMarker
        let folder = url.deletingLastPathComponent()
        let doomed = try contents(of: folder).filter { name in
            guard name.hasPrefix(prefix) else { return false }
            guard let cutoff else { return true }
            // A stamp that does not parse is kept, since its age cannot be known.
            let stamp = name.dropFirst(prefix.count).split(separator: "-").first
            guard let seconds = stamp.flatMap({ Int($0) }) else { return false }
            return Date(timeIntervalSince1970: Double(seconds)) < cutoff
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

    /// Renames an unreadable file to a timestamped name beside it, answering `nil` when it cannot be moved.
    static func setAside(_ url: URL, now: Date) -> URL? {
        let name = url.lastPathComponent
        let stamp = "\(name)\(setAsideMarker)\(Int(now.timeIntervalSince1970))"
        let folder = url.deletingLastPathComponent()
        for attempt in 0..<100 {
            let candidate = attempt == 0 ? stamp : "\(stamp)-\(attempt)"
            let destination = folder.appending(path: candidate, directoryHint: .notDirectory)
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
            else { continue }
            do {
                try FileManager.default.moveItem(at: url, to: destination)
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
