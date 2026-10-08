import Foundation
import MLXLMCommon
import Testing

@testable import UttrflowLocalModel

private func link(_ path: URL, to target: String) throws {
    try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: target)
}

private func addStaleSnapshot(
    to cache: FakeCache.PinnedCache, revision: String, blobName: String
) throws -> (snapshot: URL, blob: URL) {
    let snapshot = cache.repository.appending(path: "snapshots/\(revision)")
    let blob = cache.blobs.appending(path: blobName)
    try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 16).write(to: blob)
    try link(snapshot.appending(path: "model.safetensors"), to: "../../blobs/\(blob.lastPathComponent)")
    return (snapshot, blob)
}

private func removeSuperseded(_ cache: FakeCache.PinnedCache) -> Bool {
    CachedSnapshot.removeSuperseded(
        identifier: cache.identifier, revision: cache.revision, in: cache.root,
        minimumWeightBytes: FakeCache.minimum)
}

@Suite("Model cache storage")
struct CachedSnapshotStorageTests {
    @Test("Superseded snapshots wait for a whole pinned model and preserve shared blobs")
    func supersededSnapshotWaitsForWholePinnedModel() throws {
        let cache = try FakeCache.PinnedCache()
        let old = try addStaleSnapshot(
            to: cache, revision: String(repeating: "a4", count: 20), blobName: "shared-weight")
        let unshared = try addStaleSnapshot(
            to: cache, revision: String(repeating: "c5", count: 20), blobName: "stale-weight")
        let anotherSnapshot = cache.root.appending(
            path: "models--another-org--model/snapshots/\(String(repeating: "b5", count: 20))")
        try FileManager.default.createDirectory(at: anotherSnapshot, withIntermediateDirectories: true)
        try link(
            anotherSnapshot.appending(path: "shared.safetensors"),
            to: "../../../models--example-org--pinned-model/blobs/shared-weight")

        #expect(!removeSuperseded(cache))
        #expect(FileManager.default.fileExists(atPath: old.snapshot.path))
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let bytesBeforeCleanup = try #require(cache.model().cachedBytes(in: cache.root))
        let currentBlob = cache.snapshot.appending(path: "model.safetensors").resolvingSymlinksInPath()
        #expect(removeSuperseded(cache))
        #expect(!FileManager.default.fileExists(atPath: old.snapshot.path))
        #expect(!FileManager.default.fileExists(atPath: unshared.snapshot.path))
        #expect(FileManager.default.fileExists(atPath: old.blob.path))
        #expect(!FileManager.default.fileExists(atPath: unshared.blob.path))
        #expect(FileManager.default.fileExists(atPath: currentBlob.path))
        let bytesAfterCleanup = try #require(cache.model().cachedBytes(in: cache.root))
        #expect(bytesBeforeCleanup - bytesAfterCleanup == 16)
    }

    @Test("Pruning preserves a blob referenced below a current snapshot directory")
    func pruningPreservesNestedSnapshotBlobReference() throws {
        let cache = try FakeCache.PinnedCache()
        let stale = try addStaleSnapshot(
            to: cache, revision: String(repeating: "f8", count: 20), blobName: "nested-shared")
        let nested = cache.snapshot.appending(path: "nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try link(nested.appending(path: "weight.safetensors"), to: "../../../blobs/nested-shared")
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))

        #expect(removeSuperseded(cache))
        #expect(!FileManager.default.fileExists(atPath: stale.snapshot.path))
        #expect(FileManager.default.fileExists(atPath: stale.blob.path))
    }

    @Test("Failed cache scan preserves every superseded snapshot")
    func failedCacheScanPreservesSnapshots() throws {
        let cache = try FakeCache.PinnedCache()
        let revisions = [String(repeating: "a4", count: 20), String(repeating: "d6", count: 20)]
        let stale = try revisions.map {
            try addStaleSnapshot(to: cache, revision: $0, blobName: "\($0).safetensors")
        }
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let unreadable = cache.snapshot.appending(path: "nested")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)

        #expect(!removeSuperseded(cache))
        for item in stale {
            #expect(FileManager.default.fileExists(atPath: item.snapshot.path))
            #expect(FileManager.default.fileExists(atPath: item.blob.path))
        }
    }

    @Test("Pruning removes stale snapshot links without deleting files in another repository")
    func pruningPreservesFilesOutsideRepositoryBlobs() throws {
        let cache = try FakeCache.PinnedCache()
        let revision = String(repeating: "e7", count: 20)
        let staleSnapshot = cache.repository.appending(path: "snapshots/\(revision)")
        try FileManager.default.createDirectory(at: staleSnapshot, withIntermediateDirectories: true)
        let otherRepositoryBlobs = cache.root.appending(path: "models--other-org--model/blobs")
        try FileManager.default.createDirectory(
            at: otherRepositoryBlobs, withIntermediateDirectories: true)
        let otherRepositoryFile = otherRepositoryBlobs.appending(path: "outside-weight")
        try Data(repeating: 9, count: 16).write(to: otherRepositoryFile)
        try link(
            staleSnapshot.appending(path: "model.safetensors"),
            to: "../../../models--other-org--model/blobs/outside-weight")
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))

        #expect(removeSuperseded(cache))
        #expect(!FileManager.default.fileExists(atPath: staleSnapshot.path))
        #expect(FileManager.default.fileExists(atPath: otherRepositoryFile.path))
    }

    @Test("Cache usage returns nil for unreadable contents and removal deletes the repository")
    func cacheUsageAndRemoval() throws {
        let cache = try FakeCache.PinnedCache()
        try cache.add("weight.safetensors", Data(repeating: 7, count: 40))
        #expect(cache.model().cachedBytes(in: cache.root) == 40)
        let unreadable = cache.repository.appending(path: "unreadable")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        #expect(cache.model().cachedBytes(in: cache.root) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        try cache.model().removeCachedFiles(in: cache.root)
        #expect(!FileManager.default.fileExists(atPath: cache.repository.path))
    }

    @Test("Cache removal rejects aliased roots, dangling repositories, and snapshot symlinks")
    func removalRejectsAliasedAndLinkedPaths() throws {
        let cache = try FakeCache.PinnedCache()
        let alias = FileManager.default.temporaryDirectory.appending(path: "cache-alias-\(UUID().uuidString)")
        try link(alias, to: cache.root.path)
        #expect(throws: (any Error).self) { try cache.model().removeCachedFiles(in: alias) }

        let missing = cache.root.appending(path: "missing")
        try FileManager.default.removeItem(at: cache.repository)
        try link(cache.repository, to: missing.path)
        #expect(throws: (any Error).self) { try cache.model().removeCachedFiles(in: cache.root) }
        try FileManager.default.removeItem(at: cache.repository)
        try FileManager.default.createDirectory(at: cache.blobs, withIntermediateDirectories: true)
        let snapshots = cache.repository.appending(path: "snapshots")
        try link(snapshots, to: missing.path)
        #expect(throws: (any Error).self) { try cache.model().removeCachedFiles(in: cache.root) }
    }

    @Test("Cache removal rejects a nonwritable repository")
    func removalRejectsNonwritableRepository() throws {
        let cache = try FakeCache.PinnedCache()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: cache.repository.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cache.repository.path)
        #expect(throws: (any Error).self) { try cache.model().removeCachedFiles(in: cache.root) }
        #expect(FileManager.default.fileExists(atPath: cache.snapshot.path))
    }
}
