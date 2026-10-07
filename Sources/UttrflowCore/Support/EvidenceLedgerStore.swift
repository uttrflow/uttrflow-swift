// The encrypted evidence ledger every inferred fact projects from. See `Docs/learned-state.md`.

public import struct Foundation.Date
public import struct Foundation.URL
public import class Foundation.FileManager
public import struct Foundation.CocoaError

/// One observed fact about one subject: never raw text, only a kind, a key, a signed weight and a day.
public struct EvidenceRow: Sendable, Equatable, Codable {
    /// The closed set of observations; a new fact is a new case, never a new counter.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case use, revert, restore, sighting
        /// Style counts, keyed by destination; see ``StyleSignals``.
        case styleMessage, styleWords, styleSentences, styleShortMessage, styleClosingStop
        /// A respelling between two spellings of one listed word, and the user's deletion of it; see `SpellingPreferences`.
        case spellingPreference, spellingPreferenceCleared
        /// A heard-to-meant pair the user kept, undid, or allowed again after undoing; see `ConfusionPairs`.
        case pairConfirmed, pairVetoed, pairAllowed
    }

    /// Which path produced the row.
    public enum Provenance: String, Sendable, Codable, CaseIterable {
        case dictation, undo, user, migration
    }

    /// What was observed.
    public let kind: Kind
    /// The identifier the row is about: a dictionary entry id, a snippet id or a spelling key.
    public let subject: String
    /// Signed so a correction can subtract; compaction sums it.
    public let weight: Int
    /// A day number rather than a timestamp, so a row carries no time of day.
    public let day: Int
    /// The path that wrote the row.
    public let provenance: Provenance

    /// A row; `weight` is `+1` for an ordinary observation.
    public init(kind: Kind, subject: String, weight: Int = 1, day: Int, provenance: Provenance) {
        self.kind = kind
        self.subject = subject
        self.weight = weight
        self.day = day
        self.provenance = provenance
    }

    /// The day number a moment falls on, counted in whole days since 1970, so a row records no hour.
    public static func day(of moment: Date) -> Int {
        Int((moment.timeIntervalSince1970 / secondsPerDay).rounded(.down))
    }

    /// The first instant of the row's day, which retention measures from so a row never outlives its window.
    var start: Date { Date(timeIntervalSince1970: Double(day) * Self.secondsPerDay) }

    private static let secondsPerDay: Double = 86_400
}

/// The ledger file's contents, versioned so a later build can recognise a file it did not write.
struct EvidenceLedgerFile: Sendable, Codable {
    static let currentVersion = 1
    let schemaVersion: Int
    let rows: [EvidenceRow]
}

/// Why the ledger refused a write rather than risk the rows already on disk.
public enum EvidenceLedgerError: Error, Sendable, Equatable {
    /// The file is there and could not be read, so writing would replace rows nobody has seen.
    case unreadable
    /// The file was written by a newer build; its downgrade policy is not decided, so it is left alone.
    case newerVersion(Int)
}

/// Appends evidence rows to one encrypted file on this Mac and deletes them all on reset.
public actor EvidenceLedgerStore {
    private let file: URL
    private let encryptedStore: EncryptedStore

    /// Only a test passes a file other than ``defaultFile(in:)``.
    public init(file: URL, encryptedStore: EncryptedStore) {
        self.file = file
        self.encryptedStore = encryptedStore
    }

    /// Where the ledger lives, versioned in the name; only a test passes a `directory`.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStoreEntry.evidenceLedger.location(in: directory)
    }

    /// Every row inside the History retention window, in append order, deleting expired rows from disk.
    public func rows(keeping window: RetentionWindow) -> [EvidenceRow] {
        guard let stored = try? load() else { return [] }
        try? persist(onDisk(stored, keeping: window), replacing: stored)
        return stored.filter { window.keeps($0.start) }
    }

    /// Appends rows after the ones on disk, dropping expired rows, refusing when the disk cannot be read.
    public func append(_ newRows: [EvidenceRow], keeping window: RetentionWindow) throws {
        let stored = try load()
        try persist(onDisk(stored + newRows, keeping: window), replacing: stored)
    }

    /// Deletes every row of the given kinds about one subject, which is how the user removes one remembered fact.
    public func forget(subject: String, kinds: Set<EvidenceRow.Kind>) throws {
        let stored = try load()
        try persist(stored.filter { $0.subject != subject || !kinds.contains($0.kind) }, replacing: stored)
    }

    /// Deletes every row of the given kinds, whatever they are about.
    public func forget(kinds: Set<EvidenceRow.Kind>) throws {
        let stored = try load()
        try persist(stored.filter { !kinds.contains($0.kind) }, replacing: stored)
    }

    /// Why the ledger cannot be used as it stands, or `nil` when it can; reading never changes the file.
    public func refusal() -> EvidenceLedgerError? {
        do {
            _ = try load()
            return nil
        } catch {
            return error
        }
    }

    /// Deletes the whole ledger; an already absent file is a completed reset.
    public func reset() throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Rows the window keeps, plus expired ones a clock too far ahead to be believed may only hide.
    private func onDisk(_ rows: [EvidenceRow], keeping window: RetentionWindow) -> [EvidenceRow] {
        rows.filter { window.keeps($0.start) || !window.mayDelete($0.start) }
    }

    /// Writes `rows` when they differ from what is stored; no rows left deletes the file.
    private func persist(_ rows: [EvidenceRow], replacing stored: [EvidenceRow]) throws {
        guard rows != stored else { return }
        guard !rows.isEmpty else { return try reset() }
        let contents = EvidenceLedgerFile(schemaVersion: EvidenceLedgerFile.currentVersion, rows: rows)
        try encryptedStore.write(contents, to: file)
    }

    private func load() throws(EvidenceLedgerError) -> [EvidenceRow] {
        switch encryptedStore.read(EvidenceLedgerFile.self, from: file) {
        case .missing:
            return []
        case .unreadable:
            throw .unreadable
        case .read(let contents), .recovered(let contents, _, _, _, _):
            guard contents.schemaVersion <= EvidenceLedgerFile.currentVersion else {
                throw .newerVersion(contents.schemaVersion)
            }
            return contents.rows
        }
    }
}
