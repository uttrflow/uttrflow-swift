// Tests for the permanent file saved clips move to.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Saving a clip has to mean somewhere permanent, not merely somewhere exempt from eviction.
@Suite("Anything saved is kept somewhere permanent")
struct SavedClipsTests {
    private func clip(_ text: String, at offset: TimeInterval = 0) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon.addingTimeInterval(offset), source: "Notes")
    }

    /// The three gestures, each on its own, because each one alone is the user saying it.
    @Test(
        "each way of saving a clip moves it to the permanent file",
        arguments: ["alias", "category", "pin"])
    func everyGestureSaves(_ gesture: String) async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("the connection string")
        try await store.record(subject, keeping: week())

        switch gesture {
        case "alias": try await store.setAlias("/pgprod", of: subject.id, keeping: week())
        case "category": try await store.setCategory("Work", of: subject.id, keeping: week())
        default: try await store.setPinned(true, of: subject.id, keeping: week())
        }

        let saved = await store.savedFile
        let onDisk = try JSONDecoder().decode(
            [Clip].self, from: try Data(contentsOf: saved))
        #expect(onDisk.map(\.id) == [subject.id])
        // And out of the disposable one, or it would still share its fate.
        #expect(
            FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false)
    }

    /// The measured failure, now a test.
    @Test("a saved clip survives a history file that cannot be read at all")
    func survivesADamagedHistory() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("the connection string")
        try await store.record(subject, keeping: week())
        try await store.setAlias("/pgprod", of: subject.id, keeping: week())
        try await store.record(clip("something disposable", at: 60), keeping: week())

        // A truncated write, a half-finished sync, a build that wrote a different shape: all the same.
        try Data("{ not json".utf8).write(to: file.url)

        let reopened = ClipboardStore(file: file.url)
        let clips = await reopened.clips(keeping: week())

        #expect(clips.map(\.id) == [subject.id])
        #expect(clips.first?.alias == "/pgprod")

        // The damage must not become permanent on the next ordinary copy.
        try await reopened.record(clip("a new copy", at: 120), keeping: week())
        let after = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(after.contains { $0.id == subject.id })
    }

    /// The split is only worth having if neither file can hurt the other.
    @Test("and the history survives a saved file that cannot be read")
    func survivesADamagedSavedFile() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("saved")
        try await store.record(subject, keeping: week())
        try await store.setPinned(true, of: subject.id, keeping: week())
        try await store.record(clip("history", at: 60), keeping: week())
        let saved = await store.savedFile

        try Data("{ not json".utf8).write(to: saved)

        let clips = await ClipboardStore(file: file.url).clips(keeping: week())

        #expect(clips.map(\.text) == ["history"])
    }

    /// Unsaving is a real move back, or the clip would never age out.
    @Test("taking the last tag off a clip returns it to the history")
    func unsavingMovesItBack() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("was pinned")
        try await store.record(subject, keeping: week())
        try await store.setPinned(true, of: subject.id, keeping: week())
        try await store.setPinned(false, of: subject.id, keeping: week())

        let saved = await store.savedFile
        #expect(
            FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) == false,
            "nothing is saved any more, so nothing of the user's is left in that file")
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).count == 1)
    }

    /// A clip with two tags loses only the one that was removed.
    @Test("but a clip that is still filed stays saved when its pin is removed")
    func oneTagIsEnough() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("filed and pinned")
        try await store.record(subject, keeping: week())
        try await store.setCategory("Work", of: subject.id, keeping: week())
        try await store.setPinned(true, of: subject.id, keeping: week())
        try await store.setPinned(false, of: subject.id, keeping: week())

        let saved = await store.savedFile
        let onDisk = try JSONDecoder().decode([Clip].self, from: try Data(contentsOf: saved))
        #expect(onDisk.map(\.category) == ["Work"])
    }

    /// A clipboard written before the split has its saved clips inside the history file.
    @Test("an older clipboard's saved clips are found and moved")
    func migratesFromASingleFile() async throws {
        let file = TemporaryFile()
        let old = [
            Clip(text: "kept", kind: .text, copiedAt: noon, alias: "/keep"),
            Clip(text: "history", kind: .text, copiedAt: noon.addingTimeInterval(-60)),
        ]
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: file.url)

        let store = ClipboardStore(file: file.url)
        #expect(await store.clips(keeping: week()).map(\.text) == ["kept", "history"])

        // The next ordinary write puts it where it belongs, out of a damaged history's reach.
        try await store.record(clip("a new copy", at: 120), keeping: week())
        try Data("{ not json".utf8).write(to: file.url)
        let after = await ClipboardStore(file: file.url).clips(keeping: week())

        #expect(after.map(\.text) == ["kept"])
    }

    /// The order the panel counts rows in has to survive being assembled from two files.
    @Test("the two files come back as one list, newest first")
    func theTwoFilesReadAsOneList() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let middle = clip("saved", at: 60)
        try await store.record(clip("oldest"), keeping: week())
        try await store.record(middle, keeping: week())
        try await store.record(clip("newest", at: 120), keeping: week())
        try await store.setPinned(true, of: middle.id, keeping: week())

        let clips = await ClipboardStore(file: file.url).clips(keeping: week())

        #expect(clips.map(\.text) == ["newest", "saved", "oldest"])
    }
}
