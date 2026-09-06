// Tests for the clipboard store.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Everything the user has copied")
struct ClipboardStoreTests {
    private func clip(
        _ text: String, at offset: TimeInterval = 0, alias: String? = nil,
        category: String? = nil, pinned: Bool = false
    ) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon.addingTimeInterval(offset), source: "Notes",
            alias: alias, category: category, isPinned: pinned)
    }

    // MARK: - Keeping and fetching

    @Test("keeps a copy, newest first")
    func recording() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("first"), keeping: week())
        let clips = try await store.record(clip("second"), keeping: week())

        #expect(clips.map(\.text) == ["second", "first"])
        #expect(await store.clips(keeping: week()).map(\.text) == ["second", "first"])
    }

    /// Arrival order, not clock order, so a Mac whose clock jumped cannot shuffle the list.
    @Test("orders by arrival, not by the timestamp it was handed")
    func arrivalOrder() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("later", at: 60), keeping: week())
        let clips = try await store.record(clip("earlier", at: -60), keeping: week())

        #expect(clips.map(\.text) == ["earlier", "later"])
    }

    @Test("survives a relaunch")
    func persistence() async throws {
        let file = TemporaryFile()
        try await ClipboardStore(file: file.url).record(clip("kept"), keeping: week())

        let reopened = ClipboardStore(file: file.url)
        #expect(await reopened.clips(keeping: week()).map(\.text) == ["kept"])
    }

    /// An unreadable file costs the user their clipboard, not their app.
    @Test("opens on nothing when the file has been mangled")
    func corruption() async throws {
        let file = TemporaryFile()
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json, and never was".utf8).write(to: file.url)

        let store = ClipboardStore(file: file.url)
        #expect(await store.clips(keeping: week()).isEmpty)
        // And it recovers: the next copy simply writes over the wreckage.
        #expect(try await store.record(clip("after"), keeping: week()).map(\.text) == ["after"])
    }

    @Test("opens on nothing when there is no file at all")
    func missingFile() async {
        let file = TemporaryFile()
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).isEmpty)
    }

    /// The one write that can genuinely fail: a path blocked by something that is not a directory.
    @Test("reports a disk that refuses the write")
    func writeFailure() async throws {
        let blocker = TemporaryFile(named: "blocker")
        try FileManager.default.createDirectory(
            at: blocker.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: blocker.url)

        let store = ClipboardStore(file: blocker.url.appending(path: "Uttrflow/clipboard.json"))
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(clip("nowhere to go"), keeping: week())
        }
    }

    // MARK: - Refusing nothing

    @Test(
        "refuses to record a copy with nothing in it",
        arguments: ["", " ", "\n", "\t\n  \n"])
    func blankCopies(_ text: String) async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        #expect(try await store.record(clip(text), keeping: week()).isEmpty)
        #expect(await store.clips(keeping: week()).isEmpty)
        // Nothing was written, so nothing was left on disk either.
        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false)
    }

    @Test("refuses a blank copy without disturbing what is already there")
    func blankCopyLeavesTheListAlone() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("real"), keeping: week())

        #expect(try await store.record(clip("   "), keeping: week()).map(\.text) == ["real"])
    }

    // MARK: - Deduplication

    /// Copying the same thing twice is one row moved to the top, not two rows.
    @Test("moves a repeated copy to the top instead of adding a row")
    func deduplication() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("alpha"), keeping: week())
        try await store.record(clip("beta"), keeping: week())
        let clips = try await store.record(clip("alpha", at: 120), keeping: week())

        #expect(clips.map(\.text) == ["alpha", "beta"])
        #expect(clips.count == 2)
        // It really was copied again, so it carries the new time.
        #expect(clips[0].copiedAt == noon.addingTimeInterval(120))
    }

    /// Copying a value again must not strip the name the user gave it.
    @Test("keeps the alias, category and pin when the same thing is copied again")
    func deduplicationKeepsWhatWasDeliberate() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let original = clip("postgres://…", alias: "/pgprod", category: "Credentials", pinned: true)
        try await store.record(original, keeping: week())

        let clips = try await store.record(clip("postgres://…", at: 60), keeping: week())

        #expect(clips.count == 1)
        #expect(clips[0].alias == "/pgprod")
        #expect(clips[0].category == "Credentials")
        #expect(clips[0].isPinned)
        // And it is the same row, so a panel holding a selection by identifier keeps it.
        #expect(clips[0].id == original.id)
    }

    @Test("tells two different texts apart, however similar")
    func deduplicationIsExact() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("alpha"), keeping: week())
        let clips = try await store.record(clip("alpha "), keeping: week())

        #expect(clips.count == 2)
    }

    // MARK: - Two clocks

    @Test("ages out history once the window has passed")
    func historyAgesOut() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("old"), keeping: week())

        let fortnight = noon.addingTimeInterval(14 * 86_400)
        #expect(await store.clips(keeping: week(from: fortnight)).isEmpty)
    }

    /// The window applies on the way out as well as in, and the disk is caught up when it does.
    @Test("tidies the disk when a read finds something too old")
    func readingTidiesTheDisk() async throws {
        let file = TemporaryFile()
        try await ClipboardStore(file: file.url).record(clip("old"), keeping: week())

        let fortnight = noon.addingTimeInterval(14 * 86_400)
        _ = await ClipboardStore(file: file.url).clips(keeping: week(from: fortnight))

        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false)
    }

    /// A clip somebody named, filed or pinned never ages out, however old.
    @Test(
        "never ages out a clip the user kept",
        arguments: [
            Clip(text: "aliased", kind: .text, copiedAt: .distantPast, alias: "/a"),
            Clip(text: "filed", kind: .text, copiedAt: .distantPast, category: "Snippets"),
            Clip(text: "pinned", kind: .text, copiedAt: .distantPast, isPinned: true),
        ])
    func keptClipsNeverAgeOut(_ kept: Clip) async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        let clips = try await store.record(kept, keeping: ClipRetention(days: 1, now: .now))
        #expect(clips.map(\.text) == [kept.text])
    }

    /// Zero days is honest for somebody who wants the panel and not the record; kept clips still stay.
    @Test("keeps no history at all when the window is zero, and keeps what was kept")
    func zeroDayWindow() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let none = ClipRetention(days: 0, now: noon)

        try await store.record(clip("history"), keeping: none)
        let clips = try await store.record(clip("saved", pinned: true), keeping: none)

        #expect(clips.map(\.text) == ["saved"])
    }

    // MARK: - The cap

    @Test("caps history at the capacity it was given, oldest first")
    func capacity() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 3))

        for index in 1...5 { try await store.record(clip("clip \(index)"), keeping: week()) }

        #expect(await store.clips(keeping: week()).map(\.text) == ["clip 5", "clip 4", "clip 3"])
    }

    /// The cap bounds the write, not what the user asked to keep.
    @Test("never counts a kept clip against the cap")
    func keptClipsAreNotCapped() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 2))

        for index in 1...4 {
            try await store.record(clip("pinned \(index)", pinned: true), keeping: week())
        }
        try await store.record(clip("history 1"), keeping: week())
        let clips = try await store.record(clip("history 2"), keeping: week())

        #expect(clips.count == 6)
        #expect(clips.filter { !$0.isKept }.map(\.text) == ["history 2", "history 1"])
    }

    /// A nonsense capacity keeps no history rather than trapping, and kept clips survive it.
    @Test("keeps no history rather than crashing on a nonsense capacity")
    func negativeCapacity() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: -10))

        #expect(try await store.record(clip("gone"), keeping: week()).isEmpty)
        #expect(try await store.record(clip("kept", pinned: true), keeping: week()).count == 1)
    }

    // MARK: - Editing

    @Test("pins a clip and unpins it again")
    func pinning() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("worth keeping")
        try await store.record(subject, keeping: week())

        #expect(try await store.setPinned(true, of: subject.id, keeping: week())[0].isPinned)
        #expect(try await store.setPinned(false, of: subject.id, keeping: week())[0].isPinned == false)
    }

    @Test("names a clip and takes the name away")
    func aliasing() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("postgres://…")
        try await store.record(subject, keeping: week())

        #expect(try await store.setAlias("/pgprod", of: subject.id, keeping: week())[0].alias == "/pgprod")
        #expect(try await store.setAlias(nil, of: subject.id, keeping: week())[0].alias == nil)
    }

    @Test("files a clip and takes it out of the collection again")
    func categorising() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("snippet")
        try await store.record(subject, keeping: week())

        let filed = try await store.setCategory("Snippets", of: subject.id, keeping: week())
        #expect(filed[0].category == "Snippets")
        #expect(try await store.setCategory(nil, of: subject.id, keeping: week())[0].category == nil)
    }

    /// Rebuilding a clip on edit must keep `timesCopied`, or the budget evicts a tidied favourite first.
    @Test("tidying a clip keeps the count of how often it was copied")
    func editsKeepTheCount() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("let x  =  1")
        for _ in 0..<3 { try await store.record(subject, keeping: week()) }

        let tidied = try await store.setText("let x = 1", of: subject.id, keeping: week())
        #expect(tidied[0].timesCopied == 3)

        let noted = try await store.setRichText(
            "<p>let x = 1</p>", of: subject.id, keeping: week())
        #expect(noted[0].timesCopied == 3)
    }

    /// The same rebuild one field along: a clip that lost its picture would be swept as an orphan.
    @Test("and keeps the picture it is a picture of")
    func editsKeepThePicture() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let shot = Clip(text: "", kind: .image, copiedAt: noon, source: "Screenshot")
        try await store.record(
            NoticedClip(clip: shot, picture: (Data(repeating: 7, count: 64), 10, 10)),
            keeping: week())

        #expect(try await store.setRichText("<p>a note</p>", of: shot.id, keeping: week())[0].image != nil)
        #expect(try await store.setText("alt text", of: shot.id, keeping: week())[0].image != nil)
    }

    /// Un-naming makes a clip history again from that moment, so the window applies at once.
    @Test("lets an unnamed clip fall back under the window")
    func unKeepingRestoresTheWindow() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("was saved", alias: "/a")
        try await store.record(subject, keeping: week())

        let fortnight = noon.addingTimeInterval(14 * 86_400)
        let clips = try await store.setAlias(nil, of: subject.id, keeping: week(from: fortnight))
        #expect(clips.isEmpty)
    }

    /// An identifier that is not there is not an error; afterwards it is neither present nor changed.
    @Test("shrugs at an identifier it has never seen")
    func unknownIdentifier() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("here"), keeping: week())

        #expect(try await store.delete(UUID(), keeping: week()).map(\.text) == ["here"])
        #expect(try await store.setPinned(true, of: UUID(), keeping: week()).map(\.text) == ["here"])
    }

    // MARK: - Forgetting

    @Test("forgets one clip")
    func deletingOne() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let doomed = clip("delete me")
        try await store.record(clip("keep me"), keeping: week())
        try await store.record(doomed, keeping: week())

        #expect(try await store.delete(doomed.id, keeping: week()).map(\.text) == ["keep me"])
    }

    /// "Clear Clipboard" clears the record of what was copied, reaches the disk, and keeps what was saved.
    @Test("forgets the history and leaves nothing of it on disk, but keeps what was saved")
    func deletingEverything() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("history"), keeping: week())
        try await store.record(clip("pinned", pinned: true), keeping: week())

        let left = try await store.deleteEverything(keeping: week())

        #expect(left.map(\.text) == ["pinned"])
        #expect(await store.clips(keeping: week()).map(\.text) == ["pinned"])
        #expect(
            FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false,
            "the history file is gone")
        // And it survives the process, which is the whole point of calling it permanent.
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == ["pinned"])
    }

    /// Emptying an already-empty store is not a failure.
    @Test("is happy to forget nothing")
    func deletingNothing() async throws {
        let file = TemporaryFile()
        try await ClipboardStore(file: file.url).deleteEverything(keeping: week())
    }

    // MARK: - Speed

    /// Fetching is on the ⇧⌘V path and must not touch the disk once read; proved by deleting the file.
    @Test("answers a fetch from memory rather than from the disk")
    func fetchingDoesNoDiskWork() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("in memory"), keeping: week())

        try FileManager.default.removeItem(at: file.url)

        #expect(await store.clips(keeping: week()).map(\.text) == ["in memory"])
    }

    /// An empty store is cached too, or the case with nothing to show reads the disk on every open.
    @Test("caches an empty clipboard as well as a full one")
    func emptinessIsCachedToo() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        #expect(await store.clips(keeping: week()).isEmpty)

        // Written behind the store's back. A store that re-read the file would find it.
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([clip("smuggled in")]).write(to: file.url)

        #expect(await store.clips(keeping: week()).isEmpty)
    }

    @Test("puts its file somewhere versioned under Uttrflow's own folder")
    func defaultLocation() {
        let file = ClipboardStore.defaultFile(in: URL(filePath: "/tmp"))
        #expect(file.path(percentEncoded: false) == "/tmp/Uttrflow/clipboard.v1.json")
        #expect(ClipboardStore.defaultBudget.copied.items == 500)
    }
}

/// A dictation lives in two files, and only one of the two windows was on a screen.
@Suite("The transcript window governs both copies")
struct ClipRetentionDictationTests {
    @Test("a dictation ages by the transcript window, not the clipboard one")
    func dictationFollowsTheTranscriptWindow() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        // Transcripts kept for one day on a Mac whose clipboard window is a fortnight.
        let now = Date()
        let retention = ClipRetention(days: 14, now: now, dictationDays: 1)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)

        let spoken = Clip(
            text: "something they said", kind: .text, copiedAt: twoDaysAgo,
            source: ClipOrigin.dictationSource, origin: .uttrflow)
        let copied = Clip(
            text: "something they copied", kind: .text, copiedAt: twoDaysAgo, source: "Finder")

        _ = try await store.record(spoken, keeping: retention)
        let remaining = try await store.record(copied, keeping: retention)

        #expect(
            !remaining.contains { $0.text == "something they said" },
            "the dictation outlived the window the user set for their transcripts")
        #expect(
            remaining.contains { $0.text == "something they copied" },
            "an ordinary copy still ages by the clipboard window")
    }
}
