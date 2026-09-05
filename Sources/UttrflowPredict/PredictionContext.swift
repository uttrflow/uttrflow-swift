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
    /// Whether the field gives a place to draw at all, which a field that reports no caret does not.
    public let canDraw: Bool

    public init(
        typed: String, caretAtLineEnd: Bool = true, hasSelection: Bool = false,
        isComposing: Bool = false, isSecure: Bool = false, isProse: Bool = false,
        millisecondsSinceKeystroke: Int = 1_000, isEnabledHere: Bool = true,
        isMinimised: Bool = false, rejectionsThisSession: Int = 0, canDraw: Bool = true
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
        self.canDraw = canDraw
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
        if !context.canDraw { return .nowhereToDraw }
        if context.hasSelection { return .textSelected }
        if !context.caretAtLineEnd { return .caretInsideText }
        if context.rejectionsThisSession >= rejectionsBeforeSilence { return .rejectedTooOften }
        if context.isProse, context.millisecondsSinceKeystroke < proseHesitationInMilliseconds {
            return .writingFluently
        }
        return nil
    }

    /// Why nothing is on offer, from the moment's own rules or from the turn that followed them.
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        /// Suggestions are off in this field, by ⎋⎋, by ⌥⎋ or by the preferences.
        case turnedOffHere
        /// The field hides what is typed into it.
        case secureField
        /// The field reports no caret, so there is no place on its line to draw.
        case nowhereToDraw
        /// Text is selected, which the next keystroke would replace.
        case textSelected
        /// The caret is not at the end of its line.
        case caretInsideText
        /// Enough suggestions were typed past in this field to silence it.
        case rejectedTooOften
        /// A prose writer is still in flow and has not paused.
        case writingFluently
        /// No field has the focus.
        case nothingFocused
        /// An empty line is not a prefix of anything.
        case emptyLine
        /// A line past `SuggestionSession.maximumTypedLength` is a document, not a prefix.
        case lineTooLong
        /// The user pressed ⎋, so only the dot remains.
        case minimised
        /// Nothing extends the line: no candidate, none the gates allowed, or nothing usable from the model.
        case nothingOffered
        /// Every line the model wrote names a program, a path or a branch this machine does not have.
        case notOnThisMachine
        /// The leader has less evidence than `PredictionEngine.supportFloor`.
        case evidenceTooThin
        /// An irreversible leader does not clearly beat a real rival.
        case irreversibleNotCertain
        /// The turn ran past `SuggestionSession.turnBudgetInMilliseconds`.
        case overBudget
        /// Quiet mode dropped a list the session was unsure about.
        case quietModeChoice
    }
}
