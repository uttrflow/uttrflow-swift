// Builds each panel row once per clip and panel open, so an arrow key rebuilds only what changed.
private import Synchronization
import Foundation
import UttrflowClipboard

/// Remembers the rows last drawn, keyed by clip, with selection applied afterwards.
final class PanelRowMemo: Sendable, Equatable {
    /// Everything outside the clip that a row's words depend on; a change to any of it forgets every row.
    struct Context: Sendable, Equatable {
        let needle: String
        let locale: Locale
        let now: Date
        let imagesFolder: URL?
        let formattableLanguages: Set<CodeLanguage>
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
    }

    private let built = Mutex(Built())

    init() {}

    /// How many rows have been built rather than reused, for the tests that hold the arrow key to a constant cost.
    var builds: Int { built.withLock { $0.builds } }

    /// The row for this key, reused when the context and the key are unchanged, with the selection set on it.
    func row(
        for key: Key, in context: Context, isSelected: Bool, building build: () -> PanelRow
    ) -> PanelRow {
        let known = built.withLock { memo -> PanelRow? in
            if memo.context != context {
                memo.context = context
                memo.rows = [:]
            }
            guard let hit = memo.rows[key.result.id], hit.key == key else { return nil }
            return hit.row
        }
        var row: PanelRow
        if let known {
            row = known
        } else {
            row = build()
            built.withLock {
                $0.rows[key.result.id] = (key, row)
                $0.builds += 1
            }
        }
        row.isSelected = isSelected
        return row
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: PanelRowMemo, rhs: PanelRowMemo) -> Bool { true }
}
