// How a quick panel row is drawn, keyed and spoken.

import Foundation
import UttrflowClipboard
import UttrflowUX

/// How a row is drawn given the presenter's selection and the pointer, which only the view knows.
struct QuickPanelRowAppearance: Sendable, Equatable {
    let isSelected: Bool
    /// Draws the fill; selection and hover both fill, which is why the ring exists as well.
    let isFilled: Bool
    /// Dims a hovered row while the ring sits elsewhere, so the ring stays the answer to Return.
    let isSubdued: Bool
    /// Whether the row shows its buttons instead of its timestamp; at 420 points there is no room for both.
    let showsActions: Bool

    /// Selection beats hover on the same row; `hasSelection` says whether there is a ring to dim against.
    static func of(
        _ row: PanelRow, isSelected: Bool, hovered: UUID?, hasSelection: Bool
    ) -> QuickPanelRowAppearance {
        let isHovered = row.id == hovered
        return QuickPanelRowAppearance(
            isSelected: isSelected,
            isFilled: isSelected || isHovered,
            isSubdued: isHovered && !isSelected && hasSelection,
            showsActions: isSelected || isHovered)
    }

    static func of(_ row: PanelRow, hovered: UUID?, hasSelection: Bool) -> QuickPanelRowAppearance {
        of(row, isSelected: row.isSelected, hovered: hovered, hasSelection: hasSelection)
    }
}

/// One run of the list with its heading, so the list has one shape whether browsing or searching.
struct QuickPanelSection: Identifiable {
    let id: String
    let title: String?
    let rows: [PanelRow]
    let moreLine: String?

    /// A row's identity in the list: the run it is in as well as the clip it is.
    func key(for row: PanelRow) -> String { "\(id)-\(row.id)" }
}

/// What VoiceOver reads for a row; a masked row reads as hidden and its text is never in the string.
enum QuickPanelSpeech {
    static func label(for row: PanelRow) -> String {
        let body = row.isMasked ? "hidden" : row.summary
        let details: [String?] =
            row.isMasked
            ? []
            : [
                row.measurements,
                row.checklist,
                row.language.map { "\($0) code" },
                row.category.map { "Collection \($0)" },
            ]
        return
            ([noun(for: row.kind), row.isPinned ? "Pinned" : nil, row.alias, body]
            + details
            + [row.containsDisplayHazards ? "contains invisible or control characters" : nil, row.when])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Spoken in place of the glyph, so a row is identifiable without being seen.
    static func noun(for kind: ClipKind) -> String {
        switch kind {
        case .text: "Text"
        case .link: "Link"
        case .code: "Code"
        case .secret: "Hidden credential"
        case .colour: "Colour"
        case .filePath: "File path"
        case .image: "Image"
        }
    }

    /// Whether the kind gets a filled tile: code and credentials, the two nobody may paste by accident.
    static func hasTile(_ kind: ClipKind) -> Bool {
        kind == .code || kind == .secret
    }
}
