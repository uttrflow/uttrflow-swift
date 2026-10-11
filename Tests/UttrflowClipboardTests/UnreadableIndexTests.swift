// Tests that an index the store could not read never costs a picture or its own bytes.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A damaged index is kept aside and sweeps nothing, because a failed read is not evidence of an orphan.
@Suite("An unreadable index destroys nothing")
struct UnreadableIndexTests {
    /// The ways a file on disk stops being readable, each applied to the bytes the store wrote.
    enum Damage: String, CaseIterable, Sendable {
        case corrupt, truncated, empty, permissionDenied
    }

    /// The index whose unreadable bytes cannot be set aside.
    enum IndexFile: String, CaseIterable, Sendable {
        case history, saved
    }

    /// A pinned picture clip and an ordinary copy, so the history file holds something besides.
    private func seeded(_ folder: borrowing TemporaryFolder) async throws -> ClipImage {
        let pinned = Clip(text: "", kind: .image, copiedAt: Date().addingTimeInterval(-10))
        try await folder.store.record(
            NoticedClip(clip: pinned, picture: (ClipImageTests.bytes, 1, 1)),
            keeping: folder.retention)
        try await folder.store.setPinned(true, of: pinned.id, keeping: folder.retention)
        try await folder.store.record(
            Clip(text: "ordinary copy", kind: .text, copiedAt: Date()), keeping: folder.retention)
        return try #require(
            await folder.store.clips(keeping: folder.retention).first { $0.isPinned }?.image)
    }

    /// Damages a file in place and answers with the bytes that are now on disk.
    private func damage(_ url: URL, with damage: Damage) throws -> Data {
        let original = try Data(contentsOf: url)
        let bytes: Data
        switch damage {
        case .corrupt: bytes = Data("{ not json".utf8)
        case .truncated: bytes = original.prefix(original.count / 2)
        case .empty: bytes = Data()
        case .permissionDenied: bytes = original
        }
        try bytes.write(to: url)
        if damage == .permissionDenied {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        }
        return bytes
    }

    /// The bytes of the file set aside for `name`, readable again whatever permissions it carried.
    private func setAside(_ name: String, in folder: URL) throws -> Data? {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let aside = names.first(where: { $0.hasPrefix("\(name).unreadable-") }) else {
            return nil
        }
        let url = folder.appending(path: aside, directoryHint: .notDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try Data(contentsOf: url)
    }

    @Test("a pinned clip's picture survives a saved file that cannot be read", arguments: Damage.allCases)
    func savedFilePicturesSurvive(_ kind: Damage) async throws {
        let folder = try TemporaryFolder()
        let image = try await seeded(folder)
        let saved = await folder.store.savedFile
        let bytes = try damage(saved, with: kind)

        // A relaunch reads, and then an ordinary copy writes.
        let next = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        _ = await next.clips(keeping: folder.retention)
        #expect(await next.imageData(for: image) != nil)
        try await next.record(
            Clip(text: "a later copy", kind: .text, copiedAt: Date()), keeping: folder.retention)
        await next.forgetOrphanedImages()
        #expect(await next.imageData(for: image) != nil)

        // The damaged bytes are kept aside, not written over, so the pin can still be recovered.
        #expect(try setAside("saved.v1.json", in: folder.url) == bytes)

        // And the launch after that still does not sweep while the damaged file is kept.
        _ = await ClipboardStore(file: folder.url.appending(path: "clipboard.json")).clips(
            keeping: folder.retention)
        #expect(await next.imageData(for: image) != nil)
    }

    @Test("a history picture survives a history file that cannot be read", arguments: Damage.allCases)
    func historyFilePicturesSurvive(_ kind: Damage) async throws {
        let folder = try TemporaryFolder()
        _ = try await seeded(folder)
        let picture = Clip(text: "", kind: .image, copiedAt: Date())
        try await folder.store.record(
            NoticedClip(clip: picture, picture: (Data(repeating: 7, count: 64), 1, 1)),
            keeping: folder.retention)
        let image = try #require(
            await folder.store.clips(keeping: folder.retention).first { $0.id == picture.id }?.image)
        let file = folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory)
        let bytes = try damage(file, with: kind)

        let next = ClipboardStore(file: file)
        _ = await next.clips(keeping: folder.retention)
        try await next.record(
            Clip(text: "a later copy", kind: .text, copiedAt: Date()), keeping: folder.retention)

        #expect(await next.imageData(for: image) != nil)
        #expect(try setAside("clipboard.json", in: folder.url) == bytes)
    }

    @Test("a saved file that can be neither read nor moved aside is never written over")
    func unmovableFileIsNotReplaced() async throws {
        let folder = try TemporaryFolder()
        let image = try await seeded(folder)
        let saved = await folder.store.savedFile
        let bytes = try damage(saved, with: .corrupt)

        // The folder refuses the rename during the read, then accepts writes again.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.url.path)
        let next = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        _ = await next.clips(keeping: folder.retention)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.url.path)

        let fresh = Clip(text: "pin me", kind: .text, copiedAt: Date())
        try await next.record(fresh, keeping: folder.retention)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await next.setPinned(true, of: fresh.id, keeping: folder.retention)
        }
        #expect(try Data(contentsOf: saved) == bytes)
        #expect(await next.imageData(for: image) != nil)
    }

    @Test(
        "forgetting refuses to partially erase around an unreplaceable index", arguments: IndexFile.allCases)
    func forgetDoesNotPartiallyErase(_ indexFile: IndexFile) async throws {
        let folder = try TemporaryFolder()
        _ = try await seeded(folder)
        let history = folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory)
        let saved = await folder.store.savedFile
        let unreadable: URL
        switch indexFile {
        case .history: unreadable = history
        case .saved: unreadable = saved
        }
        _ = try damage(unreadable, with: .corrupt)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.url.path)
        let store = ClipboardStore(file: history)
        _ = await store.clips(keeping: folder.retention)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.url.path)

        let historyBytes = try Data(contentsOf: history)
        let savedBytes = try Data(contentsOf: saved)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.forgetEverything()
        }
        #expect(try Data(contentsOf: history) == historyBytes)
        #expect(try Data(contentsOf: saved) == savedBytes)
    }

    @Test("a missing saved file is not unreadable, so a real orphan is still swept")
    func missingIsNotUnreadable() async throws {
        let folder = try TemporaryFolder()
        _ = try await folder.store.record(
            Clip(text: "something", kind: .text, copiedAt: Date()), keeping: folder.retention)
        let images = await folder.store.imagesFolder
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let stray = ClipImage(file: "stray.png", width: 1, height: 1, bytes: 4)
        try ClipImageTests.bytes.write(to: images.appending(path: stray.file))

        let next = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        _ = await next.clips(keeping: folder.retention)

        #expect(await next.imageData(for: stray) == nil)
    }
}
