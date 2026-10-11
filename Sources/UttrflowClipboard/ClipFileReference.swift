// A copied file kept as a reference, never as a copy of its contents.

public import Foundation

/// One file from a file-manager copy; the path names it and the bookmark finds it again after a move.
public struct ClipFileReference: Sendable, Equatable, Codable {
    /// The absolute path when the file was copied.
    public let path: String
    /// A bookmark to the file, or `nil` when macOS could not make one.
    public let bookmark: Data?

    init(path: String, bookmark: Data? = nil) {
        self.path = path
        self.bookmark = bookmark
    }

    /// A reference to the file at `url`, with a bookmark when macOS makes one.
    init(url: URL) {
        self.init(path: url.path(percentEncoded: false), bookmark: try? url.bookmarkData())
    }

    /// The file's name, as the row and its accessibility label say it.
    var name: String { URL(filePath: path).lastPathComponent }

    /// Where the file is now, or `nil` when it has gone or cannot be read.
    func resolved() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
                Self.isReadable(url)
            {
                return url
            }
        }
        let url = URL(filePath: path)
        return Self.isReadable(url) ? url : nil
    }

    private static func isReadable(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false))
    }
}

/// Whether every file of a copied selection can still be put back.
enum ClipFileResolution: Sendable, Equatable {
    /// Every file, in copy order.
    case available([URL])
    /// The names of the files that are gone or unreadable; none of the selection is used.
    case unavailable([String])

    /// All or nothing: one missing file refuses the whole selection.
    static func resolving(_ references: [ClipFileReference]) -> ClipFileResolution {
        let found = references.map { ($0, $0.resolved()) }
        let missing = found.filter { $0.1 == nil }.map { $0.0.name }
        guard missing.isEmpty else { return .unavailable(missing) }
        return .available(found.compactMap(\.1))
    }
}
