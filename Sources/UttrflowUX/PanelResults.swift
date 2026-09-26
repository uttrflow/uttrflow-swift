// What the panel lists: the rows that survive the view, how they rank, and which is selected.
public import Foundation
public import UttrflowClipboard

/// Which part of a clip the search found; the case order is the order of precedence.
public enum PanelMatchField: Int, Sendable, Equatable, CaseIterable {
    /// The name the user gave it.
    case alias
    /// The collection it is filed in.
    case category
    /// The clip's own text.
    case content
}

/// A clip that survived the current view, and why it is here.
public struct PanelResult: Sendable, Equatable, Identifiable {
    /// The clip.
    public let clip: Clip
    /// Absent when nothing has been typed; with an empty field every clip is here for no reason.
    public let match: PanelMatchField?
    /// Whether what was typed is this clip's alias, not merely inside it; it alone outranks a pin.
    public let isExactAlias: Bool

    /// The clip's identity.
    public var id: Clip.ID { clip.id }

    /// Builds a result.
    public init(clip: Clip, match: PanelMatchField?, isExactAlias: Bool) {
        self.clip = clip
        self.match = match
        self.isExactAlias = isExactAlias
    }
}

/// The rows the panel is showing, in the order it shows them, and which one is selected.
public struct PanelResults: Sendable, Equatable {
    /// What is listed, in order.
    public let rows: [PanelResult]
    /// How many matches of each kind were left out of ``rows``; the cap decides what Return can reach.
    public let omitted: [PanelMatchField: Int]
    /// Always a real row while there is one, and `nil` only when there are none.
    public let selectedIndex: Int?

    /// Builds the results; nothing omitted unless said.
    public init(
        rows: [PanelResult], selectedIndex: Int?, omitted: [PanelMatchField: Int] = [:]
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.omitted = omitted
    }

    /// What Return would insert.
    public var selected: Clip? { selectedIndex.map { rows[$0].clip } }
}

extension PanelSnapshot {
    /// What the panel is showing right now, found once for each list of clips, query and tab, so Return and an arrow key share the search.
    public var results: PanelResults {
        let (rows, omitted) = searchMemo.rows(
            for: PanelSearchMemo.View(self), scanning: matches(ruledIn:), ranking: ranked)
        return PanelResults(
            rows: rows, selectedIndex: Self.index(of: selection, in: rows), omitted: omitted)
    }

    /// Every clip this view admits, and why it is here; `ruledIn` names the clips a shorter query found, whose text alone still has to be searched, and `nil` searches every clip's.
    func matches(ruledIn: Set<Clip.ID>?) -> [PanelMatch] {
        let needle = self.needle
        // A tab narrows what is browsed, never what is searched, so typing looks everywhere.
        let wanted = needle.isEmpty ? Self.name(category) : nil
        // The bottom bar is a tab too, and `nil` rather than `.history` so a search still finds dictations.
        let browsing: PanelScope? = needle.isEmpty ? scope : nil

        return clips.enumerated().compactMap { position, clip -> PanelMatch? in
            guard browsing?.admits(clip, inCollection: wanted != nil) ?? true,
                filter.admits(clip.kind)
            else { return nil }
            if let wanted, Self.name(clip.category) != wanted { return nil }
            guard !needle.isEmpty else {
                return PanelMatch(
                    position: position,
                    result: PanelResult(clip: clip, match: nil, isExactAlias: false))
            }
            // The exact test comes first, so "/pgprod" still finds the clip aliased "pgprod".
            let isExact = Self.isAlias(needle, of: clip, locale: locale)
            // An alias and a collection name are words and are searched for every clip; only a clip's own text is long enough to be worth skipping.
            let matched: PanelMatchField? =
                isExact
                ? .alias
                : Self.field(
                    matching: needle, in: clip, locale: locale,
                    searchingText: (ruledIn?.contains(clip.id) ?? true) && !isMasked(clip))
            guard let matched else { return nil }
            return PanelMatch(
                position: position,
                result: PanelResult(clip: clip, match: matched, isExactAlias: isExact))
        }
    }

