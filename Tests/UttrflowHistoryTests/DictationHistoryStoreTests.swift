// Tests DictationHistoryStore against real files: persistence, retention, cap, deletion, undo, corruption.
import Foundation
import UttrflowCore
import Testing

@testable import UttrflowHistory

// MARK: - Fixtures

/// A fixed instant, so no test reads the real clock or sleeps.
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// A seven-day window measured from `epoch`.
private let week = Retention(days: 7, now: epoch)

/// A plain dictation `daysAgo` before `epoch`, with no recorded changes.
private func spoken(
    _ text: String, daysAgo: Double = 0, id: UUID = UUID(), app: String? = nil
) -> DictationRecord {
    DictationRecord(
        id: id, text: text, when: epoch.addingTimeInterval(-daysAgo * 86_400),
        applicationName: app)
}

/// A dictation whose first two spoken words, "utter flow", the dictionary replaced with `wrote`.
private func changed(
    _ text: String, wrote: String, daysAgo: Double = 0, entry: UUID = UUID(),
    isUndone: Bool = false
) -> DictationRecord {
    DictationRecord(
        text: text, when: epoch.addingTimeInterval(-daysAgo * 86_400),
        changes: RecordedChanges(
            corrections: [
                RecordedCorrection(
                    heard: "utter flow", wrote: wrote, wordRange: 0..<2, entryID: entry,
                    reason: .seenOnScreen, heardConfidence: 0.3, isUndone: isUndone)
            ]))
}

/// A directory per test, removed with it; real files, because the store's whole job is what happens on disk.
private struct Sandbox: ~Copyable {
    /// The per-test directory.
    let root: URL

