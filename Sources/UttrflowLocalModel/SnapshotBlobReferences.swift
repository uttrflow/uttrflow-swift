import Foundation

extension CachedSnapshot {
    static func snapshotBlobReferences(
        in cacheRoot: URL, excluding excludedRepository: URL? = nil,
        excludingSnapshots: Set<String> = []
    ) -> Set<String>? {
        guard
            let repositories = try? FileManager.default.contentsOfDirectory(
                at: cacheRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return nil }
        var references: Set<String> = []
        for repository in repositories where repository.lastPathComponent.hasPrefix("models--") {
            guard isDirectory(repository) else { return nil }
            if repository.standardizedFileURL == excludedRepository { continue }
            let snapshots = repository.appending(path: "snapshots", directoryHint: .isDirectory)
            guard let snapshotsExist = pathExistsIncludingDanglingSymlink(snapshots) else { return nil }
            guard snapshotsExist else { continue }
            guard isDirectory(snapshots),
                let revisions = try? FileManager.default.contentsOfDirectory(
                    at: snapshots, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            else { return nil }
            for revision in revisions {
                guard
                    let values = try? revision.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
                    values.isSymbolicLink != true
                else { return nil }
                guard values.isDirectory == true else { continue }
                if excludingSnapshots.contains(revision.standardizedFileURL.path) { continue }
                guard let blobs = blobReferences(in: revision, cacheRoot: cacheRoot) else { return nil }
                references.formUnion(blobs)
            }
        }
        return references
    }

    static func blobReferences(in snapshot: URL, cacheRoot: URL) -> Set<String>? {
        var references: Set<String> = []
        var directories = [snapshot]
        while let directory = directories.popLast() {
            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            else { return nil }
            for entry in entries {
                guard
                    let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                else { return nil }
                if values.isSymbolicLink == true {
                    let resolved = canonical(entry)
                    guard
                        resolved.pathComponents.starts(with: cacheRoot.pathComponents),
                        resolved != cacheRoot
                    else { continue }
                    references.insert(resolved.path)
                } else if values.isDirectory == true {
                    directories.append(entry)
                }
            }
        }
        return references
    }
}
