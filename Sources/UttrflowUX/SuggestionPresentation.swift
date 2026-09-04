public import CoreGraphics
public import UttrflowPredict

/// What the user's accessibility settings ask the suggestion surface to do differently.
public struct SuggestionAppearance: Sendable, Equatable {
    /// Increase Contrast, under which grey text on the user's own line fails to read.
    public let increasesContrast: Bool
    /// Reduce Transparency, which asks for a solid surface rather than a floating one.
    public let reducesTransparency: Bool
    /// Reduce Motion, under which nothing on the surface moves.
    public let reducesMotion: Bool

    public init(
        increasesContrast: Bool = false,
        reducesTransparency: Bool = false,
        reducesMotion: Bool = false
    ) {
        self.increasesContrast = increasesContrast
        self.reducesTransparency = reducesTransparency
        self.reducesMotion = reducesMotion
    }

    /// Nothing turned on, which is what most Macs report.
    public static let standard = Self()

    /// Whether the ghost must drop its transparency to stay legible, keeping the text but not the grey.
    var demandsOpaqueGhost: Bool { increasesContrast || reducesTransparency }
}

/// What the suggestion surface draws, decided without drawing it.
public struct SuggestionPresentation: Sendable, Equatable {
    /// How the offered text is told apart from the text the user typed.
    public enum Style: String, Sendable, Equatable {
        /// Nothing on screen at all.
        case hidden
        /// Grey text on the user's own line, with no chip and no border.
        case ghost
        /// One dot, which is all that is left after the user presses escape.
        case dot
    }

    /// One candidate on offer, and whether it is the one Tab takes.
    public struct Row: Sendable, Equatable {
        /// The whole line this row leaves behind, which is what the list and VoiceOver show.
        public let candidate: String
        /// What Tab does to what is typed, which is the same value acceptance applies.
        public let edit: Acceptance.Edit
        /// Whether Tab takes this row, which is also what puts it on the caret's line.
        public let isSelected: Bool

        /// The text drawn after the caret, which is only what this row adds to the line.
        public var ghost: String { edit.inserted }

        /// The typed characters Tab destroys, drawn struck through and empty for a plain append.
        public var consumed: String { edit.replaced }

        /// Whether taking this row costs the user characters they typed themselves.
        public var isReplacement: Bool { edit.isReplacement }
    }

    /// Grey text is drawn at this share of the line's own colour.
    public static let ghostOpacity = 0.45

    /// Ghost text drawn at full strength, for a display setting under which faint grey fails to read.
    public static let opaqueGhostOpacity = 1.0

    /// An unselected row of the list, and the footer, are drawn at this share of the ghost's own strength.
    public static let dimmedShare = 0.55

    /// What opens each row of the list, so it reads as a branch off the caret's line.
    public static let listPrefix = "↳"

    /// The dot's diameter, in points.
    public static let dotDiameter: CGFloat = 7

    /// The type size used where the field will not say what its own is.
    public static let defaultPointSize: CGFloat = 13

    /// The type sizes worth following, outside which a field is reporting nonsense.
    public static let pointSizeRange: ClosedRange<CGFloat> = 9...48

    public let style: Style
    /// Every candidate on offer, the leader first, with the one Tab takes marked selected.
    public let rows: [Row]
    /// Whether the list is open under the caret's line, which only a Down press does. See `Docs/predict.md`.
    public let isExpanded: Bool
    /// The field's own type size, so the surface reads as part of the line it sits on.
    public let pointSize: CGFloat
    /// Whether to set the ghost in a monospaced face, chosen when the field would not say what its own is.
    public let prefersMonospaced: Bool
    /// Whether a change of state is allowed to animate.
    public let animates: Bool
    /// The share of the line's colour the ghost is drawn at, raised to full under a contrast setting.
    public let opacity: Double
    /// The key that takes the suggestion in this field, which the hint after the ghost must name truthfully.
    public let acceptKey: AcceptKey

