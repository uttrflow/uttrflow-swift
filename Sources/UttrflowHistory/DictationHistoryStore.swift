public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONEncoder

/// Everything the user has dictated, in its own file on this Mac. See `Docs/history-store-file.md`.
public actor DictationHistoryStore {
    /// A thousand dictations, which bounds the whole-file rewrite each one costs.
    public static let defaultCapacity = 1_000

    /// The file, injected so a test writes into a temporary directory rather than a real history.
    private let file: URL

    /// The file's decoded contents, reread only when the file changed on disk.
    var cache: CachedStoredList<[DictationRecord]>

    /// The most records kept, oldest discarded first.
    private let capacity: Int

    /// Uses the app's own file and cap unless a test names others.
    public init(
        file: URL = DictationHistoryStore.defaultFile(),
        capacity: Int = DictationHistoryStore.defaultCapacity
    ) {
        self.file = file
        self.cache = CachedStoredList(file: file)
        // Clamped because a negative capacity would trap in `prefix`.
        self.capacity = max(0, capacity)
    }

    /// Where the history lives, versioned in the name; only a test passes a `directory`.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("history.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Everything still within the window, newest first, tidying the disk as it goes.
    public func records(keeping retention: Retention) -> [DictationRecord] {
        let stored = load()
        let onDisk = keptOnDisk(stored, keeping: retention)
        if onDisk.count != stored.count { try? persist(onDisk) }
        // A set-aside copy lasts as long as the transcripts in it would have. See `Docs/history-store-file.md`.
        try? LocalStore.removeSetAside(file, stamped: Self.window(of: retention).sweepable)
        return retained(stored, keeping: retention)
    }

    /// Every change across the history still within the window, with whether the list is complete.
    public func changes(
        in scope: CorrectionsScope = .all, keeping retention: Retention
    ) -> CorrectionHistory {
        CorrectionHistory(of: records(keeping: retention), in: scope)
    }

    // MARK: - Writing

    /// Records a dictation and answers with the history as it now stands, newest first.
    @discardableResult
    public func append(
        _ record: DictationRecord, keeping retention: Retention
    ) throws(HistoryStoreError) -> [DictationRecord] {
        // Prepended, not sorted in, so a machine whose clock moved cannot reshuffle the list.
        let all = [record] + load()
        try persist(keptOnDisk(all, keeping: retention))
        return retained(all, keeping: retention)
    }

    /// Forgets one dictation, and answers with what is left; an absent identifier is not an error.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> [DictationRecord] {
        let left = load().filter { $0.id != id }
        try persist(keptOnDisk(left, keeping: retention))
        return retained(left, keeping: retention)
    }

    /// Puts one change back, answering with the dictionary entry to count it against, or `nil`.
    public func undoCorrection(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> UUID? {
        var records = load()
        for (index, record) in records.enumerated() {
            guard let (undone, entryID) = record.undoing(id) else { continue }
            records[index] = undone
            try persist(keptOnDisk(records, keeping: retention))
            return entryID
        }
        return nil
    }

    /// Flips the user's verdict on one dictation, answering with how it stands now, or `nil`.
    @discardableResult
    public func toggleFlag(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> Bool? {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        records[index].isFlagged.toggle()
        let flagged = records[index].isFlagged
        try persist(keptOnDisk(records, keeping: retention))
        return flagged
    }

    /// Forgets everything, reaching the disk now rather than at the next write.
    public func deleteEverything() throws(HistoryStoreError) {
        try persist([])
        // A copy set aside from an unreadable file is a transcript too.
        do { try LocalStore.removeSetAside(file) } catch { throw .couldNotWrite }
    }

    // MARK: - The rules

    /// Applies the retention promise and then the cap, in that order: what the caller may be shown.
    private func retained(
        _ records: [DictationRecord], keeping retention: Retention
    ) -> [DictationRecord] {
        let surviving = records.filter { $0.survives(days: retention.days, now: retention.now) }
        return Array(surviving.prefix(capacity))
    }

    /// The same, plus what a clock too far ahead to be believed says is past. See `Docs/retention-clock.md`.
    private func keptOnDisk(
        _ records: [DictationRecord], keeping retention: Retention
    ) -> [DictationRecord] {
        let window = Self.window(of: retention)
        let held = records.filter { window.keeps($0.when) || !window.mayDelete($0.when) }
        return Array(held.prefix(capacity))
    }

    /// The promise as the rule the three stores share states it.
    static func window(of retention: Retention) -> RetentionWindow {
        RetentionWindow(days: retention.days, now: retention.now)
    }

    // MARK: - The file

    /// Reads the file, setting an unreadable one aside so the next write cannot replace the only copy.
    private func load() -> [DictationRecord] {
        cache.load() ?? []
    }

    /// Writes the whole list atomically, or removes the file when nothing is left to keep.
    private func persist(_ records: [DictationRecord]) throws(HistoryStoreError) {
        do {
            guard !records.isEmpty else {
                try removeFile()
                cache.remember(nil)
                return
            }
            try PrivateFile.write(JSONEncoder().encode(records), to: file)
            cache.remember(records)
        } catch {
            cache.forget()
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
