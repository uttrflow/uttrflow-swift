/// How far a dismissal goes, which is one rung of the escape ladder.
public enum Dismissal: Sendable, Equatable, CaseIterable {
    /// ⎋ — the suggestion goes and the dot stays.
    case minimise
    /// ⎋⎋ — this field offers nothing more until the user leaves it.
    case silenceField
    /// ⌥⎋ — suggestions stop everywhere until they are turned back on.
    case turnOff
}

/// Where the highlight sits in what is on offer, and whether the user put it there.
public struct SuggestionSelection: Sendable, Equatable {
    /// Which of the offered texts is highlighted, counting the leader as zero.
    public let index: Int
    /// Whether Down has been pressed at least once, which is the only thing that makes ⏎ ours.
    public let hasMoved: Bool

    /// Nothing has been navigated, so the leader is highlighted and ⏎ belongs to the app.
    public static let untouched = SuggestionSelection()

    public init(index: Int = 0, hasMoved: Bool = false) {
        self.index = index
        self.hasMoved = hasMoved
    }
}

/// What the event tap must do with one keystroke.
public enum KeyDecision: Sendable, Equatable {
    /// Swallow it and insert this text.
    case accept(String)
    /// Swallow it and move the highlight here.
    case moveSelection(SuggestionSelection)
    /// Swallow it and go this far quiet.
    case dismiss(Dismissal)
    /// It was never ours, so the application gets it untouched.
    case passThrough
}

/// Decides what a keystroke means while a suggestion is on screen. See `Docs/predict-accept.md`.
public enum KeyRouting {
    /// What to do with this keystroke, given what is drawn and where the highlight sits.
    public static func decision(
        for stroke: KeyStroke,
        showing suggestion: Suggestion,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab
    ) -> KeyDecision {
        switch suggestion {
        case .silent:
            // Nothing is drawn, so nothing is ours — including ⎋, which closes dialogs.
            return .passThrough
        case .minimised:
            if stroke == Self.turnOffStroke { return .dismiss(.turnOff) }
            return stroke == KeyStroke(.escape) ? .dismiss(.silenceField) : .passThrough
        case .certain(let text):
            return decision(for: stroke, over: [text], selection: selection, acceptKey: acceptKey)
        case .choice(let leader, let others):
            return decision(
                for: stroke, over: [leader] + others, selection: selection, acceptKey: acceptKey)
        }
    }

    /// Which keystrokes the tap must swallow, derived from the decision so the two cannot disagree.
    public static func arming(
        showing suggestion: Suggestion,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab
    ) -> ArmedKeys {
        ArmedKeys.slots.reduce(into: ArmedKeys()) { armed, entry in
            let decided = decision(
                for: entry.stroke, showing: suggestion, selection: selection, acceptKey: acceptKey)
            if decided != .passThrough { armed.insert(entry.slot) }
        }
    }

    /// ⌥⎋, which turns the whole feature off from wherever it is showing.
    private static let turnOffStroke = KeyStroke(.escape, modifiers: .option)

    /// The same decision once the offered texts are in hand, leader first.
    private static func decision(
        for stroke: KeyStroke, over offered: [String], selection: SuggestionSelection,
        acceptKey: AcceptKey
    ) -> KeyDecision {
        if stroke == turnOffStroke { return .dismiss(.turnOff) }
        let index = min(max(selection.index, 0), offered.count - 1)
        if stroke == acceptKey.stroke { return .accept(offered[index]) }

        // A single suggestion is not a list, so the keys that walk one are not ours.
        let navigable = offered.count > 1
        guard stroke.modifiers.isEmpty else { return .passThrough }
        switch stroke.key {
        case .escape:
            return .dismiss(.minimise)
        case .downArrow where navigable:
            return .moveSelection(
                SuggestionSelection(index: (index + 1) % offered.count, hasMoved: true))
        case .upArrow where navigable && selection.hasMoved:
            return .moveSelection(
                SuggestionSelection(
                    index: (index + offered.count - 1) % offered.count, hasMoved: true))
        // ⏎ runs the command and sends the message, so it is ours only while a list is being walked.
        case .return where navigable && selection.hasMoved:
            return .accept(offered[index])
        default:
            return .passThrough
        }
    }
}
