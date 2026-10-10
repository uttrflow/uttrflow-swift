public import CoreGraphics
public import UttrflowCore
public import UttrflowPredict

public enum SuggestionWritingDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft
}

/// The display settings that change how the suggestion surface is drawn.
public struct SuggestionAppearance: Sendable, Equatable {
    /// Increase Contrast, under which grey text on the user's own line fails to read.
    public let increasesContrast: Bool
    /// Reduce Transparency, which asks for a solid surface rather than a floating one.
    public let reducesTransparency: Bool
    public init(
        increasesContrast: Bool = false,
        reducesTransparency: Bool = false
    ) {
        self.increasesContrast = increasesContrast
        self.reducesTransparency = reducesTransparency
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

    /// What colour the ghost is drawn in, which must read against the field rather than against Uttrflow's appearance.
    public enum Ink: Sendable, Equatable {
        /// The field's own text colour, which contrasts with the field's background because the field chose it to.
        case field(TextColor)
        /// The field would not say, so the ghost sits on a backing of its own that its colour is resolved against.
        case backed
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

    /// The backing behind a ghost whose field would not say its text colour is drawn at this share of the window colour.
    public static let backingOpacity = 0.9

    /// The backing is solid when the system asks to reduce transparency.
    public static let opaqueBackingOpacity = 1.0

    /// Unselected rows and the footer must remain readable against the field in the default appearance.
    public static let standardListOpacity = 0.72

    /// Unselected rows and the footer stay readable when an accessibility display setting is enabled.
    public static let accessibleListOpacity = 0.9

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
    /// The widest the surface may draw, the room from the caret to the field's or screen's edge, past which text ends in an ellipsis.
    public let maximumWidth: CGFloat?
    /// The direction used to lay out the continuation.
    public let direction: SuggestionWritingDirection
    /// The share of the line's colour the ghost is drawn at, raised to full under a contrast setting.
    public let opacity: Double
    /// The direct opacity for unselected list rows and the footer, independent of the inline ghost.
    public let unselectedListOpacity: Double
    /// Whether the ghost is underlined, which is what tells it from typed text once it is drawn at full strength.
    public let underlinesGhost: Bool
    /// The key that takes the suggestion in this field, which the hint after the ghost must name truthfully.
    public let acceptKey: AcceptKey
    /// Whether Escape has a decision for this offer and accept key.
    private let escapeIsRouted: Bool
    /// The field's own font family, so the ghost is set in the face the line is, or nothing when it will not say.
    public let fontFamily: String?
    /// Whether to set the ghost in bold to match the field's face.
    public let isBold: Bool
    /// Whether to set the ghost in italics to match the field's face.
    public let isItalic: Bool
    /// The colour the ghost is drawn in, and whether it needs a backing to be read at all.
    public let ink: Ink
    /// The backing opacity used when the field does not report its text colour.
    public let backingOpacity: Double
    /// A system-condition message exposed to VoiceOver when suggestions are temporarily gated.
    public let statusMessage: String?

    public init(
        _ suggestion: Suggestion,
        typed: String = "",
        selection: SuggestionSelection = .untouched,
        fieldPointSize: CGFloat? = nil,
        appearance: SuggestionAppearance = .standard,
        acceptKey: AcceptKey = .tab,
        fontFamily: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        fieldTextColor: TextColor? = nil,
        statusMessage: String? = nil,
        maximumWidth: CGFloat? = nil,
        direction: SuggestionWritingDirection = .leftToRight
    ) {
        self.acceptKey = acceptKey
        escapeIsRouted =
            KeyRouting.decision(
                for: KeyStroke(.escape), showing: suggestion, selection: selection,
                acceptKey: acceptKey) != .passThrough
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.isItalic = isItalic
        ink = fieldTextColor.map(Ink.field) ?? .backed
        backingOpacity = appearance.reducesTransparency ? Self.opaqueBackingOpacity : Self.backingOpacity
        self.statusMessage = statusMessage
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
        // A field that reports neither size nor face is most often a terminal, where a monospaced default lines up.
        prefersMonospaced = fieldPointSize == nil && fontFamily == nil
        self.maximumWidth = maximumWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.direction = direction
        // Faint grey is the intent; a contrast setting keeps the text but drops the transparency.
        opacity = appearance.demandsOpaqueGhost ? Self.opaqueGhostOpacity : Self.ghostOpacity
        unselectedListOpacity =
            appearance.demandsOpaqueGhost
            ? Self.accessibleListOpacity
            : Self.standardListOpacity
        underlinesGhost = appearance.demandsOpaqueGhost
    }

    /// The row Tab takes, whose continuation is the ghost on the caret's own line.
    public var inline: Row? { rows.first(where: \.isSelected) }

    /// The rows listed under the caret's line, which is every candidate once the list is open and none before.
    public var list: [Row] { isExpanded ? rows : [] }

    /// The keys that work the open list, drawn under it in the dimmed style.
    public var footer: String {
        "\(acceptKey.glyph) take   ⌥↓ next" + (escapeIsRouted ? "   ⎋ dismiss" : "")
    }

    /// The selected candidate keeps full strength; other rows use the contrast-safe list opacity.
    public func listOpacity(for row: Row) -> Double {
        row.isSelected ? 1 : unselectedListOpacity
    }

    /// What VoiceOver hears automatically when the offer changes, without exposing unselected candidates.
    var announcementLabel: String {
        guard let leader = inline else {
            return style == .dot ? (escapeIsRouted ? Self.dotLabel : "AI suggestion hidden.") : ""
        }
        let take = "\(acceptKey.spokenName) to accept\(Self.cost(of: leader))."
        return "AI suggestion: \(leader.candidate). \(take)"
    }

    /// What VoiceOver can read while navigating the surface, including alternatives in an open list.
    public var accessibilityLabel: String {
        let alternatives = rows.filter { !$0.isSelected }.map(\.candidate)
        var parts = [announcementLabel]
        if !alternatives.isEmpty { parts.append("Alternatives: \(alternatives.joined(separator: ", ")).") }
        if let statusMessage { parts.append(statusMessage) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Includes a temporary system-condition explanation when VoiceOver is on an otherwise empty surface.
    public var surfaceAccessibilityLabel: String {
        if let statusMessage, accessibilityLabel.isEmpty { return statusMessage }
        return accessibilityLabel
    }

    /// What VoiceOver is told the dot left by Escape is, and what a second Escape does.
    public static let dotLabel = "AI suggestion hidden. Escape again to turn suggestions off in this field."

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
        let usable: [(index: Int, candidate: String, edit: Acceptance.Edit)] = offered.enumerated().compactMap
        {
            guard !$1.allSatisfy(\.isWhitespace),
                let edit = Acceptance.edit(accepting: $1, after: typed)
            else { return nil }
            return ($0, $1, edit)
        }
        guard !usable.isEmpty else { return [] }
        // Arrow-key selection counts original candidates, including ones this field cannot accept.
        let chosen = usable.firstIndex { $0.index >= selected } ?? usable.count - 1
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
