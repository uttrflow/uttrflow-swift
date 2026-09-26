// Searches the history once for each query rather than once for each keystroke, and not at all for an arrow key.
private import Synchronization
import Foundation
import UttrflowClipboard

/// One clip that matched, with the position the store keeps it at, which ranking needs to hold copy order.
struct PanelMatch: Sendable, Equatable {
    let position: Int
    let result: PanelResult
}

/// Remembers the last list drawn, so a query that only grew is searched for in what the shorter one found.
final class PanelSearchMemo: Sendable, Equatable {
    /// Everything that decides which rows are listed; a change to anything else, the selection above all, reuses them.
    struct View: Sendable, Equatable {
        let clips: [Clip]
        let needle: String
        let filter: PanelFilter
        let scope: PanelScope
        let category: String?
        let locale: Locale
        let revealed: Set<Clip.ID>
    }

    /// What one view found, and the rows it was ranked and capped into.
    private struct Listed {
        let view: View
        let matches: [PanelMatch]
        let rows: [PanelResult]
        let omitted: [PanelMatchField: Int]
    }

    private let listed = Mutex<Listed?>(nil)

    init() {}

    /// The rows for this view: the last ones when nothing that decides them moved, and otherwise a scan told which clips a shorter query has already ruled out.
    func rows(
        for view: View,
        scanning scan: (Set<Clip.ID>?) -> [PanelMatch],
        ranking rank: ([PanelMatch]) -> ([PanelResult], [PanelMatchField: Int])
    ) -> ([PanelResult], [PanelMatchField: Int]) {
        let last = listed.withLock { $0 }
        if let last, last.view == view { return (last.rows, last.omitted) }
        let ruledIn = last.flatMap { $0.view.narrows(to: view) ? Set($0.matches.map(\.result.id)) : nil }
        let matches = scan(ruledIn)
        let (rows, omitted) = rank(matches)
        listed.withLock { $0 = Listed(view: view, matches: matches, rows: rows, omitted: omitted) }
        return (rows, omitted)
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: PanelSearchMemo, rhs: PanelSearchMemo) -> Bool { true }
}

extension PanelSearchMemo.View {
    /// Whether what this view found still bounds `later`: the same clips under the same tabs, and a query that only grew.
    func narrows(to later: Self) -> Bool {
        guard clips == later.clips, filter == later.filter, scope == later.scope,
            category == later.category, locale == later.locale, revealed == later.revealed,
            !needle.isEmpty,
            !later.needle.isEmpty
        else { return false }
        // Asked of the matcher rather than of the characters, so a query it would not find in the longer one searches again.
        return later.needle.contains(needle, ignoringCaseAndAccentsIn: later.locale)
    }

    /// The view a panel is listing.
    init(_ snapshot: PanelSnapshot) {
        self.init(
            clips: snapshot.clips, needle: snapshot.needle, filter: snapshot.filter,
            scope: snapshot.scope, category: snapshot.category, locale: snapshot.locale,
            revealed: snapshot.revealed)
    }
}
