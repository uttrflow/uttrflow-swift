/// Everything about the moment that can silence a suggestion, and nothing about the candidates.
public struct PredictionContext: Sendable, Equatable {
    /// The line the caret is on, up to the caret, which is what a completion continues.
    public let typed: String
    /// Whether the caret sits at the end of that line, which completing presumes.
    public let caretAtLineEnd: Bool
    /// Whether any text is selected, which the next keystroke would replace.
    public let hasSelection: Bool
    /// Whether an input method is mid-composition, which owns both the screen and the Tab key.
    public let isComposing: Bool
    /// Whether the field hides what is typed into it.
    public let isSecure: Bool
    /// Whether the field holds prose rather than a command or an address.
    public let isProse: Bool
    /// How long since the last keystroke, which says whether the user is in flow or hesitating.
    public let millisecondsSinceKeystroke: Int
    /// Whether the user has left suggestions on for this application.
    public let isEnabledHere: Bool
    /// Whether the user has pressed escape, leaving only the dot.
    public let isMinimised: Bool
    /// How many suggestions have been typed past in this field this session.
    public let rejectionsThisSession: Int

    public init(
        typed: String, caretAtLineEnd: Bool = true, hasSelection: Bool = false,
        isComposing: Bool = false, isSecure: Bool = false, isProse: Bool = false,
        millisecondsSinceKeystroke: Int = 1_000, isEnabledHere: Bool = true,
        isMinimised: Bool = false, rejectionsThisSession: Int = 0
    ) {
        self.typed = typed
        self.caretAtLineEnd = caretAtLineEnd
        self.hasSelection = hasSelection
        self.isComposing = isComposing
        self.isSecure = isSecure
        self.isProse = isProse
        self.millisecondsSinceKeystroke = millisecondsSinceKeystroke
        self.isEnabledHere = isEnabledHere
        self.isMinimised = isMinimised
        self.rejectionsThisSession = rejectionsThisSession
    }
}

/// The rules that draw nothing whatever the candidates say, so the feature is quiet by default.
public enum Quieting {
    /// How long a prose writer must pause before a suggestion is worth their attention.
    public static let proseHesitationInMilliseconds = 400

    /// How many times a suggestion may be typed past in one field before that field goes quiet.
    public static let rejectionsBeforeSilence = 3

    /// Whether nothing at all may be drawn right now.
    public static func refuses(_ context: PredictionContext) -> Bool {
        reason(context) != nil
    }

    /// Why nothing may be drawn; composition is deliberately not consulted, so the IME never gates drawing.
    public static func reason(_ context: PredictionContext) -> Reason? {
        if !context.isEnabledHere { return .turnedOffHere }
        if context.isSecure { return .secureField }
        if context.hasSelection { return .textSelected }
        if !context.caretAtLineEnd { return .caretInsideText }
        if context.rejectionsThisSession >= rejectionsBeforeSilence { return .rejectedTooOften }
        if context.isProse, context.millisecondsSinceKeystroke < proseHesitationInMilliseconds {
            return .writingFluently
        }
        return nil
    }

    /// One reason a suggestion was withheld.
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        case turnedOffHere
        case secureField
        case textSelected
        case inputMethodComposing
        case caretInsideText
        case rejectedTooOften
        case writingFluently
    }
}
