// Tests that a deleted picture outlives its clip for as long as an undo can bring it back.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Undoing the delete of a picture")
struct PictureUndoTests {
    static let bytes = Data(repeating: 0x89, count: 2_048)

    /// Records one picture and answers with its clip as the panel kept it.
    private func recorded(in folder: borrowing TemporaryFolder) async throws -> Clip {
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()), picture: (Self.bytes, 10, 10))
        _ = try await folder.store.record(noticed, keeping: folder.retention)
        return try #require(await folder.store.clips(keeping: folder.retention).first)
    }

    @Test("a held picture is still there when the clip is restored")
    func restoreBringsThePictureBack() async throws {
        let folder = try TemporaryFolder()
        let clip = try await recorded(in: folder)
        let image = try #require(clip.image)

        _ = try await folder.store.delete(clip.id, keeping: folder.retention, holdingPicture: true)
        await folder.store.forgetOrphanedImages()
        _ = try await folder.store.record(clip, keeping: folder.retention)
        await folder.store.forgetHeldPictures()

        #expect(await folder.store.imageData(for: image) == Self.bytes)
    }

    @Test("a collection delete holds every removed picture for one undo")
    func collectionDeleteHoldsPictures() async throws {
        let folder = try TemporaryFolder()
        let first = try await recorded(in: folder)
        let secondBytes = Data(repeating: 0x90, count: 2_048)
        _ = try await folder.store.record(
            NoticedClip(
                clip: Clip(text: "", kind: .image, copiedAt: Date()),
                picture: (secondBytes, 10, 10)),
            keeping: folder.retention)
        let second = try #require(
            await folder.store.clips(keeping: folder.retention).first { $0.id != first.id })
        try await folder.store.setCategory("Work", of: first.id, keeping: folder.retention)
        try await folder.store.setCategory("Work", of: second.id, keeping: folder.retention)
        let images = [try #require(first.image), try #require(second.image)]

        let removed = try await folder.store.deleteCategoryForUndo(
            "Work", keeping: folder.retention)
        await folder.store.forgetOrphanedImages()

        #expect(removed.count == 2)
        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
        #expect(await folder.store.imageData(for: images[0]) == Self.bytes)
        #expect(await folder.store.imageData(for: images[1]) == secondBytes)
        for clip in removed {
            _ = try await folder.store.restore(clip, keeping: folder.retention)
        }
        await folder.store.forgetHeldPictures()
        let restored = await folder.store.clips(keeping: folder.retention)
        #expect(restored.count == 2)
        #expect(restored.allSatisfy { $0.category == "Work" })
        #expect(await folder.store.imageData(for: images[0]) == Self.bytes)
        #expect(await folder.store.imageData(for: images[1]) == secondBytes)
    }

    @Test("a held picture is removed once the undo is let go")
    func forgettingRemovesTheFile() async throws {
        let folder = try TemporaryFolder()
        let clip = try await recorded(in: folder)
        let image = try #require(clip.image)

        _ = try await folder.store.delete(clip.id, keeping: folder.retention, holdingPicture: true)
        #expect(await folder.store.imageData(for: image) != nil)
        await folder.store.forgetHeldPictures()

        #expect(await folder.store.imageData(for: image) == nil)
    }

    @Test("a delete with nothing to undo removes the picture at once")
    func unheldDeleteRemovesAtOnce() async throws {
        let folder = try TemporaryFolder()
        let clip = try await recorded(in: folder)
        let image = try #require(clip.image)

        _ = try await folder.store.delete(clip.id, keeping: folder.retention)

        #expect(await folder.store.imageData(for: image) == nil)
    }

    @Test("resetting removes a picture held for an undo")
    func resetRemovesAHeldPicture() async throws {
        let folder = try TemporaryFolder()
        let clip = try await recorded(in: folder)
        let image = try #require(clip.image)

        _ = try await folder.store.delete(clip.id, keeping: folder.retention, holdingPicture: true)
        try await folder.store.forgetEverything()

        #expect(await folder.store.imageData(for: image) == nil)
    }
}
