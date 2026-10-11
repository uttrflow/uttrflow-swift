// Which of the panel's keys belong to an input method while it is still composing a word.

/// The keys an input method owns mid-composition, which the panel must not take from it. See `Docs/panel.md`.
public enum PanelComposition {
    /// Whether the panel may act on a key, which it may not while a composition is open.
    public static func panelMayTake(_ key: PanelKey, whileComposing isComposing: Bool) -> Bool {
        guard isComposing else { return true }
        switch key {
        // Return commits the candidate, the arrows walk the candidate list, and Escape cancels the word.
        case .return, .returnPlain, .up, .down, .escape, .jump: return false
        // A collection number is a command chord; everything else is a chip or committed field text.
        case .category, .showShortcuts, .clearSearch: return false
        default: return true
        }
    }

    /// Whether the panel may act on a resolved key or command chord while the field editor composes text.
    public static func panelMayTake(_ decision: PanelKeyDecision, whileComposing isComposing: Bool) -> Bool {
        guard isComposing else { return true }
        switch decision {
        case .key(let key), .keyAfterClosingMenu(let key):
            return panelMayTake(key, whileComposing: true)
        case .intent:
            return false
        case .closeMenu, .ignore:
            return true
        }
    }
}
