// The panel's search results in groups, the scope sentence, the keep-query action, and excerpts.
import Foundation
import UttrflowClipboard

/// A run of rows that matched the same way, with the heading given once for the run.
public struct PanelResultGroup: Sendable, Equatable, Identifiable {
    /// Which part of the clip matched.
    public let field: PanelMatchField
    /// The heading over the run.
    public let title: String
    /// The rows in the run.
    public let rows: [PanelRow]
    /// How many matches this group has that are not drawn, said so a capped list is not read as complete.
    public let more: Int

    /// The title, which is unique in the list.
    public var id: String { title }

    /// Builds a group.
    public init(field: PanelMatchField, title: String, rows: [PanelRow], more: Int) {
        self.field = field
        self.title = title
        self.rows = rows
        self.more = more
    }
}

extension PanelPresenter {
    /// How many rows of one kind of match are drawn before the rest become a count; six is about a screen.
    public static let rowsPerGroup = 6

    /// The rows cut into runs, relying on ``PanelSnapshot/rank(_:)`` for the order; empty while browsing.
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

    /// Named for what the user did, not the field's name in the code: "Names you gave", not "Aliases".
    static func heading(for field: PanelMatchField) -> String {
        switch field {
        case .alias: "Names you gave"
        case .category: "Collections"
        case .content: "Contents"
        }
    }
}

extension PanelPresenter {
    /// What the list is scoped to, said while a search leaves a collection behind; silent while browsing.
    static func scope(for snapshot: PanelSnapshot) -> String? {
        guard snapshot.isSearching, let leaving = PanelSnapshot.name(snapshot.category) else {
            return nil
        }
        // Not "esc to go back": esc closes the panel, and emptying the field is what returns the user.
        return "Searching everywhere · clear the search to return to \(leaving)"
    }

    /// The one thing worth doing about a search that found nothing: keep what was typed as a clip.
    static func emptyAction(for snapshot: PanelSnapshot) -> PanelAction? {
        let query = snapshot.needle
        guard !query.isEmpty else { return nil }
        return PanelAction(
            title: "Keep “\(query)” as a clip", symbolName: "plus.circle",
            intent: .keepQuery(query))
    }

    /// The part of a long clip the search found, for content matches only; `nil` if it is on line one.
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

        // Flattened, because a row is one line high.
        let window =
            text[start..<end]
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return (start > text.startIndex ? "…" : "") + window + (end < text.endIndex ? "…" : "")
    }
}
