// The encrypted evidence ledger every inferred fact projects from. See `Docs/learned-state.md`.

public import struct Foundation.URL
public import class Foundation.FileManager
public import struct Foundation.CocoaError

/// One observed fact about one subject: never raw text, only a kind, a key, a signed weight and a day.
public struct EvidenceRow: Sendable, Equatable, Codable {
    /// The closed set of observations; a new fact is a new case, never a new counter.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case use, revert, restore, sighting
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

    /// The file is injected; production registration waits on the store compatibility contract.
    public init(file: URL, encryptedStore: EncryptedStore) {
        self.file = file
        self.encryptedStore = encryptedStore
    }

    /// Every row in append order; empty when the file is missing, unreadable or from a newer build.
    public func rows() -> [EvidenceRow] {
        (try? load()) ?? []
    }

    /// Appends rows after the ones on disk, refusing when those cannot be read.
    public func append(_ newRows: [EvidenceRow]) throws {
        guard !newRows.isEmpty else { return }
        let kept = try load()
        let version = EvidenceLedgerFile.currentVersion
        let contents = EvidenceLedgerFile(schemaVersion: version, rows: kept + newRows)
        try encryptedStore.write(contents, to: file)
    }

    /// Deletes the whole ledger; an already absent file is a completed reset.
    public func reset() throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func load() throws(EvidenceLedgerError) -> [EvidenceRow] {
        switch encryptedStore.read(EvidenceLedgerFile.self, from: file) {
        case .missing:
            return []
        case .unreadable:
            throw .unreadable
        case .read(let contents):
            guard contents.schemaVersion <= EvidenceLedgerFile.currentVersion else {
                throw .newerVersion(contents.schemaVersion)
            }
            return contents.rows
        }
    }
}
