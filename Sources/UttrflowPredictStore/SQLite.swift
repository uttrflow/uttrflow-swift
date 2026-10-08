// The SQLite layer the corpus sits on: what can go wrong, one open database, and the bindings.
private import Foundation
import SQLite3
import UttrflowCore

/// What can go wrong reaching the corpus on disk.
public enum PredictStoreError: Error, Equatable {
    /// The database could not be opened, and could not be replaced either.
    case cannotOpen(String)
    /// A statement failed for a reason that is not the caller's doing.
    case query(String)
    /// The file on disk is not a database this app wrote.
    case corrupt
    /// The file was written by a newer build, so this one leaves it alone and goes without.
    case newerThanThisBuild(version: Int)
}

/// Tells SQLite to copy a bound string, since Swift may free it before the step runs.
nonisolated(unsafe) private let copyBoundText = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One open database, owned by whichever actor created it and never shared.
final class Database {
    /// SQLite's fixed header distinguishes a legacy file from arbitrary bytes.
    private static let sqliteHeader = Data("SQLite format 3\0".utf8)
    /// The open connection every statement runs against.
    private let handle: OpaquePointer
    /// The path is encrypted only when the app supplies its shared local-store cipher.
    private let file: URL
    /// The shared cipher seals snapshots without adding a database dependency.
    let encryptedStore: EncryptedStore?
    /// Writes wait until migrations finish, then persist once per committed change.
    private var isReady = false
    /// Mutations inside a transaction become one durable snapshot after commit.
    private var transactionDepth = 0
    /// Whether the in-memory image differs from its last durable snapshot.
    private var isDirty = false
    /// The statements compiled so far, kept by their SQL because these run on every keystroke.
    private var cached: [String: OpaquePointer] = [:]

