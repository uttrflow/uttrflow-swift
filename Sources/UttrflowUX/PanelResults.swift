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
    /// What the panel is showing right now, computed on every ask so Return has one answer.
    public var results: PanelResults {
        let needle = self.needle
        // A tab narrows what is browsed, never what is searched, so typing looks everywhere.
        let wanted = needle.isEmpty ? Self.name(category) : nil
        // The bottom bar is a tab too, and `nil` rather than `.history` so a search still finds dictations.
        let browsing: PanelScope? = needle.isEmpty ? scope : nil

        // The store's position rides along so equal ranks keep copy order and the sort is total.
        let found = clips.enumerated().compactMap { position, clip -> (Int, PanelResult)? in
            guard browsing?.admits(clip, inCollection: wanted != nil) ?? true,
                filter.admits(clip.kind)
            else { return nil }
            if let wanted, Self.name(clip.category) != wanted { return nil }
            guard !needle.isEmpty else {
                return (position, PanelResult(clip: clip, match: nil, isExactAlias: false))
            }
            // The exact test comes first, so "/pgprod" still finds the clip aliased "pgprod".
            let isExact = Self.isAlias(needle, of: clip, locale: locale)
            let matched: PanelMatchField? =
                isExact ? .alias : Self.field(matching: needle, in: clip, locale: locale)
            guard let matched else { return nil }
            return (position, PanelResult(clip: clip, match: matched, isExactAlias: isExact))
        }

        let ordered = found.sorted { Self.rank($0) < Self.rank($1) }.map { $0.1 }
        let (kept, omitted) = Self.capping(ordered)
        return PanelResults(
            rows: kept, selectedIndex: Self.index(of: selection, in: kept), omitted: omitted)
    }

    /// Match field, then exact alias, then pinned, then arrival order, so groups are contiguous for ↓.
    static func rank(_ entry: (Int, PanelResult)) -> (Int, Int, Int, Int) {
        (
            entry.1.match?.rawValue ?? 0,
            entry.1.isExactAlias ? 0 : 1,
            entry.1.clip.isPinned ? 0 : 1,
            entry.0
        )
    }

    /// Keeps at most ``PanelPresenter/rowsPerGroup`` of each kind of match; browsing is never capped.
    static func capping(_ rows: [PanelResult]) -> ([PanelResult], [PanelMatchField: Int]) {
        var kept: [PanelResult] = []
        var seen: [PanelMatchField: Int] = [:]
        var omitted: [PanelMatchField: Int] = [:]
        for row in rows {
            guard let field = row.match else {
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

    /// The strongest part of a clip the query appears in: alias, then category, then content.
    static func field(matching needle: String, in clip: Clip, locale: Locale) -> PanelMatchField? {
        let fields: [(PanelMatchField, String?)] = [
            (.alias, clip.alias), (.category, clip.category), (.content, clip.text),
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
