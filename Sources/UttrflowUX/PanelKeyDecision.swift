/// What one panel key asks the view to do, without depending on SwiftUI.
public enum PanelKeyDecision: Sendable, Equatable {
    case key(PanelKey)
    case intent(PanelIntent)
    case closeMenu
    case keyAfterClosingMenu(PanelKey)
    case ignore
}

/// Decides the panel's command chords and whether a relayed key closes its row menu.
public enum PanelKeyHandling {
    /// Resolves a command chord or Escape using the selected row's available actions.
    public static func decision(
        characters: String,
        commandHeld: Bool,
        shiftHeld: Bool,
        isReturn: Bool,
        isEscape: Bool,
        rowMenuOpen: Bool,
        presentation: PanelPresentation
    ) -> PanelKeyDecision {
        if isEscape {
            return rowMenuOpen ? .closeMenu : .key(.escape)
        }
        if !commandHeld {
            return isReturn ? keyDecision(.return, rowMenuOpen: rowMenuOpen) : .ignore
        }
        if characters == "z" { return .intent(.undoDelete) }
        if isReturn { return keyDecision(.returnPlain, rowMenuOpen: rowMenuOpen) }
        if let character = characters.lowercased().first {
            let chord = PanelChord(character, shifted: shiftHeld)
            if let intent = presentation.intent(for: chord) { return .intent(intent) }
        }
        if let digit = Int(characters), (1...9).contains(digit) {
            return keyDecision(.category(number: digit), rowMenuOpen: rowMenuOpen)
        }
        return .ignore
    }

    /// Resolves a key already recognized by a SwiftUI key handler.
    public static func relayDecision(for key: PanelKey, rowMenuOpen: Bool) -> PanelKeyDecision {
        if key == .escape, rowMenuOpen { return .closeMenu }
        return keyDecision(key, rowMenuOpen: rowMenuOpen)
    }

    private static func keyDecision(_ key: PanelKey, rowMenuOpen: Bool) -> PanelKeyDecision {
        rowMenuOpen ? .keyAfterClosingMenu(key) : .key(key)
    }
}
