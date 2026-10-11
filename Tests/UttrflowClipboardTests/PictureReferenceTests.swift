// Synthetic controls for held pictures across a refused index write and cleanup.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Picture reference lifecycle")
struct PictureReferenceTests {
    @Test("an undo-held picture survives a refused delete, retry and orphan sweep until released")
    func heldPictureSurvivesRetryUntilReleased() async throws {
        let folder = try TemporaryFolder()
        let store = folder.store
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: folder.retention.now),
            picture: (ClipImageTests.bytes, 1024, 768))
        let original = try #require(try await store.record(noticed, keeping: folder.retention).first)
        let image = try #require(original.image)
        let path = folder.url.path
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.delete(original.id, keeping: folder.retention, holdingPicture: true)
        }
        #expect(await store.clips(keeping: folder.retention).isEmpty)
        #expect(await store.hasImage(for: image))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        try await store.record(
            Clip(text: "Later copy", kind: .text, copiedAt: folder.retention.now), keeping: folder.retention)
        await store.forgetOrphanedImages()
        #expect(await store.imageData(for: image) == ClipImageTests.bytes)
        await store.forgetHeldPictures()
        #expect(await store.hasImage(for: image) == false)
        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        #expect(await reopened.clips(keeping: folder.retention).map(\.text) == ["Later copy"])
    }
}
