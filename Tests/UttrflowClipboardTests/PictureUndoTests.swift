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
}
