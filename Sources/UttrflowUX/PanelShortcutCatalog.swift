/// One panel keystroke and what it does, as shown in the shortcut guide.
package struct PanelShortcutDescription: Sendable, Equatable, Identifiable {
    /// The action shown in the shortcut guide.
    package let title: String
    /// The keys that trigger the action.
    package let chord: String
    /// A stable identity for rendering the entry.
    package var id: String { chord + title }

}

/// The panel's complete keyboard reference. Row chords come from the same cases as row actions.
package enum PanelShortcutCatalog {
    /// Every global panel command followed by the chords available on a row.
    package static let entries: [PanelShortcutDescription] =
        [
            .init(
                title: String(localized: "Move selection", comment: "Quick panel shortcut action."),
                chord: String(localized: "↑ / ↓", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Move farther", comment: "Quick panel shortcut action."),
                chord: String(
                    localized: "Page Up / Page Down / Home / End", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(
                    localized: "Paste selected clip or save", comment: "Quick panel shortcut action."),
                chord: String(localized: "Return", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Paste without formatting", comment: "Quick panel shortcut action."),
                chord: String(localized: "⌘ Return", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Undo the last deletion", comment: "Quick panel shortcut action."),
                chord: String(localized: "⌘ Z", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(
                    localized: "Clear search; close sheet, panel, or guide",
                    comment: "Quick panel shortcut action."),
                chord: String(localized: "Esc", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Choose a collection", comment: "Quick panel shortcut action."),
                chord: String(localized: "⌘ 1–9", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Rename collection", comment: "Quick panel shortcut action."),
                chord: String(localized: "⇧ ⌘ R", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Delete collection", comment: "Quick panel shortcut action."),
                chord: String(localized: "⇧ ⌘ Delete", comment: "Quick panel keyboard chord.")),
            .init(
                title: String(localized: "Show this guide", comment: "Quick panel shortcut action."),
                chord: String(localized: "? (empty search) / ⌘ /", comment: "Quick panel keyboard chord.")),
        ]
        + PanelRowAction.allCases.map { action in
            PanelShortcutDescription(title: action.helpTitle, chord: action.chord.label)
        }
}

extension PanelRowAction {
    var helpTitle: String {
        switch self {
        case .reveal: String(localized: "Reveal secret", comment: "Quick panel row action.")
        case .copy: String(localized: "Copy clip", comment: "Quick panel row action.")
        case .pin: String(localized: "Pin or unpin clip", comment: "Quick panel row action.")
        case .alias: String(localized: "Name or rename clip", comment: "Quick panel row action.")
        case .move: String(localized: "Move clip to collection", comment: "Quick panel row action.")
        case .edit: String(localized: "Edit clip text", comment: "Quick panel row action.")
        case .format: String(localized: "Format clip", comment: "Quick panel row action.")
        case .reindent: String(localized: "Reindent code clip", comment: "Quick panel row action.")
        case .makeNote: String(localized: "Make clip a note", comment: "Quick panel row action.")
        case .secrecy: String(localized: "Mark or unmark as secret", comment: "Quick panel row action.")
        case .delete: String(localized: "Delete clip", comment: "Quick panel row action.")
        }
    }
}
