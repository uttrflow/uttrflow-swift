public import Foundation
public import UttrflowClipboard

/// Which part of a clip the search found.
///
/// Reported rather than kept quiet, because the three mean different things to whoever
/// is reading the list: an alias hit is the clip the user *named* and came back for, a
/// category hit is one of a set they filed together, and a content hit is a clip that
/// merely happens to contain the word. A list that shows all three without saying which
/// is which makes the user open rows to find out.
///
/// The order of the cases is the order of precedence, and the one place it is written
/// down: a clip matching in two places is reported as the strongest of them.
public enum PanelMatchField: Int, Sendable, Equatable, CaseIterable {
    case alias
    case category
    case content
}

/// A clip that survived the current view, and why it is here.
public struct PanelResult: Sendable, Equatable, Identifiable {
    public let clip: Clip
    /// Absent when nothing has been typed, which is not the same as "matched nothing":
    /// with an empty search field every clip is here for no reason at all.
    public let match: PanelMatchField?
    /// Whether what was typed *is* this clip's alias, rather than merely being somewhere
    /// inside it. The one thing that can outrank a pin.
    public let isExactAlias: Bool

    public var id: Clip.ID { clip.id }

    public init(clip: Clip, match: PanelMatchField?, isExactAlias: Bool) {
        self.clip = clip
        self.match = match
        self.isExactAlias = isExactAlias
    }
}

