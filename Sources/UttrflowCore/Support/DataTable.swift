// Reads a small bundled JSON table, checks it against its schema, and keeps a compiled default when it cannot.

import os

public import struct Foundation.Data
public import class Foundation.Bundle
public import class Foundation.JSONDecoder

/// One row of a bundled table, named by an id that is unique within its table.
public protocol DataTableRow: Decodable, Sendable {
    /// The row's name, unique and non-blank within its table.
    var id: String { get }
}

/// Why a bundled table could not be used.
public enum DataTableError: Error, Equatable, Sendable {
    /// The bundle holds no file of that name.
    case missing(name: String)
    /// The file is there and could not be read.
    case unreadable(name: String)
    /// The file is larger than the table's limit.
    case tooLarge(bytes: Int)
    /// The bytes are not the table's JSON shape.
    case malformed
    /// The file declares a schema version this build does not read.
    case unsupportedSchema(found: Int)
    /// The file holds more rows than the table's limit.
    case tooManyRows(count: Int)
    /// The row at this position has an empty or blank id.
    case blankID(row: Int)
    /// Two rows share this id.
    case duplicateID(String)
}

/// Where a table's rows came from: its bundled file, or the compiled default after the named failure.
public enum DataTableSource: Equatable, Sendable {
    /// The rows are the bundled file's.
    case bundled
    /// The bundled file failed for this reason, and the rows are the compiled default.
    case fallback(DataTableError)
}

/// How large a bundled table may be, so a damaged file cannot make a lookup table unbounded.
public struct DataTableLimits: Equatable, Sendable {
    /// The most bytes the file may hold.
    public let maxBytes: Int
    /// The most rows the file may hold.
    public let maxRows: Int

    /// Builds limits for one table.
    public init(maxBytes: Int, maxRows: Int) {
        self.maxBytes = maxBytes
        self.maxRows = maxRows
    }

    /// The limits every word table is read under. See `Docs/data-tables.md`.
    public static let standard = DataTableLimits(maxBytes: 64 * 1_024, maxRows: 2_000)
}

/// A table's rows, read from one versioned JSON file in the bundle and checked before anything uses them.
public struct DataTable<Row: DataTableRow>: Sendable {
    private static var log: Logger { Logger(subsystem: LocalStore.productionIdentifier, category: "tables") }

    /// The rows, in file order.
    public let rows: [Row]
    /// Whether the rows are the bundled file's or the compiled default's.
    public let source: DataTableSource

    /// Reads `name.json` from `bundle`; on any failure keeps `fallback` and logs why.
    public static func load(
        _ name: String, schema: Int, from bundle: Bundle, fallback: [Row], limits: DataTableLimits = .standard
    ) -> DataTable {
        do {
            let data = try read(name, from: bundle)
            return DataTable(rows: try decode(data, schema: schema, limits: limits), source: .bundled)
        } catch {
            log.fault(
                "Table \(name, privacy: .public) fell back: \(ErrorLog.failure(error), privacy: .public)")
            return DataTable(rows: fallback, source: .fallback(error))
        }
    }

    /// Checks and decodes a table's bytes; the seam malformed input is tested through.
    public static func decode(
        _ data: Data, schema: Int, limits: DataTableLimits
    ) throws(DataTableError) -> [Row] {
        guard data.count <= limits.maxBytes else { throw .tooLarge(bytes: data.count) }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw .malformed }
        guard header.schema == schema else { throw .unsupportedSchema(found: header.schema) }
        guard let body = try? decoder.decode(Body.self, from: data) else { throw .malformed }
        guard body.rows.count <= limits.maxRows else { throw .tooManyRows(count: body.rows.count) }
        try checkIDs(body.rows)
        return body.rows
    }

    private static func read(_ name: String, from bundle: Bundle) throws(DataTableError) -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw .missing(name: name)
        }
        do { return try Data(contentsOf: url) } catch { throw .unreadable(name: name) }
    }

    private static func checkIDs(_ rows: [Row]) throws(DataTableError) {
        var seen = Set<String>()
        for (position, row) in rows.enumerated() {
            guard !row.id.allSatisfy(\.isWhitespace) else { throw .blankID(row: position) }
            guard seen.insert(row.id).inserted else { throw .duplicateID(row.id) }
        }
    }

    private struct Header: Decodable {
        let schema: Int
    }

    private struct Body: Decodable {
        let rows: [Row]
    }
}
