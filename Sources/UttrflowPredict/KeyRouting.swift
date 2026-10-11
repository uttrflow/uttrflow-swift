public import UttrflowCore

/// How far a dismissal goes, which is one rung of the escape ladder.
public enum Dismissal: Sendable, Equatable, CaseIterable {
    /// ⎋ — the suggestion goes and the dot stays.
    case minimise
    /// ⌥⎋ — suggestions stop everywhere until they are turned back on.
    case turnOff
}

/// Where the highlight sits in what is on offer, and whether the user put it there.
public struct SuggestionSelection: Sendable, Equatable {
    /// Which of the offered texts is highlighted, counting the leader as zero.
    public let index: Int
    /// Whether ⌥↓ has been pressed at least once, which is the only thing that makes ⏎ ours.
    public let hasMoved: Bool

    /// Nothing has been navigated, so the leader is highlighted and ⏎ belongs to the app.
    public static let untouched = SuggestionSelection()

    /// Where the highlight sits, and whether the user put it there.
    public init(index: Int = 0, hasMoved: Bool = false) {
        self.index = index
        self.hasMoved = hasMoved
    }
}

/// What the event tap must do with one keystroke.
public enum KeyDecision: Sendable, Equatable {
    /// Swallow it and insert this text.
    case accept(String)
    /// Swallow it and insert the next word of this line.
    case acceptWord(String)
    /// Swallow it and move the highlight here.
    case moveSelection(SuggestionSelection)
    /// Swallow it and go this far quiet.
    case dismiss(Dismissal)
    /// Go this far quiet, then hand the same keystroke to the application.
    case dismissAndPassThrough(Dismissal)
    /// Never ours, so the application gets it untouched.
    case passThrough
}

/// Decides what a keystroke means while a suggestion is on screen. See `Docs/predict-accept.md`.
public enum KeyRouting {
    /// What to do with this keystroke, given what is drawn and where the highlight sits.
    public static func decision(
        for stroke: KeyStroke,
        showing suggestion: Suggestion,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab,
        wordKey: WordAcceptKey? = nil
    ) -> KeyDecision {
        switch suggestion {
        case .silent:
            // Nothing is drawn, so nothing is ours — including ⎋, which closes dialogs.
            return .passThrough
        case .minimised:
            // A dot never claims a bare ⎋, so the application's own cancel is not delayed by it.
            return stroke == Self.turnOffStroke ? .dismiss(.turnOff) : .passThrough
        case .certain(let text):
            return decision(
                for: stroke, over: [text], selection: selection, acceptKey: acceptKey, wordKey: wordKey)
        case .choice(let leader, let others):
            return decision(
                for: stroke, over: [leader] + others, selection: selection, acceptKey: acceptKey,
                wordKey: wordKey)
        }
    }

    /// Which keystrokes the tap must swallow, derived from the decision so the two cannot disagree.
    public static func arming(
        showing suggestion: Suggestion,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab,
        wordKey: WordAcceptKey? = nil
    ) -> ArmedKeys {
        (ArmedKeys.slots + ArmedKeys.wordSlots).reduce(into: ArmedKeys()) { armed, entry in
            let decided = decision(
                for: entry.stroke, showing: suggestion, selection: selection, acceptKey: acceptKey,
                wordKey: wordKey)
            if decided != .passThrough { armed.insert(entry.slot) }
        }
    }

    /// ⌥⎋, which turns the whole feature off from wherever it is showing.
    private static let turnOffStroke = KeyStroke(.escape, modifiers: .option)

    /// Whether a bare ⎋ is ours; a terminal's shell reads it as Meta or vi's normal mode, so it is not.
    private static func claimsEscape(_ acceptKey: AcceptKey) -> Bool {
        acceptKey != .rightArrow
    }

    /// The same decision once the offered texts are in hand, leader first.
    private static func decision(
        for stroke: KeyStroke, over offered: [String], selection: SuggestionSelection,
        acceptKey: AcceptKey, wordKey: WordAcceptKey?
    ) -> KeyDecision {
        if stroke == turnOffStroke { return .dismiss(.turnOff) }
        let index = min(max(selection.index, 0), offered.count - 1)
        if stroke == acceptKey.stroke { return .accept(offered[index]) }
        // The word key is the user's own choice for this application, so a stroke nobody chose is never ours.
        if let wordKey, stroke == wordKey.stroke { return .acceptWord(offered[index]) }

        // A single suggestion is not a list, so the keys that walk one are not ours.
        let navigable = offered.count > 1
        // A bare arrow moves the caret or the application's own popup, so only ⌥↓ and ⌥↑ walk ours.
        if stroke.modifiers == .option, navigable {
            switch stroke.key {
            case .downArrow:
                return .moveSelection(
                    SuggestionSelection(index: (index + 1) % offered.count, hasMoved: true))
            case .upArrow where selection.hasMoved:
                return .moveSelection(
                    SuggestionSelection(
                        index: (index + offered.count - 1) % offered.count, hasMoved: true))
            default:
                return .passThrough
            }
        }
        guard stroke.modifiers.isEmpty else { return .passThrough }
        switch stroke.key {
        case .escape where claimsEscape(acceptKey):
            return .dismissAndPassThrough(.minimise)
        // ⏎ runs the command and sends the message, so it is ours only while a list is being walked.
        case .return where navigable && selection.hasMoved:
            return .accept(offered[index])
        default:
            return .passThrough
        }
    }
}
