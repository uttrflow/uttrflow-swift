// The chords a row's actions answer to, in one table so the handler, the ⋯ menu and the docs agree.

/// A ⌘ chord, labelled by its Latin key and matched by its physical key code.
public struct PanelChord: Sendable, Equatable, Hashable {
    /// The character shown in shortcut labels; AppKit reports Backspace as `\u{7F}`.
    public let character: Character
    /// Whether ⇧ is held as well as ⌘, which keeps a chord off the search field's own editing keys.
    public let isShifted: Bool

    /// The physical US key position used when a layout does not produce a Latin letter.
    public var keyCode: UInt16? { Self.keyCodes[character] }

    /// Whether the layout's produced letter matches, falling back to the US key position only without one.
    public func matches(characters: String, keyCode: UInt16, shifted: Bool) -> Bool {
        guard shifted == isShifted else { return false }
        if let produced = characters.first(where: { $0.isASCII && $0.isLetter }) {
            return PanelChord(produced, shifted: shifted) == self
        }
        return self.keyCode == keyCode
    }

    public init(_ character: Character, shifted: Bool = false) {
        self.character = character.lowercased().first ?? character
        self.isShifted = shifted
    }

    private static let keyCodes: [Character: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6, "\u{7F}": 51,
    ]

    /// The chord as the user reads it, in the menu and in `Docs/shortcuts.md`.
    public var label: String {
        "⌘" + (isShifted ? "⇧" : "") + (character == "\u{7F}" ? "⌫" : character.uppercased())
    }
}

/// One thing a row offers, named without a clip, which is what a chord can be bound to.
public enum PanelRowAction: Sendable, Equatable, CaseIterable {
    case reveal
    case copy
    /// One action for both, because a row offers whichever of the two applies to it.
    case pin
    case alias
    case move
    case edit
    case format
    case reindent
    case makeNote
    /// One action for both, because a row offers whichever answer about secrecy it does not already have.
    case secrecy
    case delete
}

extension PanelRowAction {
    /// The chord that performs it: the one place any of them is written down.
    public var chord: PanelChord {
        switch self {
        case .reveal: PanelChord("r")
        // ⌘C is the search field's own copy, so the row's takes ⇧ as well.
        case .copy: PanelChord("c", shifted: true)
        case .pin: PanelChord("p")
        case .alias: PanelChord("n")
        case .move: PanelChord("m")
        case .edit: PanelChord("e")
        case .format: PanelChord("f", shifted: true)
        case .reindent: PanelChord("i", shifted: true)
        case .makeNote: PanelChord("t", shifted: true)
        case .secrecy: PanelChord("s", shifted: true)
        // ⌫ and ⌘⌫ edit the query, and a chord that acted only on an empty field would be a trap.
        case .delete: PanelChord("\u{7F}", shifted: true)
        }
    }
}

extension PanelPresentation {
    /// What a ⌘ chord does to the highlighted row, read off that row's own actions so the two agree.
    public func intent(for chord: PanelChord) -> PanelIntent? {
        selectedRow?.actions.first { $0.shortcut == chord }?.intent
    }
}