    /// Names a fresh directory under the temporary folder without creating it.
    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-history-\(UUID().uuidString)")
    }

    /// The folder the store is expected to make for itself; absent to begin with.
    var folder: URL { root.appending(path: "Uttrflow") }

    /// The path the store is pointed at.
    var file: URL { folder.appending(path: "history.v1.json") }

    /// What is on disk, decoded; the only honest way to check that a deletion reached it.
    func onDisk() -> [DictationRecord]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([DictationRecord].self, from: data)
    }

    /// Puts bytes where the store will look, so a test can hand it an aged or mangled file.
    func seed(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file)
    }

    /// Seeds the file with encoded records.
    func seed(_ records: [DictationRecord]) throws {
        try seed(JSONEncoder().encode(records))
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

// MARK: - Tests

/// Exercises the store through real files in a per-test sandbox.
@Suite("Dictation history, as it is kept")
struct DictationHistoryStoreTests {

    // MARK: Where it lives

    @Test("lives in its own versioned file inside Uttrflow's Application Support folder")
    func defaultLocation() {
        let container = URL(fileURLWithPath: "/somewhere")
        let file = DictationHistoryStore.defaultFile(in: container)
        #expect(file.lastPathComponent == "history.v1.json")
        #expect(file.deletingLastPathComponent().lastPathComponent == "Uttrflow")
    }

    /// Building the store reads and writes nothing.
    @Test("defaults to a real Application Support path without going near it")
    func defaultsAreInert() {
        #expect(DictationHistoryStore.defaultFile().path.contains("Application Support"))
        _ = DictationHistoryStore()
        #expect(DictationHistoryStore.defaultCapacity == 1_000)
    }

    // MARK: Persisting

    @Test("starts empty when there is no file")
    func startsEmpty() async {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file)
        #expect(await store.records(keeping: week).isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    @Test("a dictation recorded by one store is read back by the next")
    func survivesRelaunch() async throws {
        let sandbox = Sandbox()
        let record = spoken("Right, the drafting is done.", app: "Mail")
        try await DictationHistoryStore(file: sandbox.file).append(record, keeping: week)

        // A separate instance, exactly as the next launch of the app would build.
        let reopened = DictationHistoryStore(file: sandbox.file)
        #expect(await reopened.records(keeping: week) == [record])
    }

    @Test("the newest dictation comes first")
    func newestFirst() async throws {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file)
        for line in ["First.", "Second.", "Third."] {
            try await store.append(spoken(line), keeping: week)
        }
        #expect(await store.records(keeping: week).map(\.text) == ["Third.", "Second.", "First."])
    }

    @Test("appending answers with the history as it now stands")
    func appendAnswersWithTheList() async throws {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file)
        try await store.append(spoken("First."), keeping: week)
        let after = try await store.append(spoken("Second."), keeping: week)
        #expect(after.map(\.text) == ["Second.", "First."])
    }

    // MARK: Retention

    @Test("nothing past the window is handed back")
    func retentionOnRead() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Recent.", daysAgo: 1), spoken("Ancient.", daysAgo: 30)])
        let store = DictationHistoryStore(file: sandbox.file)
        #expect(await store.records(keeping: week).map(\.text) == ["Recent."])
    }

    /// The promise is that it is deleted, not that it is hidden.
    @Test("reading also takes what expired off the disk")
    func retentionReachesTheDisk() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Recent.", daysAgo: 1), spoken("Ancient.", daysAgo: 30)])
        _ = await DictationHistoryStore(file: sandbox.file).records(keeping: week)
        #expect(sandbox.onDisk()?.map(\.text) == ["Recent."])
    }

    @Test("a history where nothing survived leaves no file behind")
    func expiryEmptiesTheFile() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Ancient.", daysAgo: 30)])
        #expect(await DictationHistoryStore(file: sandbox.file).records(keeping: week).isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    @Test("reading a history that is entirely current does not rewrite it")
    func nothingToPruneLeavesTheFileAlone() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Recent.", daysAgo: 1)])
        let before =
            try FileManager.default.attributesOfItem(
                atPath: sandbox.file.path(percentEncoded: false))[.modificationDate] as? Date
        _ = await DictationHistoryStore(file: sandbox.file).records(keeping: week)
        let after =
            try FileManager.default.attributesOfItem(
                atPath: sandbox.file.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test("writing ages out what the window has already passed")
    func retentionOnWrite() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Ancient.", daysAgo: 30)])
        let store = DictationHistoryStore(file: sandbox.file)
        let after = try await store.append(spoken("Now."), keeping: week)
        #expect(after.map(\.text) == ["Now."])
        #expect(sandbox.onDisk()?.map(\.text) == ["Now."])
    }

    /// A window of nothing is a real setting, and it must not quietly become "for ever".
    @Test("a window that keeps nothing keeps nothing, including what has just arrived")
    func zeroWindowKeepsNothing() async throws {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file)
        let after = try await store.append(spoken("Now."), keeping: Retention(days: 0, now: epoch))
        #expect(after.isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    // MARK: The cap

    @Test("the cap holds, and the oldest is what goes")
    func capDropsTheOldest() async throws {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file, capacity: 3)
        for line in ["First.", "Second.", "Third.", "Fourth."] {
            try await store.append(spoken(line), keeping: week)
        }
        let kept = await store.records(keeping: week)
        #expect(kept.map(\.text) == ["Fourth.", "Third.", "Second."])
        #expect(sandbox.onDisk()?.count == 3)
    }

    /// A file written by a build with a bigger cap must not stay over it for ever.
    @Test("a file already over the cap is trimmed on the next read")
    func capAppliesOnRead() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Newest."), spoken("Middle."), spoken("Oldest.")])
        let store = DictationHistoryStore(file: sandbox.file, capacity: 2)
        #expect(await store.records(keeping: week).map(\.text) == ["Newest.", "Middle."])
        #expect(sandbox.onDisk()?.map(\.text) == ["Newest.", "Middle."])
    }

    @Test("a nonsense cap is clamped rather than obeyed, and keeps nothing")
    func negativeCapacityIsClamped() async throws {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file, capacity: -3)
        #expect(try await store.append(spoken("Now."), keeping: week).isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    // MARK: Deleting

    @Test("deleting one entry reaches the disk in the same call")
    func deleteOne() async throws {
        let sandbox = Sandbox()
        let doomed = UUID()
        try sandbox.seed([spoken("Keep me."), spoken("Forget me.", id: doomed)])
        let store = DictationHistoryStore(file: sandbox.file)

        let left = try await store.delete(doomed, keeping: week)
        #expect(left.map(\.text) == ["Keep me."])
        #expect(sandbox.onDisk()?.map(\.text) == ["Keep me."])
    }

    @Test("deleting something that is not there is not a failure")
    func deleteUnknown() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Keep me.")])
        let store = DictationHistoryStore(file: sandbox.file)
        #expect(try await store.delete(UUID(), keeping: week).map(\.text) == ["Keep me."])
    }

    @Test("deleting the last entry leaves no file behind")
    func deleteTheLastOne() async throws {
        let sandbox = Sandbox()
        let doomed = UUID()
        try sandbox.seed([spoken("Forget me.", id: doomed)])
        try await DictationHistoryStore(file: sandbox.file).delete(doomed, keeping: week)
        #expect(sandbox.onDisk() == nil)
    }

    /// Clearing and then quitting must not leave the words on disk for the next launch.
    @Test("clearing everything removes the file there and then")
    func clearEverything() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("First."), spoken("Second.")])
        let store = DictationHistoryStore(file: sandbox.file)

        try await store.deleteEverything()
        #expect(sandbox.onDisk() == nil)
        #expect(
            FileManager.default.fileExists(atPath: sandbox.file.path(percentEncoded: false))
                == false)
        #expect(await store.records(keeping: week).isEmpty)
    }

    @Test("clearing a history that was never written is not a failure")
    func clearNothing() async throws {
        let sandbox = Sandbox()
        try await DictationHistoryStore(file: sandbox.file).deleteEverything()
        #expect(sandbox.onDisk() == nil)
    }

    // MARK: A file we did not write

    @Test(
        "a file that cannot be read is an empty history, not a crash",
        arguments: [
            "truncated": Data(#"[{"id":"not-even-finish"#.utf8),
            "not JSON at all": Data("nonsense, entirely".utf8),
            "empty": Data(),
            "an object where an array belongs": Data(#"{"records":[]}"#.utf8),
            "an array of the wrong thing": Data("[1,2,3]".utf8),
        ])
    func corruptFileDegradesToEmpty(_ named: String, _ bytes: Data) async throws {
        let sandbox = Sandbox()
        try sandbox.seed(bytes)
        #expect(await DictationHistoryStore(file: sandbox.file).records(keeping: week).isEmpty)
    }

    /// There is nothing readable to preserve, but the next dictation must still be kept.
    @Test("a mangled file is written over rather than making the store useless")
    func corruptFileIsRecoveredFrom() async throws {
        let sandbox = Sandbox()
        try sandbox.seed(Data("nonsense, entirely".utf8))
        let store = DictationHistoryStore(file: sandbox.file)
        #expect(try await store.append(spoken("Now."), keeping: week).map(\.text) == ["Now."])
        #expect(sandbox.onDisk()?.map(\.text) == ["Now."])
    }

    // MARK: A disk that says no

    /// A sandbox with a plain file where the store expects its folder, the cheapest real filesystem refusal.
    private func blockedSandbox() throws -> Sandbox {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: sandbox.folder)
        return sandbox
    }

    @Test("a write the disk refuses is reported, not swallowed")
    func writeFailureThrows() async throws {
        let sandbox = try blockedSandbox()
        let store = DictationHistoryStore(file: sandbox.file)
        await #expect(throws: HistoryStoreError.couldNotWrite) {
            try await store.append(spoken("Now."), keeping: week)
        }
    }

    @Test("a clear the disk refuses is reported too")
    func clearFailureThrows() async throws {
        // The store points at an existing file made undeletable, so there is something whose removal fails.
        let sandbox = try blockedSandbox()
        let path = sandbox.folder.path(percentEncoded: false)
        let store = DictationHistoryStore(file: sandbox.folder)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }

        await #expect(throws: HistoryStoreError.couldNotWrite) {
            try await store.deleteEverything()
        }
    }

    /// A refusing disk must not turn "what should I show?" into a thrown error; "nothing" is the answer.
    @Test("a read never fails, even when the tidying it wanted to do cannot happen")
    func readSurvivesAnUnwritableDisk() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Ancient.", daysAgo: 30)])
        try FileManager.default.setAttributes(
            [.immutable: true], ofItemAtPath: sandbox.file.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.immutable: false], ofItemAtPath: sandbox.file.path(percentEncoded: false))
        }

        #expect(await DictationHistoryStore(file: sandbox.file).records(keeping: week).isEmpty)
    }

    // MARK: What was changed

    @Test("every change across the history comes back, newest dictation first")
    func changesAcrossTheHistory() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([
            changed("Uttrflow is late.", wrote: "Uttrflow"),
            changed("Postgres is up.", wrote: "Postgres", daysAgo: 1),
        ])
        let history = await DictationHistoryStore(file: sandbox.file).changes(keeping: week)
        #expect(history.corrections.map(\.wrote) == ["Uttrflow", "Postgres"])
    }

    @Test("the list can be narrowed to what is still applied")
    func changesInScope() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([
            changed("Uttrflow is late.", wrote: "Kept"),
            changed("Postgres is up.", wrote: "Reverted", isUndone: true),
        ])
        let store = DictationHistoryStore(file: sandbox.file)
        let applied = await store.changes(in: .applied, keeping: week)
        let undone = await store.changes(in: .undone, keeping: week)
        #expect(applied.corrections.map(\.wrote) == ["Kept"])
        #expect(undone.corrections.map(\.wrote) == ["Reverted"])
    }

    /// A change belonging to a dictation the user was told is gone must not outlive it on another page.
    @Test("a change expires with the dictation it was made in")
    func changesExpire() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([changed("Ancient.", wrote: "Ancient", daysAgo: 30)])
        let history = await DictationHistoryStore(file: sandbox.file).changes(keeping: week)
        #expect(history.corrections.isEmpty)
    }

    @Test("a history holding one dictation from before changes were kept still lists the rest")
    func incompleteHistory() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([changed("Uttrflow is late.", wrote: "Uttrflow"), spoken("From before.")])
        let history = await DictationHistoryStore(file: sandbox.file).changes(keeping: week)
        #expect(history.corrections.map(\.wrote) == ["Uttrflow"])
    }

    // MARK: Flagging

    @Test("flagging a dictation reaches the disk, and flagging it again puts it back")
    func flagging() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([spoken("Right, the drafting is done.")])
        let store = DictationHistoryStore(file: sandbox.file)
        let id = try #require(await store.records(keeping: week).first?.id)

        #expect(try await store.toggleFlag(id, keeping: week) == true)
        #expect(await store.records(keeping: week).first?.isFlagged == true)
        #expect(sandbox.onDisk()?.first?.isFlagged == true)

        #expect(try await store.toggleFlag(id, keeping: week) == false)
        #expect(await store.records(keeping: week).first?.isFlagged == false)
    }

    /// The caller holds a list that does not match the disk, and is told rather than quietly succeeding.
    @Test("says nothing was flagged when the dictation is not there")
    func flaggingSomethingGone() async throws {
        let store = DictationHistoryStore(file: Sandbox().file)
        #expect(try await store.toggleFlag(UUID(), keeping: week) == nil)
    }

    // MARK: Undoing

    @Test("undoing puts the words back on disk and names the entry to blame")
    func undoReachesTheDisk() async throws {
        let sandbox = Sandbox()
        let entry = UUID()
        let record = changed("Uttrflow is late.", wrote: "Uttrflow", entry: entry)
        let correction = try #require(record.changes?.corrections.first)
        try sandbox.seed([record])
        let store = DictationHistoryStore(file: sandbox.file)

        #expect(try await store.undoCorrection(correction.id, keeping: week) == entry)
        #expect(sandbox.onDisk()?.map(\.text) == ["utter flow is late."])
        #expect(sandbox.onDisk()?.first?.changes?.corrections.map(\.isUndone) == [true])
    }

    /// End to end as the user meets it: flag the dictation, then put one of its changes back.
    @Test("a dictation the user flagged is still flagged after one of its changes is undone")
    func flagSurvivesAnUndo() async throws {
        let sandbox = Sandbox()
        let record = changed("Uttrflow is late.", wrote: "Uttrflow")
        let correction = try #require(record.changes?.corrections.first)
        try sandbox.seed([record])
        let store = DictationHistoryStore(file: sandbox.file)

        #expect(try await store.toggleFlag(record.id, keeping: week) == true)
        _ = try await store.undoCorrection(correction.id, keeping: week)

        let kept = try #require(await store.records(keeping: week).first)
        #expect(kept.changes?.corrections.first?.isUndone == true)
        #expect(kept.isFlagged, "the flag was set before the undo and must survive it")
        #expect(sandbox.onDisk()?.first?.isFlagged == true)
    }

    /// Nothing to undo is not a failure, and must not count a second revert against an entry rejected once.
    @Test("undoing what is not there, or is already undone, changes nothing")
    func undoNothing() async throws {
        let sandbox = Sandbox()
        let record = changed("Uttrflow is late.", wrote: "Uttrflow")
        let correction = try #require(record.changes?.corrections.first)
        try sandbox.seed([record])
        let store = DictationHistoryStore(file: sandbox.file)

        #expect(try await store.undoCorrection(UUID(), keeping: week) == nil)
        #expect(sandbox.onDisk()?.map(\.text) == ["Uttrflow is late."])
        _ = try await store.undoCorrection(correction.id, keeping: week)
        #expect(try await store.undoCorrection(correction.id, keeping: week) == nil)
    }

    @Test("an undo the disk refuses is reported, not swallowed")
    func undoFailureThrows() async throws {
        let sandbox = Sandbox()
        let record = changed("Uttrflow is late.", wrote: "Uttrflow")
        let correction = try #require(record.changes?.corrections.first)
        try sandbox.seed([record])
        let path = sandbox.file.path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }

        await #expect(throws: HistoryStoreError.couldNotWrite) {
            try await DictationHistoryStore(file: sandbox.file)
                .undoCorrection(correction.id, keeping: week)
        }
    }

    // MARK: Files this build did not write

    /// The reason ``RecordedChanges`` salvages instead of throwing. See Docs/core-history-decoding.md.
    @Test("a change this build cannot read costs that change, never the history")
    func unreadableChangeKeepsTheHistory() async throws {
        let sandbox = Sandbox()
        try sandbox.seed(
            Data(
                """
                [{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","text":"Uttrflow is late.",\
                "when":721692800,"isFlagged":false,"changes":{"corrections":[\
                {"id":"6BA7B812-9DAD-11D1-80B4-00C04FD430C8","heard":"utter flow",\
                "wrote":"Uttrflow","wordRange":[0,2],\
                "entryID":"6BA7B811-9DAD-11D1-80B4-00C04FD430C8",\
                "reason":"heardInAnotherLanguage","heardConfidence":0.3,"isUndone":false}],\
                "snippets":[]}}]
                """.utf8))

        let records = await DictationHistoryStore(file: sandbox.file).records(keeping: week)

        #expect(records.map(\.text) == ["Uttrflow is late."])
        // Present and empty: measured, and its one change is one this build has nothing true to say about.
        #expect(records.first?.changes?.corrections.isEmpty == true)
    }

    // MARK: Two things at once

    /// The pipeline writes while a window reads; each append is load-change-write with no suspension inside.
    @Test("concurrent writing and reading loses nothing")
    func concurrentAccess() async {
        let sandbox = Sandbox()
        let store = DictationHistoryStore(file: sandbox.file)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { _ = try? await store.append(spoken("Line \(index)."), keeping: week) }
                group.addTask { _ = await store.records(keeping: week) }
            }
        }

        let kept = await store.records(keeping: week)
        #expect(kept.count == 40)
        #expect(Set(kept.map(\.text)).count == 40)
    }
}
