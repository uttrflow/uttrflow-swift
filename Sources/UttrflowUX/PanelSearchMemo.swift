// Searches the history once for each query rather than once for each keystroke, and not at all for an arrow key.
private import Synchronization
import Foundation
import UttrflowClipboard

/// One clip that matched, with the position the store keeps it at, which ranking needs to hold copy order.
struct PanelMatch: Sendable, Equatable {
    let position: Int
    let result: PanelResult
}

/// Remembers the recent lists drawn, so a query searched earlier in this open is not searched again and one that grew is searched in what a shorter one found.
final class PanelSearchMemo: Sendable, Equatable {
    /// Everything that decides which rows are listed; a change to anything else, the selection above all, reuses them.
    struct View: Sendable, Equatable {
        let clips: [Clip]
        let clipsRevision: UUID
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
        let id: UUID
        let matches: [PanelMatch]
        let rows: [PanelResult]
        let indexByID: [Clip.ID: Int]
        let omitted: [PanelMatchField: Int]
    }

    /// How many recent lists are kept, most recent last; enough to walk back a long word one Backspace at a time.
    static let depth = 32

    private let listed = Mutex<[Listed]>([])
    /// Length-changing folds can make a longer query match text that the shorter query did not.
    private let foldingProfile = Mutex<(UUID, Locale, Bool)?>(nil)
    private let searches = Mutex(0)

    var searchScans: Int { searches.withLock { $0 } }

    init() {}

    /// The rows for this view: a recent list when one had the same view, and otherwise a scan told which clips a shorter query has already ruled out.
    func rows(
        for view: View,
        scanning scan: (Set<Clip.ID>?) -> [PanelMatch],
        ranking rank: ([PanelMatch]) -> ([PanelResult], [PanelMatchField: Int])
    ) -> ([PanelResult], [PanelMatchField: Int], UUID) {
        let recent = listed.withLock { $0 }
        if let hit = recent.last(where: { $0.view == view }) {
            remember(hit)
            return (hit.rows, hit.omitted, hit.id)
        }
        // The narrowest earlier list that still bounds this query rules in the fewest clips.
        let candidates = recent.filter { $0.view.narrows(to: view) }
        let bound =
            candidates.isEmpty
                || hasLengthChangingFold(
                    in: view.clips, revision: view.clipsRevision, locale: view.locale)
            ? nil
            : candidates.min { $0.matches.count < $1.matches.count }
        let ruledIn = bound.map { Set($0.matches.map(\.result.id)) }
        searches.withLock { $0 += 1 }
        let matches = scan(ruledIn)
        let (rows, omitted) = rank(matches)
        // The store does not drop a repeated id from an index file, so a clip listed twice selects its first row.
        let indexByID = Dictionary(rows.enumerated().map { ($1.id, $0) }) { first, _ in first }
        let id = UUID()
        remember(
            Listed(
                view: view, id: id, matches: matches, rows: rows, indexByID: indexByID,
                omitted: omitted))
        return (rows, omitted, id)
    }

    func index(of selection: Clip.ID?, for view: View) -> Int? {
        listed.withLock { recent -> Int? in
            guard let entry = recent.last(where: { $0.view == view }), !entry.rows.isEmpty else {
                return nil
            }
            return selection.flatMap { entry.indexByID[$0] } ?? 0
        }
    }

    /// Whether any clip's searchable text has a fold that changes scalar count, cached for this clip list and locale.
    private func hasLengthChangingFold(
        in clips: [Clip], revision: UUID, locale: Locale
    ) -> Bool {
        foldingProfile.withLock { profile in
            if let profile, profile.0 == revision, profile.1 == locale { return profile.2 }
            let found = clips.contains { clip in
                hasLengthChangingSearchFold(in: clip.text, locale: locale)
            }
            profile = (revision, locale, found)
            return found
        }
    }

    /// Keeps `entry` as the most recent list, dropping lists of another clip list, which can never be reused.
    private func remember(_ entry: Listed) {
        listed.withLock { recent in
            recent.removeAll {
                $0.view == entry.view || $0.view.clipsRevision != entry.view.clipsRevision
            }
            recent.append(entry)
            if recent.count > Self.depth { recent.removeFirst(recent.count - Self.depth) }
        }
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: PanelSearchMemo, rhs: PanelSearchMemo) -> Bool { true }
}

extension PanelSearchMemo.View {
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.clipsRevision == rhs.clipsRevision, lhs.needle == rhs.needle, lhs.filter == rhs.filter,
            lhs.locale == rhs.locale, lhs.revealed == rhs.revealed
        else { return false }
        // A search spans every scope and collection, so only an empty query lists by them.
        return !lhs.needle.isEmpty || (lhs.scope == rhs.scope && lhs.category == rhs.category)
    }

    /// Whether what this view found still bounds `later`: the same clips under the same kind tab, and a query that only grew.
    func narrows(to later: Self) -> Bool {
        guard clipsRevision == later.clipsRevision, filter == later.filter, locale == later.locale,
            revealed == later.revealed,
            !needle.isEmpty, !later.needle.isEmpty,
            !hasLengthChangingSearchFold(in: needle, locale: locale),
            !hasLengthChangingSearchFold(in: later.needle, locale: locale)
        else { return false }
        // Asked of the matcher rather than of the characters, so a query it would not find in the longer one searches again.
        return later.needle.contains(needle, ignoringCaseAndAccentsIn: later.locale)
    }

    /// The view a panel is listing.
    init(_ snapshot: PanelSnapshot) {
        self.init(
            clips: snapshot.clips,
            clipsRevision: snapshot.clipsRevision.id, needle: snapshot.needle, filter: snapshot.filter,
            scope: snapshot.scope, category: snapshot.category, locale: snapshot.locale,
            revealed: snapshot.revealed)
    }
}

private func hasLengthChangingSearchFold(in text: String, locale: Locale) -> Bool {
    let scalars = text.unicodeScalars
    guard !scalars.allSatisfy({ $0.value < 0x80 }) else { return false }
    if SearchFolding.hasOverlongGrapheme(in: text) { return true }
    let folded = text.folding(options: SearchFolding.comparisonOptions, locale: locale)
    guard folded.unicodeScalars.count == scalars.count else { return true }
    return scalars.contains { scalar in
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }
}
