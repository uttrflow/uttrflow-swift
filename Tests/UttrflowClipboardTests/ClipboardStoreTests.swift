// Tests for the clipboard store.

import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

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

    @Test("reclassifies stored text with the current secret detector before returning or persisting it")
    func reclassifiesStoredSecret() async throws {
        let file = TemporaryFile()
        let old = Clip(text: "api_key = ff00aa11ff00aa11ff00aa11", kind: .text, copiedAt: noon)
        try JSONEncoder().encode([old]).write(to: file.url)
        let store = ClipboardStore(file: file.url)

        let clips = await store.clips(keeping: week())

        #expect(clips.first?.kind == .secret)
        let persisted = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: file.url))
        #expect(persisted.isEmpty)
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

    @Test("using a clip moves it to the top of history and keeps that order after reopening")
    func useMovesClipToTop() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let first = clip("first", at: -120)
        let second = clip("second", at: -60)
        let third = clip("third")
        try await store.record(first, keeping: week())
        try await store.record(second, keeping: week())
        try await store.record(third, keeping: week())

        let used = await store.markUsed(first.id, at: noon.addingTimeInterval(-600), keeping: week())

        #expect(used.map(\.text) == ["first", "third", "second"])
        await store.flushUse()
        #expect(
            await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == [
                "first", "third", "second",
            ])
    }

    @Test("survives a relaunch")
    func persistence() async throws {
        let file = TemporaryFile()
        try await ClipboardStore(file: file.url).record(clip("kept"), keeping: week())

        let reopened = ClipboardStore(file: file.url)
        #expect(await reopened.clips(keeping: week()).map(\.text) == ["kept"])
    }

    @Test("keeps a secret copy in memory for this session but never writes it to the history file")
    func secretCopyIsMemoryOnly() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let secret = Clip(text: "password: correct horse battery staple", kind: .secret, copiedAt: noon)

        #expect(try await store.record(secret, keeping: week()).map(\.text) == [secret.text])
        #expect(await store.clips(keeping: week()).map(\.text) == [secret.text])
        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) == false)
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).isEmpty)
    }

    @Test("writes ordinary history around a secret without putting the secret bytes on disk")
    func secretCopyIsSkippedWhenOtherHistoryIsWritten() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let secret = Clip(text: "api_key = ff00aa11ff00aa11ff00aa11", kind: .secret, copiedAt: noon)

        try await store.record(clip("before"), keeping: week())
        try await store.record(secret, keeping: week())
        let clips = try await store.record(clip("after"), keeping: week())

        #expect(clips.map(\.text) == ["after", secret.text, "before"])
        let bytes = try Data(contentsOf: file.url)
        let payload = try #require(String(data: bytes, encoding: .utf8))
        #expect(!payload.contains(secret.text))
        #expect(
            await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == ["after", "before"])
    }

    @Test("drops secrets found in an older history file instead of rehydrating them")
    func oldPersistedSecretsAreNotLoaded() async throws {
        let file = TemporaryFile()
        let oldSecret = Clip(text: "client_secret = abc123def456", kind: .secret, copiedAt: noon)
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([oldSecret]).write(to: file.url)

        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).isEmpty)
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

    /// The picture is written first so a clip never points at a file that is missing; this is that write failing.
    @Test("reports a disk that refuses a copied picture, and keeps no clip pointing at it")
    func pictureWriteFailure() async throws {
        let folder = try TemporaryFolder()
        // A regular file where the Images folder belongs, so creating the folder cannot succeed.
        try Data("in the way".utf8).write(
            to: folder.url.appending(path: "Images", directoryHint: .notDirectory))
        let noticed = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: Date()),
            picture: (Data(repeating: 0x89, count: 4_096), 1024, 768))

        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await folder.store.record(noticed, keeping: folder.retention)
        }
        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    /// A list is written atomically so a pin is never replaced by half of one; this is that write failing.
    @Test("reports a disk that refuses a list write, and leaves the list already saved readable")
    func listWriteFailure() async throws {
        let folder = try TemporaryFolder()
        #expect(try await folder.store.record(clip("the first one"), keeping: week()).count == 1)

        // The folder is there and readable, so the file is `missing` rather than unreplaceable, and unwritable.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.url.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: folder.url.path)
        }

        let store = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory))
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(clip("the second one"), keeping: week())
        }
        // Read fresh from disk: the point is that the atomic write left the saved list whole.
        let reopened = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json", directoryHint: .notDirectory))
        #expect(await reopened.clips(keeping: week()).map(\.text) == ["the first one"])
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

    @Test("restoring a deleted duplicate keeps the newer clip and its pin, name, and collection")
    func restoreDuplicatePreservesNewerClipState() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let deleted = clip("same text", at: -60)
        try await store.record(deleted, keeping: week())
        try await store.delete(deleted.id, keeping: week())

        let newer = clip("same text")
        try await store.record(newer, keeping: week())
        try await store.setPinned(true, of: newer.id, keeping: week())
        try await store.setAlias("/important", of: newer.id, keeping: week())
        try await store.setCategory("Work", of: newer.id, keeping: week())

        let restored = try await store.restore(deleted, keeping: week())

        #expect(restored.count == 1)
        #expect(restored[0].id == newer.id)
        #expect(restored[0].isPinned)
        #expect(restored[0].alias == "/important")
        #expect(restored[0].category == "Work")
        #expect(restored[0].copiedAt == newer.copiedAt)
        #expect(restored[0].timesCopied == 2)
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()) == restored)
    }

    @Test("restoring a duplicate keeps the newer copy data and restores choices from the deleted clip")
    func restoreDuplicateKeepsNewerCopyData() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let deleted = Clip(
            text: "same text", kind: .text, copiedAt: noon.addingTimeInterval(-60), source: "Older App",
            lastUsedAt: noon.addingTimeInterval(-30), richText: "<p>older formatting</p>",
            alias: "/remember", category: "Work", isPinned: true)
        try await store.record(deleted, keeping: week())
        try await store.delete(deleted.id, keeping: week())

        let newer = Clip(
            text: "same text", kind: .text, copiedAt: noon, source: "Newer App",
            lastUsedAt: noon.addingTimeInterval(30), richText: "<p>newer formatting</p>")
        try await store.record(newer, keeping: week())

        let restored = try await store.restore(deleted, keeping: week())
        let clip = try #require(restored.first)

        #expect(restored.count == 1)
        #expect(clip.id == newer.id)
        #expect(clip.text == newer.text)
        #expect(clip.copiedAt == newer.copiedAt)
        #expect(clip.lastUsedAt == newer.lastUsedAt)
        #expect(clip.source == newer.source)
        #expect(clip.richText == newer.richText)
        #expect(clip.alias == deleted.alias)
        #expect(clip.category == deleted.category)
        #expect(clip.isPinned == deleted.isPinned)
        #expect(clip.timesCopied == 2)
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()) == restored)
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

    /// The promise is a maximum, so a clip the clock stamped ahead must not buy a year of extra life.
    @Test("a clip copied at a clock a year ahead is past its window, not kept until the clock catches up")
    func aFutureStampIsDueRatherThanKept() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("ahead", at: 365 * 86_400), keeping: week())
        try await store.record(clip("recent", at: -86_400), keeping: week())

        #expect(await store.clips(keeping: week()).map(\.text) == ["recent"])
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == ["recent"])
    }

    /// The irreversible half: one read at a clock that jumped a year emptied the file.
    @Test("a clock far ahead of the newest clip hides the history rather than deleting it")
    func aJumpedClockLeavesTheDiskAlone() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("recent"), keeping: week())

        let jumped = week(from: noon.addingTimeInterval(400 * 86_400))
        #expect(await store.clips(keeping: jumped).isEmpty)
        // And the words come back once the clock is put right, because nothing was deleted.
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text) == ["recent"])
    }

    /// A write is no more able to tell the time than a read is.
    @Test("a copy taken at a clock far ahead does not take the history with it")
    func aJumpedClockCannotSweepOnWrite() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("recent"), keeping: week())

        let jumped = week(from: noon.addingTimeInterval(400 * 86_400))
        _ = try await store.record(clip("ahead", at: 400 * 86_400), keeping: jumped)

        #expect(
            await ClipboardStore(file: file.url).clips(keeping: week()).map(\.text)
                == ["recent"])
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

    @Test("restoring a deleted clip does not reclaim an alias assigned to another clip")
    func restoringDeletedClipDoesNotDuplicateAlias() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let deleted = clip("first", alias: "x")
        let renamed = clip("second")
        try await store.record(deleted, keeping: week())
        try await store.delete(deleted.id, keeping: week())
        try await store.record(renamed, keeping: week())
        try await store.setAlias("x", of: renamed.id, keeping: week())

        let restored = try await store.record(deleted, keeping: week())

        #expect(restored.first { $0.id == renamed.id }?.alias == "x")
        #expect(restored.first { $0.id == deleted.id }?.alias == nil)
        #expect(restored.compactMap(\.alias) == ["x"])
    }

    @Test("refuses to assign an alias already held by another clip")
    func duplicateAliasIsRefused() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let first = clip("first", alias: "x")
        let second = clip("second")
        try await store.record(first, keeping: week())
        try await store.record(second, keeping: week())

        await #expect(throws: ClipboardStoreError.aliasAlreadyInUse) {
            try await store.setAlias("x", of: second.id, keeping: week())
        }
        #expect(await store.clips(keeping: week()).compactMap(\.alias) == ["x"])
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

    @Test("rewriting a secret as ordinary text removes secret masking")
    func rewritingSecretAsOrdinaryTextReclassifies() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = Clip(text: "api_key = ff00aa11ff00aa11ff00aa11", kind: .secret, copiedAt: noon)
        try await store.record(subject, keeping: week())

        let rewritten = try await store.setText(
            "Deployment notes for Friday", of: subject.id, keeping: week())

        #expect(rewritten[0].kind == .text)
        #expect(rewritten[0].id == subject.id)
        #expect(rewritten[0].copiedAt == subject.copiedAt)
    }

    @Test("rewriting ordinary text as a secret classifies and masks it")
    func rewritingOrdinaryTextAsSecretReclassifies() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("Deployment notes for Friday")
        try await store.record(subject, keeping: week())

        let rewritten = try await store.setText(
            "api_key = ff00aa11ff00aa11ff00aa11", of: subject.id, keeping: week())

        #expect(rewritten[0].kind == .secret)
        #expect(rewritten[0].id == subject.id)
        #expect(rewritten[0].copiedAt == subject.copiedAt)
    }

    @Test("rewriting text with the same content preserves its classification")
    func rewritingUnchangedTextKeepsClassification() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = Clip(text: "https://example.com/docs", kind: .link, copiedAt: noon)
        try await store.record(subject, keeping: week())

        let rewritten = try await store.setText(subject.text, of: subject.id, keeping: week())

        #expect(rewritten[0].kind == .link)
        #expect(rewritten[0].id == subject.id)
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

    /// Un-naming resets the clip's age, so the window applies from the un-keep rather than the original copy.
    @Test("an unnamed clip starts a fresh window from the un-keep")
    func unKeepingResetsTheWindow() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("was saved", alias: "/a")
        try await store.record(subject, keeping: week())

        let fortnight = noon.addingTimeInterval(14 * 86_400)
        let kept = try await store.setAlias(nil, of: subject.id, keeping: week(from: fortnight))
        #expect(kept.map(\.id) == [subject.id], "the un-keep does not also delete the clip")
        #expect(kept.first?.copiedAt == fortnight, "the clip's age is reset from the un-keep")

        let eightDaysOn = ClipRetention(days: 7, now: fortnight.addingTimeInterval(8 * 86_400))
        let after = await ClipboardStore(file: file.url).clips(keeping: eightDaysOn)
        #expect(after.isEmpty, "the reset window still applies after the un-keep")
    }

    /// An un-kept clip survives the same write under the item cap, instead of being evicted at its old position.
    @Test("an un-kept clip survives a full pool by moving to the front")
    func unKeepingSurvivesAFullPool() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 2))
        let old = clip("old", pinned: true)
        try await store.record(old, keeping: week())
        try await store.record(clip("a", at: 60), keeping: week())
        try await store.record(clip("b", at: 120), keeping: week())

        let after = try await store.setPinned(false, of: old.id, keeping: week())

        #expect(after.contains { $0.id == old.id }, "the unpin does not also evict the clip")
        #expect(after.first?.id == old.id, "the un-kept clip moves to the front of its pool")
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
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).isEmpty)
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

    // MARK: - Who may read what was copied

    /// The list holds concealed copies in plain text, so its file is its owner's alone.
    @Test("writes the clipboard list readable only by its owner")
    func listIsOwnerOnly() async throws {
        let folder = try TemporaryFolder()

        let copied = Clip(
            text: "something copied", kind: .text, copiedAt: .now, source: "Notes")
        try await folder.store.record(copied, keeping: folder.retention)

        #expect(posixMode(of: folder.url.appending(path: "clipboard.json")) == 0o600)
        #expect(posixMode(of: folder.url) == 0o700)
    }

    /// A copied picture is as private as the words beside it.
    @Test("writes a copied picture readable only by its owner")
    func pictureIsOwnerOnly() async throws {
        let folder = try TemporaryFolder()

        let image = try await folder.store.keep(
            Data(repeating: 0x89, count: 64), forClip: UUID(), width: 1, height: 1)

        let images = await folder.store.imagesFolder
        #expect(posixMode(of: images.appending(path: image.file, directoryHint: .notDirectory)) == 0o600)
        #expect(posixMode(of: images) == 0o700)
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
