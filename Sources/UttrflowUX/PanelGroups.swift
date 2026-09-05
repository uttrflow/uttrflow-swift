import Foundation
import UttrflowClipboard

/// A run of rows that matched the same way.
///
/// H1 — a list that shows an alias hit, a collection hit and a content hit together
/// without saying which is which makes the user open rows to find out. The heading is the
/// answer, given once for the run rather than repeated on every row.
public struct PanelResultGroup: Sendable, Equatable, Identifiable {
    public let field: PanelMatchField
    public let title: String
    public let rows: [PanelRow]
    /// H6 — how many matches this group has that are not drawn.
    ///
    /// Said out loud rather than left off the end. A capped list that does not admit it
    /// is a list the user reads as complete, and the clip they were looking for is
    /// missing with no sign that anything was withheld.
    public let more: Int

    public var id: String { title }

    public init(field: PanelMatchField, title: String, rows: [PanelRow], more: Int) {
        self.field = field
        self.title = title
        self.rows = rows
        self.more = more
    }
}

extension PanelPresenter {
    /// H6 — how many rows of one kind of match are drawn before the rest become a count.
    ///
    /// Six is about a screen of one group without pushing the next heading out of sight.
    /// The cap exists so that a search matching four hundred clips by content cannot bury
    /// the one that matched by the name the user gave it.
    public static let rowsPerGroup = 6

    /// The rows, cut into the runs the list is drawn in.
    ///
    /// Empty when nothing has been typed: with no query every row is here for no reason
    /// at all, so a heading would be a label with nothing to distinguish it from the rest
    /// of the list.
    ///
    /// Relies on ``PanelSnapshot/rank(_:)`` having already put matches of the same kind
    /// together. Grouping a differently-ordered list would put the headings out of step
    /// with the order the arrow keys walk.
    /// The capping itself is not done here. ``PanelResults`` has already dropped the
    /// surplus, because what is drawn and what Return can reach have to be the same list;
    /// this only reads back how many it dropped.
    static func groups(
        for rows: [PanelRow], omitted: [PanelMatchField: Int], isSearching: Bool
    ) -> [PanelResultGroup] {
        guard isSearching else { return [] }

        var groups: [PanelResultGroup] = []
        for row in rows {
            guard let field = row.matched else { continue }
            if let last = groups.last, last.field == field {
                groups[groups.count - 1] = PanelResultGroup(
                    field: field, title: last.title, rows: last.rows + [row], more: last.more)
            } else {
                groups.append(
                    PanelResultGroup(
                        field: field, title: heading(for: field), rows: [row],
                        more: omitted[field, default: 0]))
            }
        }
        return groups
    }

    /// Named for what the user did, not for the field's name in the code. "Aliases" is a
    /// word from the implementation; "Names you gave" is what the row actually is.
    static func heading(for field: PanelMatchField) -> String {
        switch field {
        case .alias: "Names you gave"
        case .category: "Collections"
        case .content: "Contents"
        }
    }
}

extension PanelPresenter {
    /// H7 — what the current list is scoped to, said out loud.
    ///
    /// Typing leaves the open collection behind and searches everywhere, which is right
    /// but silent: the chips move to All and a user watching the list rather than the
    /// chips sees clips appear from collections they thought they had narrowed away. This
    /// is the sentence that stops them wondering.
    ///
    /// Nothing is said while browsing. The active chip already answers the question, and a
    /// line repeating it would be a line of a 420-point panel spent on something visible.
    static func scope(for snapshot: PanelSnapshot) -> String? {
        guard snapshot.isSearching, let leaving = PanelSnapshot.name(snapshot.category) else {
            return nil
        }
        // Not "esc to go back": esc closes the panel. What returns the user to the
        // collection is emptying the field, and telling them the wrong key would be a
        // worse failure than saying nothing at all.
        return "Searching everywhere · clear the search to return to \(leaving)"
    }

    /// H3 — the one thing worth doing about a search that found nothing.
    ///
    /// Offered only when something was actually typed. The other empty states — a
    /// clipboard nobody has copied into, a collection with nothing filed in it, a filter
    /// matching no kind — have no action that would help: there is nothing to keep, and a
    /// button that creates a clip out of an empty search field would be a button that
    /// creates nothing.
    ///
    /// Worth having because a fruitless search is often somebody discovering they never
    /// copied the thing they meant to, and the text they typed is usually the thing.
    static func emptyAction(for snapshot: PanelSnapshot) -> PanelAction? {
        let query = snapshot.needle
        guard !query.isEmpty else { return nil }
        return PanelAction(
            title: "Keep “\(query)” as a clip", symbolName: "plus.circle",
            intent: .keepQuery(query))
    }

    /// H5 — the part of a long clip the search actually found.
    ///
    /// A row shows its first line, which is the right answer until the match is on line
    /// forty. Then the row is a clip the user cannot see the reason for: it is in the list
    /// because of a word that is nowhere on screen, and the only way to check is to open
    /// it — which is the thing the summary exists to avoid.
    ///
    /// Only for content matches. An alias or collection hit is already named on the row,
    /// so re-cutting the text around it would replace something useful with something the
    /// user can already see.
    static func excerpt(of text: String, around needle: String, locale: Locale) -> String? {
        guard !needle.isEmpty,
            let found = text.range(
                of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
                locale: locale)
        else { return nil }

        // Nothing to do when the match is already on the line the row would show anyway.
        let firstLine = text.prefix { !$0.isNewline }
        if found.upperBound <= firstLine.endIndex { return nil }

        let lead = 24
        let start =
            text.index(found.lowerBound, offsetBy: -lead, limitedBy: text.startIndex)
            ?? text.startIndex
        let end =
            text.index(found.upperBound, offsetBy: 48, limitedBy: text.endIndex) ?? text.endIndex

        // Flattened, because a row is one line high and a newline inside it would either
        // be dropped silently or push the row out of alignment with its neighbours.
        let window =
            text[start..<end]
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return (start > text.startIndex ? "…" : "") + window + (end < text.endIndex ? "…" : "")
    }
}
