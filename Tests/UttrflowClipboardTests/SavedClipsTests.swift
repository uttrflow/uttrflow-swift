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
            ClipboardIndex.self, from: try Data(contentsOf: saved)
        ).clips
        #expect(onDisk.map(\.id) == [subject.id])
        // And out of the disposable one, or it would still share its fate.
        #expect(
            FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false)
    }

    @Test("using a saved clip moves it to the top of the saved pool")
    func useMovesClipToTopOfSaved() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let first = clip("first", at: -60)
        let second = clip("second")
        try await store.record(first, keeping: week())
        try await store.record(second, keeping: week())
        try await store.setPinned(true, of: first.id, keeping: week())
        try await store.setPinned(true, of: second.id, keeping: week())

        let used = await store.markUsed(first.id, at: noon.addingTimeInterval(-600), keeping: week())

        #expect(used.map(\.text) == ["first", "second"])
        await store.flushUse()
        #expect(
            await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == [
                "first", "second",
            ])
    }

    @Test("merges saved and history pools by sequence after a clock rollback", .bug(id: 2587))
    func interleavingUsesStoredOrderAcrossClockRollback() async throws {
        let folder = try TemporaryFolder()
        let historyFile = folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory)
        let store = ClipboardStore(file: historyFile)
        let savedFile = await store.savedFile
        let history = Clip(
            text: "history before rollback", kind: .text, copiedAt: noon.addingTimeInterval(60),
            lastUsedOrder: 1)
        let saved = Clip(
            text: "saved after rollback", kind: .text, copiedAt: noon.addingTimeInterval(-60),
            lastUsedOrder: 2, isPinned: true)
        try JSONEncoder().encode([history]).write(to: historyFile)
        try JSONEncoder().encode([saved]).write(to: savedFile)

        let clips = await ClipboardStore(file: historyFile).clips(keeping: week())

        #expect(clips.map(\.text) == ["saved after rollback", "history before rollback"])
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
        let onDisk = try JSONDecoder().decode(
            ClipboardIndex.self, from: try Data(contentsOf: saved)
        ).clips
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

    /// A clip un-filed with its collection gets a fresh age window without becoming pinned.
    @Test("deleting a collection refreshes age without pinning un-filed clips")
    func moveOutRefreshesAgeWithoutPinning() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let old = clip("a month old", at: -30 * 86_400)
        // Recorded while the window still covers it, so the clip lands on disk.
        try await store.record(old, keeping: week(from: old.copiedAt))
        try await store.setCategory("Work", of: old.id, keeping: week(from: old.copiedAt))

        let moved = try await store.moveCategory("Work", to: nil, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.id) == [old.id], "the clip is not deleted by the move")
        #expect(moved.first?.isPinned == false, "the move does not create a pin")
        #expect(reopened.first?.isPinned == false, "the persisted clip is not pinned")
        #expect(reopened.first?.isKept == false, "the clip returns to ordinary history")
        #expect(reopened.first?.copiedAt == noon, "the clip gets a fresh retention window")
    }

    /// Unpinning a clip older than the window keeps it for one write, instead of deleting it with the unpin.
    @Test("unpinning a clip older than the window leaves it for the next prune")
    func unpinningOldClipKeepsIt() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let old = clip("a month old and pinned", at: -30 * 86_400)
        try await store.record(old, keeping: week(from: old.copiedAt))
        try await store.setPinned(true, of: old.id, keeping: week(from: old.copiedAt))

        try await store.setPinned(false, of: old.id, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.id) == [old.id], "the unpin did not also delete the clip")
        #expect(reopened.first?.isPinned == false, "the unpin still took effect")
        #expect(
            reopened.first?.isKept == false,
            "the clip is no longer kept, so the next prune can age it out")
    }

    /// Clearing an alias on a clip older than the window keeps it for one write.
    @Test("clearing an alias on a clip older than the window leaves it for the next prune")
    func clearingAliasOldClipKeepsIt() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let old = clip("a month old with alias", at: -30 * 86_400)
        try await store.record(old, keeping: week(from: old.copiedAt))
        try await store.setAlias("/pgprod", of: old.id, keeping: week(from: old.copiedAt))

        try await store.setAlias(nil, of: old.id, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.id) == [old.id], "the alias removal did not also delete the clip")
        #expect(reopened.first?.alias == nil, "the alias removal still took effect")
        #expect(
            reopened.first?.isKept == false,
            "the clip is no longer kept, so the next prune can age it out")
    }

    /// Clearing a category on a clip older than the window keeps it for one write.
    @Test("clearing a category on a clip older than the window leaves it for the next prune")
    func clearingCategoryOldClipKeepsIt() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let old = clip("a month old and filed", at: -30 * 86_400)
        try await store.record(old, keeping: week(from: old.copiedAt))
        try await store.setCategory("Work", of: old.id, keeping: week(from: old.copiedAt))

        try await store.setCategory(nil, of: old.id, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.id) == [old.id], "the un-file did not also delete the clip")
        #expect(reopened.first?.category == nil, "the un-file still took effect")
        #expect(
            reopened.first?.isKept == false,
            "the clip is no longer kept, so the next prune can age it out")
    }

    /// Several pinned and several history clips, pasted from and reopened: each pool keeps its own order.
    @Test("pinned and history clips keep their order within each pool across a reopen", .bug(id: 3668))
    func poolOrderSurvivesAReopen() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let historyOlder = clip("history older", at: -300)
        let historyNewer = clip("history newer", at: -240)
        let historyNewest = clip("history newest", at: -180)
        let pinnedOlder = clip("pinned older", at: -120)
        let pinnedMiddle = clip("pinned middle", at: -60)
        let pinnedNewest = clip("pinned newest")
        for subject in [
            historyOlder, historyNewer, historyNewest, pinnedOlder, pinnedMiddle, pinnedNewest,
        ] {
            try await store.record(subject, keeping: week())
        }
        for pinned in [pinnedOlder, pinnedMiddle, pinnedNewest] {
            try await store.setPinned(true, of: pinned.id, keeping: week())
        }

        // Two pastes, one in each pool, the pinned one last, both before the reopen.
        _ = await store.markUsed(historyNewer.id, at: noon.addingTimeInterval(600), keeping: week())
        _ = await store.markUsed(pinnedOlder.id, at: noon.addingTimeInterval(660), keeping: week())
        await store.flushUse()

        let reopened = ClipboardStore(file: file.url)
        let clips = await reopened.clips(keeping: week())

        #expect(clips.count == 6)
        // Every pinned clip stayed pinned, and stayed in the saved pool on disk.
        #expect(clips.filter(\.isPinned).map(\.text) == ["pinned older", "pinned newest", "pinned middle"])
        let savedOnDisk = try JSONDecoder().decode(
            [Clip].self, from: try Data(contentsOf: await reopened.savedFile))
        #expect(Set(savedOnDisk.map(\.text)) == ["pinned older", "pinned middle", "pinned newest"])
        // Each pool kept its own order: the pasted clip first, then arrival order.
        #expect(
            clips.filter { !$0.isPinned }.map(\.text) == [
                "history newer", "history newest", "history older",
            ])
        // And the last paste moved its clip to the top of the merged list.
        #expect(clips.first?.text == "pinned older")
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

    /// An old clip kept in a collection stays kept when the collection is deleted and the user picks "keep clips".
    @Test("deleting a collection keeps older clips that were filed in it")
    func moveOutPreservesOldClipsThatWereFiledThere() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let old = Clip(text: "door code", kind: .text, copiedAt: noon.addingTimeInterval(-30 * 86_400))
        // Recorded while the window still covers the clip, so it lands on disk in the first place.
        try await store.record(old, keeping: week(from: old.copiedAt))
        try await store.setCategory("Work", of: old.id, keeping: week(from: old.copiedAt))

        let written = try await Self.writes { try await store.moveCategory("Work", to: nil, keeping: week()) }

        #expect(written <= 2)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        let unfiled = try #require(reopened.first { $0.id == old.id })
        #expect(unfiled.text == "door code")
        #expect(unfiled.isPinned == false)
        #expect(unfiled.isKept == false)
        #expect(unfiled.copiedAt == noon)
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
        // Copied at its own moment, since a clip stamped ahead of the clock is due, not young.
        try await store.record(fresh, keeping: week(from: fresh.copiedAt))
        let eightDaysOn = week(from: noon.addingTimeInterval(8 * 86_400))

        let written = await Self.writes {
            _ = await store.markUsed(fresh.id, at: eightDaysOn.now, keeping: eightDaysOn)
        }

        #expect(written >= 1)
        #expect(await ClipboardStore(file: file.url).clips(keeping: eightDaysOn).map(\.text) == ["fresh"])
    }
    @Test("editing a kept clip writes only the saved file")
    func keptEditLeavesHistoryAlone() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let kept = Clip(text: "kept", kind: .text, copiedAt: noon)
        try await store.record(kept, keeping: week())
        try await store.record(
            Clip(text: "loose", kind: .text, copiedAt: noon.addingTimeInterval(-60)), keeping: week())
        try await store.setPinned(true, of: kept.id, keeping: week())

        let alias = try await Self.writes { try await store.setAlias("k", of: kept.id, keeping: week()) }
        let rich = try await Self.writes {
            try await store.setRichText("<b>kept</b>", of: kept.id, keeping: week())
        }
        let filed = try await Self.writes {
            try await store.setCategory("Work", of: kept.id, keeping: week())
        }

        #expect(alias == 1)
        #expect(rich == 1)
        #expect(filed == 1)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.first { $0.id == kept.id }?.category == "Work")
        #expect(reopened.contains { $0.text == "loose" })
    }
}
