// Creating this app's own folders and files so nothing else on the Mac can read them.

public import struct Foundation.Data
public import struct Foundation.URL
public import class Foundation.FileManager

/// Writes what a local store keeps so only its owner can read it. See `Docs/local-store-permissions.md`.
public enum PrivateFile {
    /// The mode a folder this app makes is created with: its owner alone may read, write and enter it.
    public static let directoryMode = 0o700

    /// The mode a file this app writes is created with: its owner alone may read and write it.
    public static let fileMode = 0o600

    /// Makes `directory` and its parents if they are not there, and takes group and other off `directory`.
    public static func makeDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryMode])
        // A folder that was already there keeps its own mode through `createDirectory`.
        try tighten(at: directory)
    }

    /// Writes `data` to `url` atomically, keeping the owner's own bits where the file already had some.
    public static func write(_ data: Data, to url: URL) throws {
        try makeDirectory(at: url.deletingLastPathComponent())
        // Read first: an atomic write replaces the file, and the replacement is the umask's, not the old file's.
        let kept = (try? mode(at: url)).map { $0 & 0o700 }
        try data.write(to: url, options: .atomic)
        try set(kept ?? fileMode, at: url)
    }

    /// Takes group and other off bytes this app did not write, such as SQLite's own database file.
    public static func tighten(at url: URL) throws {
        let current = try mode(at: url)
        guard current & 0o077 != 0 else { return }
        try set(current & 0o700, at: url)
    }

    /// What is on whatever is at `url`, which throws when nothing is.
    private static func mode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return attributes[.posixPermissions] as? Int ?? fileMode
    }

    private static func set(_ mode: Int, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
}
