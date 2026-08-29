public import UttrflowCore
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// Everything the user has dictated, kept on this Mac between launches.
///
/// Its own file under Application Support rather than a key in `UserDefaults` beside
/// the settings: this grows without bound, ages out on a clock, and is the one store
/// whose contents are the user's own words rather than their preferences. Nothing else
/// reads that file, so nothing else can be surprised by its size.
///
/// An actor rather than a `Mutex`-guarded box, which is the other pattern in this
/// package. ``SampleAccumulator`` takes a lock because its writer is CoreAudio's
/// real-time thread, which must never wait; nothing here is real-time — the writer is
/// a dictation that has already finished, and the readers are a window and a menu. A
/// lock would have to be held across a file read and a whole-file rewrite, blocking
/// whichever thread asked, and the thread that asks most often is the main one. An
/// actor turns that same waiting into a suspension, so the caller's thread is free.
///
/// Nothing is cached in memory. The file is the single source of truth, and a copy
/// beside it would be a second one: it would disagree with a user who deleted the file
/// in the Finder, and would have to be invalidated by code that cannot see them do it.
/// A read happens when a window is drawn, not per keystroke, so re-reading is cheap
/// enough to be worth the certainty.
public actor DictationHistoryStore {
    /// A thousand dictations.
    ///
    /// The whole file is rewritten on every dictation, so the cap is really a bound on
    /// that write: at a few hundred bytes a record, a thousand is a couple of hundred
    /// kilobytes — one cheap atomic write — where an uncapped file eventually is not.
    /// It sits well above what the default window holds, so in ordinary use the
    /// promise does the deleting and the cap never has to. And because the cap only
    /// ever removes *more*, it cannot keep anything longer than the user was told.
    public static let defaultCapacity = 1_000

    /// The file. Injected so a test writes into a temporary directory and never into
    /// the history of whoever is running it.
    private let file: URL

    /// The most records kept, oldest discarded first.
    private let capacity: Int

    public init(
        file: URL = DictationHistoryStore.defaultFile(),
        capacity: Int = DictationHistoryStore.defaultCapacity
    ) {
        self.file = file
        // Clamped rather than trusted, for the reason ``RecentDictations`` gives about
        // its own: a negative capacity would trap in `prefix`, and a history that keeps
        // nothing is a far better outcome than a crash.
        self.capacity = max(0, capacity)
    }

    /// Where the history lives when the app has not been told otherwise.
    ///
    /// Versioned in the name so that a shape too different to read field by field can
    /// one day be introduced beside this one rather than on top of it.
    ///
    /// - Parameter directory: The container to put Uttrflow's folder in. Nothing but a
    ///   test has a reason to pass one.
    /// - Returns: The file the history is read from and written to.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        directory.appending(path: "Uttrflow/history.v1.json", directoryHint: .notDirectory)
    }

    // MARK: - Reading

    /// Everything still within the window, newest first.
    ///
    /// The window is applied here and not only where things are written, because the
    /// promise is about elapsed time and time passes while the app sits idle. It is
    /// applied to the *disk* here too: a user who dictated once a fortnight ago and
    /// never again was still told the words would be deleted, and a store that tidied
    /// only when something new arrived would keep them for ever.
    ///
    /// That rewrite is best-effort. Refusing to answer because the disk refused the
    /// tidying would punish the reader for something the reader cannot fix, and either
    /// way nothing the user was told is gone comes back on screen.
    public func records(keeping retention: Retention) -> [DictationRecord] {
        let stored = load()
        let kept = retained(stored, keeping: retention)
        if kept.count != stored.count { try? persist(kept) }
        return kept
    }

    /// Every change Uttrflow made across the history still within the window.
    ///
    /// One call rather than one for the list and another for whether the list is
    /// complete, because the two are read together — the Corrections page draws the
    /// rows, the accuracy figure is gated on the completeness — and two reads could
    /// answer from two different files.
    ///
    /// Goes through ``records(keeping:)``, so the retention promise is kept here too: a
    /// change belonging to a dictation the user was told is gone must not outlive it on
    /// another page.
    public func changes(
        in scope: CorrectionsScope = .all, keeping retention: Retention
    ) -> CorrectionHistory {
        CorrectionHistory(of: records(keeping: retention), in: scope)
    }

    // MARK: - Writing

    /// Records a dictation and answers with the history as it now stands, newest first.
    ///
    /// Answers with the list rather than nothing so a caller cannot draw a menu from a
    /// copy it forgot to refresh: asking a second time is a second chance to disagree.
    @discardableResult
    public func append(
        _ record: DictationRecord, keeping retention: Retention
    ) throws(HistoryStoreError) -> [DictationRecord] {
        // Prepended, not sorted in. Order is arrival order for the reason the menu list
        // gives: the clock belongs to the caller, so a machine whose clock moved must
        // not be able to shuffle what the user is shown.
        let kept = retained([record] + load(), keeping: retention)
        try persist(kept)
        return kept
    }

    /// Forgets one dictation, and answers with what is left.
    ///
    /// An identifier that is not there is not an error: the caller asked for it to be
    /// gone, and it is.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> [DictationRecord] {
        let kept = retained(load().filter { $0.id != id }, keeping: retention)
        try persist(kept)
        return kept
    }

    /// Puts one change back, and answers with the dictionary entry to blame for it.
    ///
    /// That answer is the reason this returns anything at all. The caller passes it to
    /// `PersonalDictionaryStore.recordRevert(of:)`, which is how a word the user keeps
    /// rejecting retires itself; an undo that stopped at the history would cross out a
    /// row and leave the bad word to be applied again tomorrow.
    ///
    /// `nil` when no dictation holds that change or the change is already undone.
    /// Neither is an error — the caller asked for it to be put back, and it is — and
    /// neither writes anything, so undoing twice cannot count twice against an entry.
    ///
    /// - Parameters:
    ///   - id: The change to put back.
    ///   - retention: The promise to keep while rewriting the file.
    /// - Returns: The entry to count the revert against, or `nil` if there was nothing
    ///   to undo.
    /// - Throws: ``HistoryStoreError/couldNotWrite`` if the change cannot be persisted,
    ///   because an undo the disk refused must not be reported as done.
    public func undoCorrection(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> UUID? {
        var records = load()
        for (index, record) in records.enumerated() {
            guard let (undone, entryID) = record.undoing(id) else { continue }
            records[index] = undone
            try persist(retained(records, keeping: retention))
            return entryID
        }
        return nil
    }

    /// Turns the user's own verdict on one dictation on or off.
    ///
    /// A toggle rather than a set, because the button is one button and pressing it
    /// twice should leave the dictation as it was found. A caller that could only ever
    /// flag would need to know the current state to offer the right label, which is the
    /// state this already holds.
    ///
    /// - Parameters:
    ///   - id: The dictation to flag or unflag.
    ///   - retention: The promise to keep while rewriting the file.
    /// - Returns: Whether it is flagged now, or `nil` when there is no such dictation —
    ///   which is what a caller holding a stale list should be told.
    /// - Throws: ``HistoryStoreError/couldNotWrite`` if the disk refused the change.
    @discardableResult
    public func toggleFlag(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> Bool? {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        records[index].isFlagged.toggle()
        let flagged = records[index].isFlagged
        try persist(retained(records, keeping: retention))
        return flagged
    }

    /// Forgets everything.
    ///
    /// Reaches the disk inside this call rather than at the next write: a user who
    /// clears their history and then quits must not find it still there.
    public func deleteEverything() throws(HistoryStoreError) {
        try persist([])
    }

    // MARK: - The rules

    /// The retention promise and then the cap, in that order.
    ///
    /// ``DictationRecord/survives(days:now:)`` decides the first, because "deleted
    /// after N days" is one promise and a second implementation of it is a second
    /// chance to keep something too long. The cap then takes the newest, which is a
    /// plain `prefix` only because the list is kept newest-first throughout.
    private func retained(
        _ records: [DictationRecord], keeping retention: Retention
    ) -> [DictationRecord] {
        let surviving = records.filter { $0.survives(days: retention.days, now: retention.now) }
        return Array(surviving.prefix(capacity))
    }

    // MARK: - The file

    /// Reads the file, answering with nothing when there is nothing readable there.
    ///
    /// Absent, unreadable, truncated, hand-edited, or written by a build that knew a
    /// different shape — to a user those all mean the same thing, which is that the app
    /// should still open. Salvaging record by record is not attempted: our own writes
    /// are atomic, so the realistic corruption is a whole file someone mangled, and
    /// half a history restored is harder to explain than none.
    private func load() -> [DictationRecord] {
        guard let data = try? Data(contentsOf: file),
            let records = try? JSONDecoder().decode([DictationRecord].self, from: data)
        else { return [] }
        return records
    }

    /// Writes the whole list, or removes the file when nothing is left to keep.
    ///
    /// Atomically, so that a crash or a full disk cannot leave behind the truncated
    /// file ``load()`` would then have to throw away. Removing rather than writing an
    /// empty array means an emptied history leaves nothing of the user's on disk at
    /// all, which is what "Clear History" says on the tin.
    private func persist(_ records: [DictationRecord]) throws(HistoryStoreError) {
        do {
            guard !records.isEmpty else {
                try removeFile()
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Deletes the file if it is there. Nothing to delete is success, not a failure.
    private func removeFile() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: file)
    }
}
