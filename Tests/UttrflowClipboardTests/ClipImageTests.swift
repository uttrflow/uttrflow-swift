import Foundation
import Testing

@testable import UttrflowClipboard

/// K4 — a picture on the clipboard. The tests that matter are about the file: a clip
/// pointing at bytes that were never written is a broken row for ever.
@Suite("K4 · pictures")
struct ClipImageTests {
    /// A store over its own temporary folder, removed with the test.
    struct Folder: ~Copyable {
        let url: URL
        let store: ClipboardStore
        let retention = ClipRetention(days: 7, now: Date())

        init() throws {
            url = URL.temporaryDirectory.appending(
                path: "uttrflow-img-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            store = ClipboardStore(
                file: url.appending(path: "clipboard.json", directoryHint: .notDirectory))
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// Not a real PNG — nothing here decodes it, and a fixture that needed decoding would
    /// be testing the platform rather than this.
    static let bytes = Data(repeating: 0x89, count: 4_096)

    @Test("a picture is written before the clip that refers to it")
    func writtenFirst() async throws {
        let folder = try Folder()
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

    /// The emptiness is the point: a picture has no text, and the rule that keeps blank
    /// copies out of the history must not keep pictures out with them.
    @Test("a picture is kept even though it has no text")
    func emptyTextIsFine() async throws {
        let folder = try Folder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))

        _ = try await folder.store.record(noticed, keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).count == 1)
    }

    /// And the rule still holds for everything else.
    @Test("a blank copy with no picture is still refused")
    func blankStillRefused() async throws {
        let folder = try Folder()

        _ = try await folder.store.record(
            Clip(text: "   \n ", kind: .text, copiedAt: Date()), keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    /// B8 — a picture can vanish underneath the app, because the folder is on a disk the
    /// user also owns. `nil` is the row's cue to say so rather than draw a blank.
    @Test("a picture whose file has gone reads as nothing, and does not crash")
    func vanishedFile() async throws {
        let folder = try Folder()
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
        let folder = try Folder()
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Self.bytes, 10, 10))
        _ = try await folder.store.record(noticed, keeping: folder.retention)
        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first?.image)

        _ = try await folder.store.deleteEverything(keeping: ClipRetention(days: 7, now: Date()))
        await folder.store.forgetOrphanedImages()

        #expect(await folder.store.imageData(for: image) == nil)
    }

    /// The test above sweeps by hand, which is why nobody noticed that nothing else ever
    /// did: `forgetOrphanedImages()` described itself as running after the retention
    /// sweep and was called from nowhere in the app at all, so every deleted or aged-out
    /// picture stayed on disk for ever. This one deletes a clip and asks whether the file
    /// went, without helping.
    @Test("deleting a picture clip takes its file with it, unaided")
    func deletingSweepsWithoutBeingAsked() async throws {
        let folder = try Folder()
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

    /// And the sweep must not take a picture that is still spoken for. Deleting one clip
    /// of two is the case where an over-eager sweep would destroy the other.
    @Test("but not the picture of a clip that is still there")
    func keepsTheOneStillReferred() async throws {
        let folder = try Folder()
        // Two *different* pictures. They used to be allowed to be identical, because
        // identical bytes were two clips; now the same bytes are one clip copied twice,
        // and this test is about two clips sharing a folder rather than a file.
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

    /// The write-time sweep cannot help with what a leaking build already left behind: no
    /// future write drops a name that is already absent from the list. So the store
    /// reconciles the folder once, the first time it reads.
    @Test("a picture orphaned before this launch is cleared on the first read")
    func reconcilesAtStartup() async throws {
        let folder = try Folder()
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

    /// And it must never fire on a read that failed. `read()` answers with nothing for a
    /// file that is missing or unreadable, so an empty list is not evidence that the user
    /// has no pictures — sweeping on one would delete every picture they own.
    @Test("but an unreadable clipboard sweeps nothing at all")
    func aBadReadDestroysNothing() async throws {
        let folder = try Folder()
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
        let folder = try Folder()
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
