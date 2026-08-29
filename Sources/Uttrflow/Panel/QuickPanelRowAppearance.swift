import Foundation
import UttrflowClipboard
import UttrflowUX

/// How a row is drawn, given the selection the presenter chose and where the pointer is.
///
/// The pointer is the one thing about the panel the presentation cannot know: it is not
/// a keystroke, it changes nothing about which clip Return means, and a model that
/// tracked it would redraw the world every time the mouse crossed a row. So hover is
/// held by the view — and the rule for reconciling it with the selection is here, where
/// it can be proved, rather than inside the layout where it cannot.
struct QuickPanelRowAppearance: Sendable, Equatable {
    /// Draws the ring. Exactly the row ``PanelRow/isSelected`` names, and the row Return
    /// acts on.
    let isSelected: Bool
    /// Draws the fill. Selection and hover both fill, which is the whole reason the ring
    /// has to exist as well.
    let isFilled: Bool
    /// Dims a hovered row while the ring sits on a different one, so that the ring stays
    /// the answer to what Return will do.
    let isSubdued: Bool
    /// Whether the row shows its buttons instead of its timestamp. At 420 points there
    /// is no room for both, and the time matters least at the moment somebody is
    /// reaching for a button.
    let showsActions: Bool

    /// Selection beats hover on the same row, so pointing at the ringed row fills it
    /// once rather than announcing itself as something new.
    ///
    /// `hasSelection` rather than a second identifier: the presenter guarantees at most
    /// one selected row, and all this rule needs to know is whether there is a ring
    /// somewhere for the hovered row to be dimmed against.
    static func of(_ row: PanelRow, hovered: UUID?, hasSelection: Bool) -> QuickPanelRowAppearance {
        let isHovered = row.id == hovered
        return QuickPanelRowAppearance(
            isSelected: row.isSelected,
            isFilled: row.isSelected || isHovered,
            isSubdued: isHovered && !row.isSelected && hasSelection,
            showsActions: row.isSelected || isHovered)
    }
}

/// One run of the list, with the heading it is drawn under.
///
/// A value rather than two branches of an `if`, so the list has one shape whether it is
/// browsing or searching — see the comment at its only use.
struct QuickPanelSection: Identifiable {
    let id: String
    let title: String?
    let rows: [PanelRow]
    let more: Int

    /// A row's identity in the list, which is the run it is in as well as the clip it
    /// is. See the comment where it is used.
    func key(for row: PanelRow) -> String { "\(id)-\(row.id)" }
}

/// What VoiceOver reads for a row.
///
/// Composed here rather than in the layout because it is a decision about disclosure,
/// not about drawing: a masked row must read as masked, and its text must not be in the
/// string at all. `summary` is already bullets by the time the panel sees it, but saying
/// so explicitly means a future presenter that stopped masking could not quietly turn
/// this into a screen reader announcing a production connection string out loud.
enum QuickPanelSpeech {
    static func label(for row: PanelRow) -> String {
        let body = row.isMasked ? "hidden" : row.summary
        return [noun(for: row.kind), row.alias, body, row.when]
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

    /// The mark at the head of a row, which is about what you are about to paste rather
    /// than exactly what it is — the text beside it already says that. Code and
    /// credentials are the two nobody may paste by accident, so they are the two that
    /// get a filled tile the eye finds without reading.
    static func hasTile(_ kind: ClipKind) -> Bool {
        kind == .code || kind == .secret
    }
}
