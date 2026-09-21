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

    /// The most records kept, oldest discarded first.
    private let capacity: Int

    /// Uses the app's own file and cap unless a test names others.
    public init(
        file: URL = DictationHistoryStore.defaultFile(),
        capacity: Int = DictationHistoryStore.defaultCapacity
    ) {
        self.file = file
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
        let kept = retained(stored, keeping: retention)
        if kept.count != stored.count { try? persist(kept) }
        // A set-aside copy lasts as long as the transcripts in it would have. See `Docs/history-store-file.md`.
        try? LocalStore.removeSetAside(file, stampedBefore: Self.cutoff(of: retention))
        return kept
    }

    /// The moment before which nothing is kept under this promise; zero days keeps nothing at all.
    static func cutoff(of retention: Retention) -> Date {
        guard retention.days > 0 else { return .distantFuture }
        return retention.now.addingTimeInterval(-Double(retention.days) * 86_400)
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
        let kept = retained([record] + load(), keeping: retention)
        try persist(kept)
        return kept
    }

    /// Forgets one dictation, and answers with what is left; an absent identifier is not an error.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: Retention
    ) throws(HistoryStoreError) -> [DictationRecord] {
        let kept = retained(load().filter { $0.id != id }, keeping: retention)
        try persist(kept)
        return kept
    }

    /// Puts one change back, answering with the dictionary entry to count it against, or `nil`.
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

    /// Flips the user's verdict on one dictation, answering with how it stands now, or `nil`.
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

    /// Forgets everything, reaching the disk now rather than at the next write.
    public func deleteEverything() throws(HistoryStoreError) {
        try persist([])
        // A copy set aside from an unreadable file is a transcript too.
        do { try LocalStore.removeSetAside(file) } catch { throw .couldNotWrite }
    }

    // MARK: - The rules

    /// Applies the retention promise and then the cap, in that order.
    private func retained(
        _ records: [DictationRecord], keeping retention: Retention
    ) -> [DictationRecord] {
        let surviving = records.filter { $0.survives(days: retention.days, now: retention.now) }
        return Array(surviving.prefix(capacity))
    }

    // MARK: - The file

    /// Reads the file, setting an unreadable one aside so the next write cannot replace the only copy.
    private func load() -> [DictationRecord] {
        LocalStore.read([DictationRecord].self, from: file).value ?? []
    }

    /// Writes the whole list atomically, or removes the file when nothing is left to keep.
    private func persist(_ records: [DictationRecord]) throws(HistoryStoreError) {
        do {
            guard !records.isEmpty else {
                try removeFile()
                return
            }
            try PrivateFile.write(JSONEncoder().encode(records), to: file)
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