/// The rows the panel is showing, in the order it shows them, and which one is selected.
public struct PanelResults: Sendable, Equatable {
    public let rows: [PanelResult]
    /// H6 — how many matches of each kind were left out of ``rows``.
    ///
    /// Counted here rather than in the presentation because the cap decides what Return
    /// can reach, not merely what is drawn. A row omitted from the list but still
    /// reachable by arrow key would be a selection travelling through clips nobody can
    /// see, and a paste from one of them would arrive from nowhere.
    public let omitted: [PanelMatchField: Int]
    /// Always a real row while there is one, and `nil` only when there are none.
    ///
    /// Resolved here rather than stored, which is what makes "never on nothing, never on
    /// a row the user cannot see" a property of the type instead of a rule every
    /// transition has to remember.
    public let selectedIndex: Int?

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
    /// What the panel is showing right now: filtered, searched, ordered, and with the
    /// selection landed on a row that exists.
    ///
    /// Computed on every ask rather than cached beside the state. The lists are the size
    /// of a person's recent clipboard, and a cache is a second answer to "which clip does
    /// Return mean" — which is the one question this whole module exists to have a single
    /// answer to.
    public var results: PanelResults {
        let needle = self.needle
        // A tab narrows what is *browsed*, never what is *searched*. Typing therefore
        // leaves the tab behind and looks everywhere.
        //
        // The alternative — searching inside the open tab — fails the case the search
        // field exists for. Somebody who half-remembers filing a connection string does
        // not remember which tab they filed it in; that is the thing they are searching
        // to find out. Scoped search answers "it is not in this tab", which is the one
        // answer they cannot act on, and it answers it as an empty list that looks
        // exactly like "you never copied it".
        //
        // Nothing is lost by it. The tab is not cleared, only unused while there is a
        // query, so clearing the field puts the user back where they were browsing. And
        // every row says which tab it came from, so a global result set stays legible.
        let wanted = needle.isEmpty ? Self.name(category) : nil
        // The bottom bar is a tab too, and the paragraph above is the whole argument for
        // this line: somebody searching for a clip does not remember whether they pinned
        // it, so a search inside Pinned answers "not here", which is the one answer they
        // cannot act on.
        //
        // `nil` rather than `.history`, which is what this said while History meant
        // everything. It does not any more — History is what the user copied — so leaving
        // it there would have made every search silently blind to every dictation, and
        // the tab built to stop dictations being buried would have made them unfindable.
        // The absence of a scope is now spelt as an absence.
        let browsing: PanelScope? = needle.isEmpty ? scope : nil

        // The position in the store's own list is carried through the sort so that clips
        // of equal rank keep the order they were copied in, and so the comparison below
        // is a strict total order — an unstable sort over an ambiguous one would let two
        // draws of the same unchanged panel disagree about which row is third.
        let found = clips.enumerated().compactMap { position, clip -> (Int, PanelResult)? in
            guard browsing?.admits(clip, inCollection: wanted != nil) ?? true,
                filter.admits(clip.kind)
            else { return nil }
            if let wanted, Self.name(clip.category) != wanted { return nil }
            guard !needle.isEmpty else {
                return (position, PanelResult(clip: clip, match: nil, isExactAlias: false))
            }
            // The exact test comes first, and does not merely report alongside the search:
            // somebody who types "/pgprod" for the clip aliased "pgprod" has named it
            // exactly, and a plain substring test would drop the clip they asked for.
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

    /// Where the match was found, then exact alias, then pinned, then arrival order.
    ///
    /// The match field leads so that rows matching the same way are next to each other,
    /// which is what lets the list be *drawn* in groups. That is not cosmetic: the arrow
    /// keys walk this order, so if the groups on screen were assembled from a list sorted
    /// some other way, ↓ would jump between headings in an order nobody could predict and
    /// the third press would land somewhere the eye had not been travelling towards.
    ///
    /// It costs nothing at the top. An exact alias is an alias match, so it is in the
    /// first group anyway, and the promise it exists for — type the name, press Return,
    /// get that clip — is unaffected.
    ///
    /// With nothing typed every row has no match field, the first component is constant,
    /// and this collapses to what it was: pinned first, then arrival order.
    static func rank(_ entry: (Int, PanelResult)) -> (Int, Int, Int, Int) {
        (
            entry.1.match?.rawValue ?? 0,
            entry.1.isExactAlias ? 0 : 1,
            entry.1.clip.isPinned ? 0 : 1,
            entry.0
        )
    }

    /// Keeps at most ``PanelPresenter/rowsPerGroup`` of each kind of match.
    ///
    /// So that a query matching four hundred clips by content cannot bury the one that
    /// matched by the name the user gave it. Rows with no match field — the whole list,
    /// with nothing typed — are never capped: that is browsing, and the cap is about
    /// making a *search* readable.
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

    /// Where the selection has landed.
    ///
    /// A selection naming a clip that is no longer listed falls back to the top rather
    /// than to nothing: the panel is aimed at by counting rows from the top, and a list
    /// with no row highlighted is a list where Return does nothing and the user cannot
    /// see why.
    static func index(of selection: Clip.ID?, in rows: [PanelResult]) -> Int? {
        guard !rows.isEmpty else { return nil }
        return selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
    }

    /// The strongest part of a clip the query appears in.
    ///
    /// Alias before category before content: the first two are names the user chose for
    /// this clip and for its collection, and the third is a word that merely happens to
    /// be in it. A secret's contents are searched like anything else — the row stays
    /// masked, so what is learnt is that a clip matches, never what it says.
    static func field(matching needle: String, in clip: Clip, locale: Locale) -> PanelMatchField? {
        let fields: [(PanelMatchField, String?)] = [
            (.alias, clip.alias), (.category, clip.category), (.content, clip.text),
        ]
        return fields.first { $0.1?.contains(needle, ignoringCaseAndAccentsIn: locale) == true }?.0
    }

    /// Whether what was typed is this clip's alias, slash or no slash.
    ///
    /// The convention is a leading slash — `/pgprod` — which says "type me", and the
    /// people who adopt it are exactly the people who will not bother typing the slash
    /// when they are in a hurry. Both spellings are the same name.
    static func isAlias(_ needle: String, of clip: Clip, locale: Locale) -> Bool {
        guard let alias = clip.alias else { return false }
        // The same reduction the alias field saves through, so both spell one name.
        let typed = PanelAlias.handle(needle, locale: locale)
        return !typed.isEmpty && typed == PanelAlias.handle(alias, locale: locale)
    }
}