    public init(
        _ suggestion: Suggestion,
        typed: String = "",
        selection: SuggestionSelection = .untouched,
        fieldPointSize: CGFloat? = nil,
        appearance: SuggestionAppearance = .standard,
        acceptKey: AcceptKey = .tab
    ) {
        self.acceptKey = acceptKey
        let offered = Self.rows(of: suggestion, after: typed, selected: selection.index)
        style =
            switch suggestion {
            case .minimised: .dot
            case .silent, .certain, .choice:
                offered.isEmpty ? .hidden : .ghost
            }
        rows = offered
        // A list is only ever opened by the user; until Down is pressed the choice is one ghost line.
        isExpanded = offered.count > 1 && selection.hasMoved
        pointSize = Self.pointSize(fieldPointSize)
        // With no reported size, the field's own font is unknown too, so a monospaced default reads best at a caret.
        prefersMonospaced = fieldPointSize == nil
        animates = !appearance.reducesMotion
        // Faint grey is the intent; a contrast setting keeps the text but drops the transparency.
        opacity = appearance.demandsOpaqueGhost ? Self.opaqueGhostOpacity : Self.ghostOpacity
    }

    /// The row Tab takes, whose continuation is the ghost on the caret's own line.
    public var inline: Row? { rows.first(where: \.isSelected) }

    /// The rows listed under the caret's line, which is every candidate once the list is open and none before.
    public var list: [Row] { isExpanded ? rows : [] }

    /// The accept key as a glyph, which opens the list's footer so a terminal reads →, not ⇥; the ghost line carries none.
    public var acceptGlyph: String { acceptKey.glyph }

    /// The keys that work the open list, drawn under it in the dimmed style.
    public var footer: String { "\(acceptKey.glyph) take   ↓ next   ⎋ dismiss" }

    /// What VoiceOver is told the surface is offering, and what taking it costs.
    public var accessibilityLabel: String {
        guard let leader = inline else { return "" }
        let alternatives = rows.filter { !$0.isSelected }.map(\.candidate)
        let take = "\(acceptKey.spokenName) to accept\(Self.cost(of: leader))."
        guard !alternatives.isEmpty else { return "Suggestion: \(leader.candidate). \(take)" }
        return "Suggestion: \(leader.candidate). \(take) Alternatives: "
            + alternatives.joined(separator: ", ") + "."
    }

    /// Says how much of the user's own typing a row takes back, and nothing when it only adds.
    private static func cost(of row: Row) -> String {
        let count = row.edit.replacedCount
        guard count > 0 else { return "" }
        return ", replacing \(count) character\(count == 1 ? "" : "s")"
    }

    /// Every usable candidate in offered order, with the highlighted one selected.
    private static func rows(of suggestion: Suggestion, after typed: String, selected: Int) -> [Row] {
        let offered: [String] =
            switch suggestion {
            case .silent, .minimised: []
            case .certain(let text): [text]
            case .choice(let leader, let others): [leader] + others
            }
        // The edit is the one acceptance applies, so drawing and doing cannot disagree.
        let usable: [(candidate: String, edit: Acceptance.Edit)] = offered.compactMap {
            guard !$0.allSatisfy(\.isWhitespace),
                let edit = Acceptance.edit(accepting: $0, after: typed)
            else { return nil }
            return ($0, edit)
        }
        guard !usable.isEmpty else { return [] }
        // The highlight can be moved with the arrow keys, so it follows the chosen row, not always the leader.
        let chosen = min(max(selected, 0), usable.count - 1)
        return usable.enumerated().map {
            Row(candidate: $1.candidate, edit: $1.edit, isSelected: $0 == chosen)
        }
    }

    /// Follows the field's own type, and refuses a size no text is ever set in.
    private static func pointSize(_ reported: CGFloat?) -> CGFloat {
        guard let reported, reported.isFinite else { return defaultPointSize }
        return min(max(reported, pointSizeRange.lowerBound), pointSizeRange.upperBound)
    }
}

extension AcceptKey {
    /// The key as the keyboard prints it, which is what sits after the ghost and opens the footer.
    public var glyph: String {
        switch self {
        case .tab: "⇥"
        case .rightArrow: "→"
        case .optionTab: "⌥⇥"
        }
    }

    /// The key as VoiceOver says it.
    public var spokenName: String {
        switch self {
        case .tab: "Tab"
        case .rightArrow: "Right Arrow"
        case .optionTab: "Option-Tab"
        }
    }
}
