// Creating this app's own folders and files so nothing else on the Mac can read them.

public import struct Foundation.Data
public import struct Foundation.URL
public import class Foundation.FileManager

/// Writes what a local store keeps so only its owner can read it. See `Docs/local-store-permissions.md`.
public enum PrivateFile {
    /// The mode a folder this app makes is created with: its owner alone may read, write and enter it.
    public static let directoryMode = 0o700

    /// The mode a file this app writes ends up with: its owner alone may read and write it.
    public static let fileMode = 0o600

    /// Makes `directory` and its parents if they are not there, and takes group and other off `directory`.
    public static func makeDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryMode])
        // A folder that was already there keeps its own mode through `createDirectory`.
        try keepToOwner(directory)
    }

    /// Writes `data` to `url` atomically, inside a folder and under a mode only its owner can read.
    public static func write(_ data: Data, to url: URL) throws {
        try makeDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        // An atomic write replaces the file, so the mode is set on what the rename left behind.
        try keepToOwner(url)
    }

    /// Takes group and other off bytes this app did not write, such as SQLite's own database file.
    public static func tighten(at url: URL) throws {
        try keepToOwner(url)
    }

    /// Removes every permission but the owner's, and never gives back one the owner took away.
    private static func keepToOwner(_ url: URL) throws {
        let path = url.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let mode = attributes[.posixPermissions] as? Int, mode & 0o077 != 0 else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: mode & 0o700], ofItemAtPath: path)
    }
}
