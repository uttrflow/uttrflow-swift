private import Foundation
private import SQLite3
package import UttrflowPredict

/// Shared legacy storage observations, never linked into the shipping app.
package enum LegacySuccessions {
    package static let query = """
        SELECT entry.text, entry.count, entry.accepted, entry.rejected, entry.self_sourced, entry.last_used
        FROM succession JOIN surface ON surface.id = succession.surface_id
        JOIN entry ON entry.surface_id = surface.id AND entry.text = succession.next
        WHERE surface.bundle_id = ? AND surface.role = ? AND surface.locator = ? AND surface.scope = ?
          AND succession.previous = ? AND entry.superseded_by IS NULL
        ORDER BY succession.count DESC LIMIT 16
        """

    package static func bind(_ statement: OpaquePointer, surface: Surface, previous: String) {
        for (index, value) in [
            surface.bundleIdentifier, surface.role, surface.locator ?? "", surface.scope ?? "",
            previous,
        ].enumerated() {
            _ = value.withCString {
                sqlite3_bind_text(
                    statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    package static func read(_ statement: OpaquePointer) -> Candidate {
        let text = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        return Candidate(
            text: text, source: .succession,
            evidence: Entry(
                text: text, count: Int(sqlite3_column_int64(statement, 1)),
                accepted: Int(sqlite3_column_int64(statement, 2)),
                rejected: Int(sqlite3_column_int64(statement, 3)),
                selfSourced: Int(sqlite3_column_int64(statement, 4)),
                lastUsed: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))),
            isIrreversible: DestructiveCommand.matches(text, failClosedOnUnresolved: true))
    }
}
