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

/// A collection is one gesture, so it is one write per file however many clips it holds.
@Suite("Collection changes and pastes write as little as they can")
struct ClipboardWriteCountTests {
    /// How many files `work` wrote.
    static func writes(_ work: () async throws -> Void) async rethrows -> Int {
        let tally = StoreWriteTally()
        try await ClipboardStore.$writes.withValue(tally) { try await work() }
        return tally.count
    }

    /// A store holding a collection of `count` clips and one clip outside it.
    static func store(at url: URL, filing count: Int, into name: String) async throws -> ClipboardStore {
        let store = ClipboardStore(file: url)
        for index in 0..<count {
            let filed = Clip(
                text: "filed \(index)", kind: .text, copiedAt: noon.addingTimeInterval(Double(index)))
            try await store.record(filed, keeping: week())
            try await store.setCategory(name, of: filed.id, keeping: week())
        }
        try await store.record(
            Clip(text: "loose", kind: .text, copiedAt: noon.addingTimeInterval(-60)), keeping: week())
        return store
    }

    @Test("renaming a collection of forty clips writes each file once")
    func renameIsOneWrite() async throws {
        let file = TemporaryFile()
        let store = try await Self.store(at: file.url, filing: 40, into: "Work")

        let written = try await Self.writes {
            try await store.moveCategory("Work", to: "Jobs", keeping: week())
        }

        #expect(written <= 2)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.filter { $0.category == "Jobs" }.count == 40)
        #expect(!reopened.contains { $0.category == "Work" })
        #expect(reopened.contains { $0.text == "loose" && $0.category == nil })
    }

    @Test("deleting a collection and keeping its clips writes each file once")
    func moveOutIsOneWrite() async throws {
        let file = TemporaryFile()
        let store = try await Self.store(at: file.url, filing: 40, into: "Work")

        let written = try await Self.writes { try await store.moveCategory("Work", to: nil, keeping: week()) }

        #expect(written <= 2)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.count == 41)
        #expect(reopened.allSatisfy { $0.category == nil })
    }

    @Test("deleting a collection with its clips writes each file once")
    func deleteIsOneWrite() async throws {
        let file = TemporaryFile()
        let store = try await Self.store(at: file.url, filing: 40, into: "Work")

        let written = try await Self.writes { try await store.deleteCategory("Work", keeping: week()) }

        #expect(written <= 2)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.text) == ["loose"])
    }

    @Test("a paste writes nothing, and the next real write carries it")
    func pasteIsCarriedByTheNextWrite() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let pasted = Clip(text: "pasted", kind: .text, copiedAt: noon)
        try await store.record(pasted, keeping: week())
        let later = noon.addingTimeInterval(600)

        let written = await Self.writes { _ = await store.markUsed(pasted.id, at: later, keeping: week()) }

        #expect(written == 0)
        #expect(await store.clips(keeping: week()).first?.lastUsedAt == later, "in memory at once")
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).first?.lastUsedAt == noon)

        let next = Clip(text: "next", kind: .text, copiedAt: noon.addingTimeInterval(60))
        try await store.record(next, keeping: week())
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.first { $0.id == pasted.id }?.lastUsedAt == later)
    }

    @Test("a held use is written by a flush, and a second flush writes nothing")
    func flushWritesHeldUse() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let pasted = Clip(text: "pasted", kind: .text, copiedAt: noon)
        try await store.record(pasted, keeping: week())
        let later = noon.addingTimeInterval(600)
        _ = await store.markUsed(pasted.id, at: later, keeping: week())

        let first = await Self.writes { await store.flushUse() }
        let second = await Self.writes { await store.flushUse() }

        #expect(first == 1)
        #expect(second == 0)
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).first?.lastUsedAt == later)
    }

    @Test("a use that drops an aged-out clip is written at once")
    func agingIsWrittenAtOnce() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let old = Clip(text: "old", kind: .text, copiedAt: noon)
        let fresh = Clip(text: "fresh", kind: .text, copiedAt: noon.addingTimeInterval(6 * 86_400))
        try await store.record(old, keeping: week())
        try await store.record(fresh, keeping: week())
        let eightDaysOn = week(from: noon.addingTimeInterval(8 * 86_400))

        let written = await Self.writes {
            _ = await store.markUsed(fresh.id, at: eightDaysOn.now, keeping: eightDaysOn)
        }

        #expect(written >= 1)
        #expect(await ClipboardStore(file: file.url).clips(keeping: eightDaysOn).map(\.text) == ["fresh"])
    }
}
