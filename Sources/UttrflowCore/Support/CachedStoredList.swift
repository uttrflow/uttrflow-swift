// Keeps one stored JSON file's decoded value in memory, reading the file again only when it changed on disk.

import Darwin

public import struct Foundation.URL

/// What identifies one version of a file on disk: its inode, size and change times.
public struct FileStamp: Equatable, Sendable {
    let inode: UInt64
    let size: Int64
    let modified: timespec
    let changed: timespec

    /// The file's stamp, or `nil` when nothing is there to stat.
    public static func of(_ url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path(percentEncoded: false), &info) == 0 else { return nil }
        return FileStamp(
            inode: info.st_ino, size: info.st_size, modified: info.st_mtimespec,
            changed: info.st_ctimespec)
    }

    public static func == (lhs: FileStamp, rhs: FileStamp) -> Bool {
        lhs.inode == rhs.inode && lhs.size == rhs.size
            && lhs.modified.tv_sec == rhs.modified.tv_sec
            && lhs.modified.tv_nsec == rhs.modified.tv_nsec
            && lhs.changed.tv_sec == rhs.changed.tv_sec
            && lhs.changed.tv_nsec == rhs.changed.tv_nsec
    }
}

/// A stored list held in memory, decoded again only when the file's stamp differs from the one it was read at.
public struct CachedStoredList<Value: Decodable & Sendable>: Sendable {
    /// The file this copy mirrors.
    public let file: URL

    /// The stamp the held value was read or written at, and the value itself; `nil` value is an empty store.
    private var held: (stamp: FileStamp?, value: Value?)?

    /// How many times the file has been decoded, which a test counts.
    public private(set) var diskReads = 0

    /// Goes up whenever the held value is replaced, so anything derived from it knows to rebuild.
    public private(set) var generation = 0

    public init(file: URL) {
        self.file = file
    }

    /// The value on disk, from memory when the file is unchanged; `nil` when missing or unreadable.
    public mutating func load() -> Value? {
        // Stamped before the read, so a write landing during it shows as a change next time.
        let stamp = FileStamp.of(file)
        if let held, held.stamp == stamp { return held.value }
        guard stamp != nil else {
            replace(with: nil, stamp: nil)
            return nil
        }
        diskReads += 1
        let read = LocalStore.read(Value.self, from: file)
        // An unreadable file is not held, so the set-aside path runs exactly as it did before.
        guard !read.isUnreadable else {
            held = nil
            generation += 1
            return nil
        }
        replace(with: read.value, stamp: stamp)
        return read.value
    }

    /// Holds what was just written to the file, or `nil` after the file was removed.
    public mutating func remember(_ value: Value?) {
        replace(with: value, stamp: FileStamp.of(file))
    }

    /// Drops the held value, so the next load reads the file.
    public mutating func forget() {
        held = nil
        generation += 1
    }

    private mutating func replace(with value: Value?, stamp: FileStamp?) {
        held = (stamp, value)
        generation += 1
    }
}
