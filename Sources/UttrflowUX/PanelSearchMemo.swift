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

    /// How many recent lists are kept, most recent last; enough to walk back a long word one Backspace at a time.
    static let depth = 32

    private let listed = Mutex<[Listed]>([])
    /// Length-changing folds can make a longer query match text that the shorter query did not.
    private let foldingProfile = Mutex<([Clip], Locale, Bool)?>(nil)

    init() {}

    /// The rows for this view: a recent list when one had the same view, and otherwise a scan told which clips a shorter query has already ruled out.
    func rows(
        for view: View,
        scanning scan: (Set<Clip.ID>?) -> [PanelMatch],
        ranking rank: ([PanelMatch]) -> ([PanelResult], [PanelMatchField: Int])
    ) -> ([PanelResult], [PanelMatchField: Int]) {
        let recent = listed.withLock { $0 }
        if let hit = recent.last(where: { $0.view == view }) {
            remember(hit)
            return (hit.rows, hit.omitted)
        }
        // The narrowest earlier list that still bounds this query rules in the fewest clips.
        let candidates = recent.filter { $0.view.narrows(to: view) }
        let bound =
            candidates.isEmpty || hasLengthChangingFold(in: view.clips, locale: view.locale)
            ? nil
            : candidates.min { $0.matches.count < $1.matches.count }
        let ruledIn = bound.map { Set($0.matches.map(\.result.id)) }
        let matches = scan(ruledIn)
        let (rows, omitted) = rank(matches)
        remember(Listed(view: view, matches: matches, rows: rows, omitted: omitted))
        return (rows, omitted)
    }

    /// Whether any clip's searchable text has a fold that changes scalar count, cached for this clip list and locale.
    private func hasLengthChangingFold(in clips: [Clip], locale: Locale) -> Bool {
        foldingProfile.withLock { profile in
            if let profile, profile.0 == clips, profile.1 == locale { return profile.2 }
            let found = clips.contains { clip in
                hasLengthChangingSearchFold(in: clip.text, locale: locale)
            }
            profile = (clips, locale, found)
            return found
        }
    }

    /// Keeps `entry` as the most recent list, dropping lists of another clip list, which can never be reused.
    private func remember(_ entry: Listed) {
        listed.withLock { recent in
            recent.removeAll { $0.view == entry.view || $0.view.clips != entry.view.clips }
            recent.append(entry)
            if recent.count > Self.depth { recent.removeFirst(recent.count - Self.depth) }
        }
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: PanelSearchMemo, rhs: PanelSearchMemo) -> Bool { true }
}

extension PanelSearchMemo.View {
    /// Whether what this view found still bounds `later`: the same clips under the same tabs, and a query that only grew.
    func narrows(to later: Self) -> Bool {
        guard clips == later.clips, filter == later.filter, scope == later.scope,
            category == later.category, locale == later.locale, revealed == later.revealed,
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
            clips: snapshot.clips, needle: snapshot.needle, filter: snapshot.filter,
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