    /// Whether a clip is a secret still hidden, whose text is never searched. See `Docs/panel.md`.
    func isMasked(_ clip: Clip) -> Bool { clip.kind == .secret && !revealed.contains(clip.id) }

    /// The matches in the order they are drawn, and how many of each kind the cap left out.
    func ranked(_ matches: [PanelMatch]) -> ([PanelResult], [PanelMatchField: Int]) {
        let needle = self.needle
        // A clip whose whole text is the query can never be narrowed to, so it leads its group.
        let whole = Set(
            matches.lazy.filter { $0.result.match == .content }.map(\.result.clip)
                .filter { Self.isWhole(needle, of: $0, locale: self.locale) }.map(\.id))
        let ordered = matches.sorted { Self.rank($0, whole: whole) < Self.rank($1, whole: whole) }
            .map(\.result)
        return Self.capping(ordered) { row in
            // A collection named exactly is asked for whole; there is nothing more to type to narrow it.
            row.match == .category
                && row.clip.category?.compare(
                    needle, options: [.caseInsensitive, .diacriticInsensitive], locale: self.locale)
                    == .orderedSame
        }
    }

    /// Whether a clip's whole text, trimmed, is the query, ignoring case and accents.
    static func isWhole(_ needle: String, of clip: Clip, locale: Locale) -> Bool {
        clip.text.trimmingCharacters(in: .whitespacesAndNewlines).compare(
            needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            == .orderedSame
    }

    /// Match field, then exact alias or whole text, then pinned, then arrival order, so groups are contiguous for ↓.
    static func rank(_ entry: PanelMatch, whole: Set<Clip.ID>) -> (Int, Int, Int, Int) {
        (
            entry.result.match?.rawValue ?? 0,
            entry.result.isExactAlias || whole.contains(entry.result.clip.id) ? 0 : 1,
            entry.result.clip.isPinned ? 0 : 1,
            entry.position
        )
    }

    /// Keeps at most ``PanelPresenter/rowsPerGroup`` of each kind of match; browsing is never capped.
    static func capping(
        _ rows: [PanelResult], uncapped: (PanelResult) -> Bool = { _ in false }
    ) -> ([PanelResult], [PanelMatchField: Int]) {
        var kept: [PanelResult] = []
        var seen: [PanelMatchField: Int] = [:]
        var omitted: [PanelMatchField: Int] = [:]
        for row in rows {
            guard let field = row.match, !uncapped(row) else {
                kept.append(row)
                continue
            }
            let count = seen[field, default: 0]
            seen[field] = count + 1
            if count < PanelPresenter.rowsPerGroup {
                kept.append(row)
            } else {
                omitted[field, default: 0] += 1
            }
        }
        return (kept, omitted)
    }

    /// Where the selection has landed; a clip missing from the list falls back to the top, not nothing.
    static func index(of selection: Clip.ID?, in rows: [PanelResult]) -> Int? {
        guard !rows.isEmpty else { return nil }
        return selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
    }

    /// The strongest part of a clip the query appears in: alias, then category, then content, the last searched only where an earlier query has not already ruled the clip out.
    static func field(
        matching needle: String, in clip: Clip, locale: Locale, searchingText: Bool = true
    ) -> PanelMatchField? {
        let fields: [(PanelMatchField, String?)] = [
            (.alias, clip.alias), (.category, clip.category),
            (.content, searchingText ? clip.text : nil),
        ]
        return fields.first { $0.1?.contains(needle, ignoringCaseAndAccentsIn: locale) == true }?.0
    }

    /// Whether what was typed is this clip's alias, slash or no slash.
    static func isAlias(_ needle: String, of clip: Clip, locale: Locale) -> Bool {
        guard let alias = clip.alias else { return false }
        // The same reduction the alias field saves through, so both spell one name.
        let typed = PanelAlias.handle(needle, locale: locale)
        return !typed.isEmpty && typed == PanelAlias.handle(alias, locale: locale)
    }
}