    /// Opens or creates the database, reporting corruption as itself so it can be replaced.
    init(path: String, encryptedStore: EncryptedStore? = nil) throws(PredictStoreError) {
        file = URL(filePath: path)
        self.encryptedStore = encryptedStore
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let opened = sqlite3_open_v2(encryptedStore == nil ? path : ":memory:", &handle, flags, nil)
        guard opened == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw opened == SQLITE_NOTADB ? .corrupt : .cannotOpen(path)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 2_000)
        guard encryptedStore != nil else { return }
        do {
            try loadSnapshot(at: file)
        } catch {
            throw error
        }
    }

    deinit {
        for statement in cached.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    /// How many compiled statements are kept.
    var cachedStatements: Int { cached.count }

    /// Whether committed changes are persisted as encrypted database images.
    var usesEncryptedSnapshots: Bool { encryptedStore != nil }

    /// Runs a statement that returns nothing, such as a schema change or a pragma.
    func execute(_ sql: String) throws(PredictStoreError) {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "sqlite error \(result)"
            sqlite3_free(message)
            throw isCorrupt(result) ? .corrupt : .query(text)
        }
        if Self.changesDatabase(sql) { try markDirty() }
    }

    /// A prepared statement, compiled once and kept, because these run on every keystroke.
    func statement(_ sql: String) throws(PredictStoreError) -> OpaquePointer {
        if let existing = cached[sql] {
            sqlite3_reset(existing)
            sqlite3_clear_bindings(existing)
            return existing
        }
        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
        guard result == SQLITE_OK, let prepared else {
            throw isCorrupt(result) ? .corrupt : .query(lastMessage())
        }
        cached[sql] = prepared
        return prepared
    }

    /// Steps a statement that returns no rows, and says whether it changed anything.
    @discardableResult
    func run(_ sql: String, _ bind: (OpaquePointer) -> Void) throws(PredictStoreError) -> Int {
        let statement = try statement(sql)
        bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw isCorrupt(result) ? .corrupt : .query(lastMessage())
        }
        let changed = Int(sqlite3_changes(handle))
        if changed > 0 { try markDirty() }
        return changed
    }

    /// Steps a statement to exhaustion, handing each row to the reader.
    func rows<T>(
        _ sql: String, _ bind: (OpaquePointer) -> Void, _ read: (OpaquePointer) -> T
    ) throws(PredictStoreError) -> [T] {
        let statement = try statement(sql)
        bind(statement)
        var found: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                found.append(read(statement))
                continue
            }
            guard result == SQLITE_DONE else {
                throw isCorrupt(result) ? .corrupt : .query(lastMessage())
            }
            return found
        }
    }

    /// Runs the body as one transaction, so a step that fails leaves none of the others behind.
    func transaction<T>(_ body: () throws(PredictStoreError) -> T) throws(PredictStoreError) -> T {
        let wasDirty = isDirty
        try execute("BEGIN")
        transactionDepth += 1
        do {
            let result = try body()
            try execute("COMMIT")
            transactionDepth -= 1
            if isReady, transactionDepth == 0, isDirty { try persistSnapshot() }
            return result
        } catch {
            if transactionDepth == 0, isDirty, isReady {
                throw error
            }
            transactionDepth = max(0, transactionDepth - 1)
            try? execute("ROLLBACK")
            isDirty = wasDirty
            throw error
        }
    }

    /// Makes schema creation and migration durable before the corpus is returned.
    func finishOpening() throws(PredictStoreError) {
        isReady = true
        guard encryptedStore != nil else { return }
        if isDirty { try persistSnapshot() }
        try removePlaintextSidecars()
        try? PrivateFile.tighten(at: file)
        try? PrivateFile.excludeFromBackup(at: file)
    }

    /// Persists structural migrations whose DDL does not affect SQLite's row-change count.
    func markSchemaChanged() throws(PredictStoreError) { try markDirty() }

    /// What SQLite says it will do for a statement, which is checkable where a timing is not.
    func plan(of sql: String) throws(PredictStoreError) -> [String] {
        try rows("EXPLAIN QUERY PLAN " + sql, { _ in }) { $0.text(3) }
    }

    /// The row id the last insert produced, for a caller that needs to point at it.
    var lastInsertedIdentifier: Int64 { sqlite3_last_insert_rowid(handle) }

    /// What SQLite says went wrong with the last statement on this connection.
    private func lastMessage() -> String { String(cString: sqlite3_errmsg(handle)) }

    /// Restores a sealed image or copies a legacy SQLite file, including its committed WAL, into memory.
    private func loadSnapshot(at url: URL) throws(PredictStoreError) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            isDirty = true
            return
        }
        let stored: Data
        do { stored = try Data(contentsOf: url) } catch { throw .cannotOpen(url.path) }
        let image: Data
        if EncryptedStore.isSealed(stored) {
            do {
                image = try encryptedStore?.open(stored, for: url.lastPathComponent) ?? stored
            } catch let error as StoreKeyError where error.isMissing {
                throw .corrupt
            } catch {
                throw .cannotOpen("encrypted corpus could not be authenticated")
            }
            try deserialize(image, path: url.path)
        } else {
            guard stored.starts(with: Self.sqliteHeader) else { throw .corrupt }
            try copyLegacyDatabase(at: url.path)
            isDirty = true
        }
    }

    /// Copies an authenticated database image into SQLite-owned memory.
    private func deserialize(_ image: Data, path: String) throws(PredictStoreError) {
        guard !image.isEmpty, let allocation = sqlite3_malloc64(UInt64(image.count)) else {
            throw .corrupt
        }
        let bytes = allocation.assumingMemoryBound(to: UInt8.self)
        image.copyBytes(to: bytes, count: image.count)
        let result = sqlite3_deserialize(
            handle, "main", bytes, Int64(image.count), Int64(image.count),
            UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE))
        guard result == SQLITE_OK else {
            sqlite3_free(allocation)
            throw result == SQLITE_CORRUPT || result == SQLITE_NOTADB ? .corrupt : .cannotOpen(path)
        }
    }

    /// Copies a legacy database through SQLite so any committed WAL frames migrate with it.
    private func copyLegacyDatabase(at path: String) throws(PredictStoreError) {
        var source: OpaquePointer?
        // Read-write, because a read-only connection cannot open a WAL file whose `-shm` was removed on close.
        let result = sqlite3_open_v2(path, &source, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let source else {
            if let source { sqlite3_close_v2(source) }
            throw result == SQLITE_NOTADB ? .corrupt : .cannotOpen(path)
        }
        defer { sqlite3_close_v2(source) }
        guard let backup = sqlite3_backup_init(handle, "main", source, "main") else {
            throw .cannotOpen(path)
        }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard (copied == SQLITE_DONE || copied == SQLITE_OK), finished == SQLITE_OK else {
            throw copied == SQLITE_CORRUPT || copied == SQLITE_NOTADB ? .corrupt : .cannotOpen(path)
        }
    }

    /// Seals the complete in-memory database and atomically replaces the on-disk snapshot.
    private func persistSnapshot() throws(PredictStoreError) {
        guard let encryptedStore else { isDirty = false; return }
        var size: sqlite3_int64 = 0
        guard let serialized = sqlite3_serialize(handle, "main", &size, 0), size > 0 else {
            throw .cannotOpen(file.path)
        }
        let image = Data(bytes: serialized, count: Int(size))
        sqlite3_free(serialized)
        do {
            try PrivateFile.write(
                encryptedStore.seal(image, for: file.lastPathComponent), to: file)
        } catch {
            throw .cannotOpen(file.path)
        }
        isDirty = false
        try removePlaintextSidecars()
    }

    /// Removes sidecars left by the legacy plaintext database after its encrypted image is safe.
    private func removePlaintextSidecars() throws(PredictStoreError) {
        guard encryptedStore != nil else { return }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(filePath: file.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path(percentEncoded: false)) else {
                continue
            }
            do { try FileManager.default.removeItem(at: sidecar) } catch { throw .cannotOpen(sidecar.path) }
        }
    }

    /// Persists a successful mutation only after schema setup and outside a transaction.
    private func markDirty() throws(PredictStoreError) {
        isDirty = true
        if isReady, transactionDepth == 0 { try persistSnapshot() }
    }

    /// Recognizes statements whose successful execution changes the database image.
    private static func changesDatabase(_ sql: String) -> Bool {
        let statement = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["DELETE ", "VACUUM"]
            .contains { statement.hasPrefix($0) }
    }

    /// Whether a result code means the file itself is unusable rather than the query wrong.
    private func isCorrupt(_ result: Int32) -> Bool {
        result == SQLITE_CORRUPT || result == SQLITE_NOTADB
    }
}

/// Binding helpers, named so a call site reads as what it puts where.
extension OpaquePointer {
    /// Puts a string at this one-based placeholder, copied so Swift may free the original.
    func bind(_ index: Int32, _ value: String) {
        sqlite3_bind_text(self, index, value, -1, copyBoundText)
    }

    /// Puts optional text at this one-based placeholder, preserving nil as NULL.
    func bind(_ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(self, index)
            return
        }
        bind(index, value)
    }

    /// Puts a whole number at this one-based placeholder.
    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(self, index, value)
    }

    /// Puts a fractional number at this one-based placeholder.
    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(self, index, value)
    }

    /// The text in this zero-based column, empty where the column holds nothing.
    func text(_ column: Int32) -> String {
        sqlite3_column_text(self, column).map { String(cString: $0) } ?? ""
    }

    /// The text in this zero-based column, or nil when the column holds NULL.
    func optionalText(_ column: Int32) -> String? {
        sqlite3_column_type(self, column) == SQLITE_NULL ? nil : text(column)
    }

    /// The whole number in this zero-based column.
    func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(self, column)) }

    /// The fractional number in this zero-based column.
    func double(_ column: Int32) -> Double { sqlite3_column_double(self, column) }
}
