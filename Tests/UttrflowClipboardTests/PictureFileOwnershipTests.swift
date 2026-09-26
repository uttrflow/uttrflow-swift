// Tests that every picture file written for a clip has an owner, whatever happens to the clip.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A picture written for a clip that never reaches an index would otherwise sit on disk for ever.
@Suite("A picture file outlives no clip")
struct PictureFileOwnershipTests {
    /// Two bytes, because the store never decodes these and the disk budget is what is under test.
    static func picture(_ byte: UInt8) -> NoticedClip {
        NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Data(repeating: byte, count: 2), 10, 10))
    }

    /// Every file in a store's pictures folder, and what they cost together.
    static func onDisk(_ store: ClipboardStore) async throws -> (names: [String], bytes: Int) {
        let folder = await store.imagesFolder
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        let bytes = try names.reduce(0) {
            try $0 + Data(contentsOf: folder.appending(path: $1, directoryHint: .notDirectory)).count
        }
        return (names, bytes)
    }

    @Test("a picture the disk budget drops the moment it arrives leaves nothing behind")
    func immediateEvictionTakesTheFile() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json", directoryHint: .notDirectory),
            budget: .standard.limiting(disk: 1))

        for byte in [UInt8(1), 2, 3] {
            #expect(try await store.record(Self.picture(byte), keeping: folder.retention).isEmpty)
        }

        let after = try await Self.onDisk(store)
        #expect(after.names.isEmpty)
        #expect(after.bytes == 0)
    }

    @Test("and the next launch finds no picture to reconcile, empty index or not")
    func immediateEvictionSurvivesARelaunch() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "c.json", directoryHint: .notDirectory)
        let store = ClipboardStore(file: file, budget: .standard.limiting(disk: 1))
        for byte in [UInt8(1), 2, 3] {
            _ = try await store.record(Self.picture(byte), keeping: folder.retention)
        }

        let next = ClipboardStore(file: file, budget: .standard.limiting(disk: 1))
        #expect(await next.clips(keeping: folder.retention).isEmpty)

        #expect(try await Self.onDisk(next).names.isEmpty)
    }

    /// A trustworthy read that found nothing is evidence of no clips, so its orphans are real orphans.
    @Test("an index that is honestly empty still has its orphans swept")
    func anEmptyIndexStillSweeps() async throws {
        let folder = try TemporaryFolder()
        let images = await folder.store.imagesFolder
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let stray = ClipImage(file: "stray.png", width: 1, height: 1, bytes: 2)
        try Data(repeating: 9, count: 2).write(
            to: images.appending(path: stray.file, directoryHint: .notDirectory))

        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)

        #expect(await folder.store.imageData(for: stray) == nil)
    }

    /// A dropped entry leaves the index unchanged, so nothing is written, and the file still goes.
    @Test("a picture dropped by a budget in a folder that refuses writes is not left on disk")
    func refusedIndexWriteStillTakesADroppedPicture() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json", directoryHint: .notDirectory),
            budget: .standard.limiting(disk: 1))
        _ = try await store.record(
            Clip(text: "a copy that survives", kind: .text, copiedAt: Date()),
            keeping: folder.retention)
        try FileManager.default.createDirectory(
            at: await store.imagesFolder, withIntermediateDirectories: true)
        // A folder that takes no new file is an index write the store cannot land.
        let path = folder.url.path
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }

        let kept = try await store.record(Self.picture(1), keeping: folder.retention)

        #expect(kept.map(\.text) == ["a copy that survives"])

        #expect(try await Self.onDisk(store).names.isEmpty)
    }

    /// A refused write leaves the clip in memory, and a row the panel shows must still have its bytes.
    @Test("but a picture the index refused is kept for the clip in memory, and swept the next launch")
    func refusedIndexWriteKeepsAPictureItsClipStillWants() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "c.json", directoryHint: .notDirectory)
        let store = ClipboardStore(file: file)
        _ = try await store.record(Self.picture(1), keeping: folder.retention)
        let path = folder.url.path
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(Self.picture(2), keeping: folder.retention)
        }
        let refused = try #require(await store.clips(keeping: folder.retention).first?.image)
        #expect(await store.imageData(for: refused) != nil, "the panel can still show the row")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)

        let next = ClipboardStore(file: file)
        _ = await next.clips(keeping: folder.retention)

        #expect(await next.imageData(for: refused) == nil)
        #expect(try await Self.onDisk(next).names.count == 1, "and the clip that did land keeps its own")
    }

    /// The other half of the rule: a picture the budget does keep must still be there to show.
    @Test("a picture the budget keeps is left exactly where its clip points")
    func aKeptPictureStays() async throws {
        let folder = try TemporaryFolder()

        _ = try await folder.store.record(Self.picture(1), keeping: folder.retention)

        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first?.image)
        let after = try await Self.onDisk(folder.store)
        #expect(after.names == [image.file])
        #expect(after.bytes == 2)
    }
}
