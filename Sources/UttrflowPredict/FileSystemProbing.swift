public import struct Foundation.Date

private import Synchronization

/// What a path names on disk, as far as a check that never runs a program can tell.
public enum PathKind: Sendable, Equatable {
    /// Nothing is there.
    case missing
    /// A directory, which is what `cd` needs.
    case directory
    /// Anything that is not a directory, and whether this user may execute it.
    case file(executable: Bool)
    /// The disk did not answer in time or refused the question, which is never taken as existence.
    case unknown
}

/// The filesystem as terminal verification reads it: a stat, a bounded read, a bounded listing, and nothing that runs a program.
public protocol FileSystemProbing: Sendable {
    /// What one absolute path names.
    func kind(atPath path: String) -> PathKind

    /// A small text file's contents, absent when it is missing, unreadable or longer than `limit` bytes.
    func contents(ofFile path: String, limit: Int) -> String?

    /// The names in one directory, absent when it cannot be listed or holds more than `limit`.
    func names(inDirectory path: String, limit: Int) -> [String]?

    /// The user's home directory, which `~` and `$HOME` stand for.
    var homeDirectory: String { get }

    /// The absolute directories a command name is looked for in, in order.
    var searchPaths: [String] { get }
}

/// A filesystem whose stats and reads are believed for a moment, so a burst of keystrokes asks the disk once.
public final class CachedFileSystem: FileSystemProbing {
    /// How long an answer is believed, short enough that a directory made a moment ago is found.
    public static let lifetimeInSeconds = 2.0

    /// How many answers are held before the oldest are forgotten.
    static let capacity = 1_024

    /// One remembered answer and when it stops being believed.
    private struct Held<Value: Sendable>: Sendable {
        let value: Value
        let expires: Date
    }

    /// The disk behind the cache.
    private let inner: any FileSystemProbing
    /// The clock the lifetime is measured on, injected so a test decides when an answer goes stale.
    private let now: @Sendable () -> Date
    /// What each path last named.
    private let kinds = Mutex<[String: Held<PathKind>]>([:])
    /// What each small file last held.
    private let texts = Mutex<[String: Held<String?>]>([:])

    /// A cache over one filesystem, on the given clock.
    public init(_ inner: any FileSystemProbing, now: @escaping @Sendable () -> Date = { Date() }) {
        self.inner = inner
        self.now = now
    }

    public var homeDirectory: String { inner.homeDirectory }

    public var searchPaths: [String] { inner.searchPaths }

    public func kind(atPath path: String) -> PathKind {
        let moment = now()
        if let held = kinds.withLock({ $0[path] }), held.expires > moment { return held.value }
        let kind = inner.kind(atPath: path)
        kinds.withLock { Self.store(kind, for: path, in: &$0, at: moment) }
        return kind
    }

    public func contents(ofFile path: String, limit: Int) -> String? {
        let key = "\(limit)\u{0}\(path)"
        let moment = now()
        if let held = texts.withLock({ $0[key] }), held.expires > moment { return held.value }
        let text = inner.contents(ofFile: path, limit: limit)
        texts.withLock { Self.store(text, for: key, in: &$0, at: moment) }
        return text
    }

    public func names(inDirectory path: String, limit: Int) -> [String]? {
        inner.names(inDirectory: path, limit: limit)
    }

    /// Holds one answer, emptying the table first when it is full, since a full table is a burst that is over.
    private static func store<Value>(
        _ value: Value, for key: String, in table: inout [String: Held<Value>], at moment: Date
    ) {
        if table.count >= capacity { table.removeAll(keepingCapacity: true) }
        table[key] = Held(value: value, expires: moment.addingTimeInterval(lifetimeInSeconds))
    }
}
