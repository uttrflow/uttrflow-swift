// Creating this app's own folders and files so nothing else on the Mac can read them.

import Darwin
public import struct Foundation.Data
public import struct Foundation.URL
public import struct Foundation.URLResourceValues
public import struct Foundation.UUID
public import class Foundation.FileManager

/// Writes what a local store keeps so only its owner can read it. See `Docs/local-store-permissions.md`.
public enum PrivateFile {
    private struct SystemError: Error {
        let code: Int32
    }

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
        try? excludeFromBackup(at: directory)
    }

    /// Writes `data` to `url` atomically, keeping the owner's own bits where the file already had some.
    public static func write(_ data: Data, to url: URL) throws {
        try makeDirectory(at: url.deletingLastPathComponent())
        let kept = (try? mode(at: url)).map { $0 & 0o700 } ?? fileMode
        try writeAtomically(data, to: url, mode: kept)
    }

    /// The sealed previous generation, stored beside the live file and bound to the live name.
    static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("bak")
    }

    /// Durably saves already-authenticated bytes before the live generation is replaced.
    static func preserveSealedGeneration(_ data: Data, from url: URL) throws {
        try makeDirectory(at: url.deletingLastPathComponent())
        try writeAtomically(data, to: backupURL(for: url), mode: fileMode)
    }

    /// Restores bytes already authenticated using the live file's logical name.
    static func restore(_ data: Data, to url: URL) throws {
        try makeDirectory(at: url.deletingLastPathComponent())
        let kept = (try? mode(at: url)).map { $0 & 0o700 } ?? fileMode
        try writeAtomically(data, to: url, mode: kept)
    }

    private static func writeAtomically(_ data: Data, to url: URL, mode: Int) throws {
        let folder = url.deletingLastPathComponent()
        let temporary = folder.appending(
            path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        let descriptor = open(
            temporary.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode_t(fileMode))
        guard descriptor >= 0 else { throw posixError() }
        var descriptorIsOpen = true
        var shouldRemoveTemporary = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
            if shouldRemoveTemporary { _ = unlink(temporary.path(percentEncoded: false)) }
        }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        guard fchmod(descriptor, mode_t(mode)) == 0 else { throw posixError() }
        try synchronizeFile(descriptor)
        guard Darwin.close(descriptor) == 0 else {
            descriptorIsOpen = false
            throw posixError()
        }
        descriptorIsOpen = false

        guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0
        else { throw posixError() }
        shouldRemoveTemporary = false
        try? excludeFromBackup(at: url)
        try synchronizeDirectory(at: folder)
    }

    private static func synchronizeFile(_ descriptor: Int32) throws {
        #if os(macOS)
            if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
            guard errno == EINVAL || errno == ENOTSUP || errno == ENOTTY else { throw posixError() }
        #endif
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    static func synchronizeDirectory(at directory: URL) throws {
        let descriptor = open(directory.path(percentEncoded: false), O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    /// Replaces a chosen export with a sibling file created owner-only before its bytes are written.
    public static func writeOwnerOnlyAtomically(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appending(
            path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(
            temporary.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode_t(fileMode))
        guard descriptor >= 0 else { throw posixError() }
        var shouldRemoveTemporary = true
        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
            if shouldRemoveTemporary { _ = unlink(temporary.path(percentEncoded: false)) }
        }
        guard fchmod(descriptor, mode_t(fileMode)) == 0 else { throw posixError() }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        let closeResult = Darwin.close(descriptor)
        descriptorIsOpen = false
        guard closeResult == 0 else { throw posixError() }
        guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0
        else { throw posixError() }
        shouldRemoveTemporary = false
    }

    /// Takes group and other off bytes this app did not write, such as SQLite's own database file.
    public static func tighten(at url: URL) throws {
        let current = try mode(at: url)
        guard current & 0o077 != 0 else { return }
        try set(current & 0o700, at: url)
    }

    /// Keeps a local store path out of backup systems that honour Finder's exclusion flag.
    public static func excludeFromBackup(at url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
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

    private static func posixError() -> SystemError {
        SystemError(code: errno)
    }
}
