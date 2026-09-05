// Tests for picture clips and their files.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A picture on the clipboard; a clip pointing at bytes never written is a broken row for ever.
@Suite("K4 · pictures")
struct ClipImageTests {
    /// Not a real PNG, because nothing here decodes it.
    static let bytes = Data(repeating: 0x89, count: 4_096)

    @Test("a picture is written before the clip that refers to it")
    func writtenFirst() async throws {
        let folder = try TemporaryFolder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 1024, 768))

        _ = try await folder.store.record(noticed, keeping: folder.retention)

        let clips = await folder.store.clips(keeping: folder.retention)
        let image = try #require(clips.first?.image)
        #expect(image.width == 1024)
        #expect(image.height == 768)
        #expect(image.bytes == 4_096)
        #expect(await folder.store.imageData(for: image) == Self.bytes)
    }

    /// A picture has no text, and the rule that keeps blank copies out must not keep pictures out.
    @Test("a picture is kept even though it has no text")
    func emptyTextIsFine() async throws {
        let folder = try TemporaryFolder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))

        _ = try await folder.store.record(noticed, keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).count == 1)
    }

    /// And the rule still holds for everything else.
    @Test("a blank copy with no picture is still refused")
    func blankStillRefused() async throws {
        let folder = try TemporaryFolder()

        _ = try await folder.store.record(
            Clip(text: "   \n ", kind: .text, copiedAt: Date()), keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    /// A picture can vanish underneath the app; `nil` is the row's cue to say so.
    @Test("a picture whose file has gone reads as nothing, and does not crash")
    func vanishedFile() async throws {
        let folder = try TemporaryFolder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))
        _ = try await folder.store.record(noticed, keeping: folder.retention)
        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first?.image)

        try FileManager.default.removeItem(
            at: await folder.store.imagesFolder.appending(path: image.file))

        #expect(await folder.store.imageData(for: image) == nil)
        // The clip is still listed: the record is intact, only the bytes are gone.
        #expect(await folder.store.clips(keeping: folder.retention).count == 1)
    }

    /// A picture left behind by a clip that aged out would sit on disk for ever.
    @Test("pictures no clip refers to are swept up")
    func orphansAreForgotten() async throws {
        let folder = try TemporaryFolder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))
        _ = try await folder.store.record(noticed, keeping: folder.retention)
        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first?.image)

        _ = try await folder.store.deleteEverything(keeping: folder.retention)
        await folder.store.forgetOrphanedImages()

        #expect(await folder.store.imageData(for: image) == nil)
    }

    /// Deleting a clip must take its file with it unaided, without a sweep called by hand.
    @Test("deleting a picture clip takes its file with it, unaided")
    func deletingSweepsWithoutBeingAsked() async throws {
        let folder = try TemporaryFolder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))
        _ = try await folder.store.record(noticed, keeping: folder.retention)
        let stored = try #require(await folder.store.clips(keeping: folder.retention).first)
        let image = try #require(stored.image)
        #expect(await folder.store.imageData(for: image) != nil)

        _ = try await folder.store.delete(stored.id, keeping: folder.retention)

        #expect(await folder.store.imageData(for: image) == nil)
    }

    /// The sweep must not take a picture that is still spoken for.
    @Test("but not the picture of a clip that is still there")
    func keepsTheOneStillReferred() async throws {
        let folder = try TemporaryFolder()
        // Two different pictures, since the same bytes are one clip copied twice.
        for byte in [UInt8(3), UInt8(4)] {
            _ = try await folder.store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (Data(repeating: byte, count: Self.bytes.count), 10, 10)),
                keeping: folder.retention)
        }
        let both = await folder.store.clips(keeping: folder.retention)
        #expect(both.count == 2)
        let surviving = try #require(both.last?.image)

        _ = try await folder.store.delete(try #require(both.first).id, keeping: folder.retention)

        #expect(await folder.store.imageData(for: surviving) != nil)
    }

    /// A leak from an earlier build is reconciled once, the first time the store reads.
    @Test("a picture orphaned before this launch is cleared on the first read")
    func reconcilesAtStartup() async throws {
        let folder = try TemporaryFolder()
        _ = try await folder.store.record(
            Clip(text: "something", kind: .text, copiedAt: Date()), keeping: folder.retention)
        let stray = ClipImage(file: "stray.png", width: 1, height: 1, bytes: 4)
        try FileManager.default.createDirectory(
            at: await folder.store.imagesFolder, withIntermediateDirectories: true)
        try Self.bytes.write(
            to: await folder.store.imagesFolder.appending(
                path: stray.file, directoryHint: .notDirectory))

        // A second store over the same folder, which is what the next launch is.
        let next = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory))
        _ = await next.clips(keeping: folder.retention)

        #expect(await next.imageData(for: stray) == nil)
    }

    /// A failed read must never sweep: an empty list is not evidence the user has no pictures.
    @Test("but an unreadable clipboard sweeps nothing at all")
    func aBadReadDestroysNothing() async throws {
        let folder = try TemporaryFolder()
        _ = try await folder.store.record(
            NoticedClip(
                clip: Clip(text: "", kind: .image, copiedAt: Date()),
                picture: (Self.bytes, 10, 10)),
            keeping: folder.retention)
        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first?.image)

        // The clipboard file becomes unreadable; the pictures folder is untouched.
        let file = folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory)
        try Data("not json".utf8).write(to: file)
        let next = ClipboardStore(file: file)
        #expect(await next.clips(keeping: folder.retention).isEmpty)

        #expect(await next.imageData(for: image) != nil)
    }

    /// The file name is relative, so moving the folder keeps the pictures with the clips.
    @Test("the file is named relative to the clipboard, never absolutely")
    func relativeName() async throws {
        let folder = try TemporaryFolder()
        let id = UUID()

        let image = try await folder.store.keep(Self.bytes, forClip: id, width: 1, height: 1)

        #expect(image.file == "\(id.uuidString).png")
        #expect(!image.file.contains("/"))
    }

    @Test("dimensions read as a size, with a multiplication sign")
    func dimensionsRead() {
        #expect(ClipImage(file: "x", width: 1024, height: 768, bytes: 0).dimensions == "1024 × 768")
    }
}
