private import Foundation
import SQLite3

/// What can go wrong reaching the corpus on disk.
public enum PredictStoreError: Error, Equatable {
    /// The database could not be opened, and could not be replaced either.
    case cannotOpen(String)
    /// A statement failed for a reason that is not the caller's doing.
    case query(String)
    /// The file on disk is not a database this app wrote.
    case corrupt
}

/// Tells SQLite to copy a bound string, since Swift may free it before the step runs.
let copyBoundText = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One open database, owned by whichever actor created it and never shared.
final class Database {
    let handle: OpaquePointer
    private var cached: [String: OpaquePointer] = [:]

    /// Opens or creates the database, reporting corruption as itself so it can be replaced.
    init(path: String) throws(PredictStoreError) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let opened = sqlite3_open_v2(path, &handle, flags, nil)
        guard opened == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw opened == SQLITE_NOTADB ? .corrupt : .cannotOpen(path)
        }
        self.handle = handle
    }

    deinit {
        for statement in cached.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    /// Runs a statement that returns nothing, such as a schema change or a pragma.
    func execute(_ sql: String) throws(PredictStoreError) {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "sqlite error \(result)"
            sqlite3_free(message)
            throw isCorrupt(result) ? .corrupt : .query(text)
        }
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
        return Int(sqlite3_changes(handle))
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

    /// What SQLite says it will do for a statement, which is checkable where a timing is not.
    func plan(of sql: String) throws(PredictStoreError) -> [String] {
        try rows("EXPLAIN QUERY PLAN " + sql, { _ in }) { $0.text(3) }
    }

    /// The row id the last insert produced, for a caller that needs to point at it.
    var lastInsertedIdentifier: Int64 { sqlite3_last_insert_rowid(handle) }

    private func lastMessage() -> String { String(cString: sqlite3_errmsg(handle)) }

    /// Whether a result code means the file itself is unusable rather than the query wrong.
    private func isCorrupt(_ result: Int32) -> Bool {
        result == SQLITE_CORRUPT || result == SQLITE_NOTADB
    }
}

/// Binding helpers, named so a call site reads as what it puts where.
extension OpaquePointer {
    func bind(_ index: Int32, _ value: String) {
        sqlite3_bind_text(self, index, value, -1, copyBoundText)
    }

    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(self, index, value)
    }

    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(self, index, value)
    }

    func text(_ column: Int32) -> String {
        sqlite3_column_text(self, column).map { String(cString: $0) } ?? ""
    }

    func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(self, column)) }

    func double(_ column: Int32) -> Double { sqlite3_column_double(self, column) }
}
