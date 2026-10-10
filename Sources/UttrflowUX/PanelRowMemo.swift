// Builds each panel row once per clip and panel open, so an arrow key rebuilds only what changed.
private import Synchronization
import Foundation
import UttrflowClipboard
import UttrflowCore

/// Remembers the rows last drawn, keyed by clip, with selection applied afterwards.
final class PanelRowMemo: Sendable, Equatable {
    /// Everything outside the clip that a row's words depend on; a change to any of it forgets every row.
    struct Context: Sendable, Equatable {
        let needle: String
        let locale: Locale
        let now: Date
        let imagesFolder: URL?
        let formattableLanguages: Set<CodeLanguage>
        let revealed: Set<Clip.ID>
        let missingImages: Set<Clip.ID>
    }

    /// What one row was built from, compared before it is reused.
    struct Key: Sendable, Equatable {
        let result: PanelResult
        let isMasked: Bool
        let isGone: Bool
    }

    private struct Built {
        var context: Context?
        var rows: [Clip.ID: (key: Key, row: PanelRow)] = [:]
        var builds = 0
        var listID: UUID?
        var presentationID = UUID()
        var presentedRows: [PanelRow]?
        var groupedListID: UUID?
        var groupedRows: [PanelResultGroup]?
        var rowVisits = 0
        var groupBuilds = 0
    }

    private let built = Mutex(Built())

    init() {}

    /// How many rows have been built rather than reused, for the tests that hold the arrow key to a constant cost.
    var builds: Int { built.withLock { $0.builds } }
    var rowVisits: Int { built.withLock { $0.rowVisits } }
    var groupBuilds: Int { built.withLock { $0.groupBuilds } }
    var presentationID: UUID { built.withLock { $0.presentationID } }

    func rows(
        listID: UUID, results: [PanelResult], context: Context,
        building build: (PanelResult) -> PanelRow
    ) -> [PanelRow] {
        if let cached = built.withLock({ memo -> [PanelRow]? in
            guard memo.listID == listID, memo.context == context else { return nil }
            return memo.presentedRows
        }) {
            return cached
        }

        built.withLock { $0.rowVisits += results.count }
        var rows: [PanelRow] = []
        rows.reserveCapacity(results.count)
        for result in results {
            let key = Key(
                result: result,
                isMasked: result.clip.kind == .secret && !context.revealed.contains(result.id),
                isGone: result.clip.image != nil && context.missingImages.contains(result.id))
            let row = self.row(for: key, in: context) { build(result) }
            rows.append(row)
        }
        built.withLock { memo in
            memo.listID = listID
            memo.context = context
            memo.presentedRows = rows
            memo.presentationID = UUID()
            memo.groupedListID = nil
            memo.groupedRows = nil
        }
        return rows
    }

    func groups(
        for listID: UUID, building build: () -> [PanelResultGroup]
    ) -> [PanelResultGroup] {
        if let cached = built.withLock({ memo -> [PanelResultGroup]? in
            guard memo.groupedListID == listID else { return nil }
            return memo.groupedRows
        }) {
            return cached
        }
        let rows = build()
        built.withLock { memo in
            memo.groupedListID = listID
            memo.groupedRows = rows
            memo.groupBuilds += 1
        }
        return rows
    }

    func row(for key: Key, in context: Context, building build: () -> PanelRow) -> PanelRow {
        let known = built.withLock { memo -> PanelRow? in
            if memo.context != context {
                memo.context = context
                memo.rows = [:]
            }
            guard let hit = memo.rows[key.result.id], hit.key == key else { return nil }
            return hit.row
        }
        let row: PanelRow
        if let known {
            row = known
        } else {
            row = build()
            built.withLock {
                $0.rows[key.result.id] = (key, row)
                $0.builds += 1
            }
        }
        return row
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: PanelRowMemo, rhs: PanelRowMemo) -> Bool { true }
}
