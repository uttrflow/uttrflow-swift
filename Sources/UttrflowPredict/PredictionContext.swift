public import UttrflowCore

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
    /// What the field itself says about marked text, which alone is definite enough to stay quiet on.
    public let markedText: MarkedText
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
    /// Whether the field is a terminal's command line, where `@`, `:` and `/` open no picker.
    public let isCommandLine: Bool
    /// Whether the field says the application's own list of choices is open, which owns Tab, Escape and the arrows.
    public let showsOwnList: Bool
    /// Whether this surface has a picker; filled by `SuggestionSession`.
    var applicationSupportsPickers = false
    /// Whether the writing direction at the caret is known well enough to place a ghost safely.
    public let writingDirectionKnown: Bool

    /// One moment in one field, everything but the line defaulted to the ordinary case.
    public init(
        typed: String, caretAtLineEnd: Bool = true, hasSelection: Bool = false,
        isComposing: Bool = false, isSecure: Bool = false, isProse: Bool = false,
        millisecondsSinceKeystroke: Int = 1_000, isEnabledHere: Bool = true,
        isMinimised: Bool = false, rejectionsThisSession: Int = 0, canDraw: Bool = true,
        markedText: MarkedText = .unanswered, isCommandLine: Bool = false, showsOwnList: Bool = false,
        writingDirectionKnown: Bool = true
    ) {
        self.typed = typed
        self.caretAtLineEnd = caretAtLineEnd
        self.hasSelection = hasSelection
        self.isComposing = isComposing
        self.markedText = markedText
        self.isSecure = isSecure
        self.isProse = isProse
        self.millisecondsSinceKeystroke = millisecondsSinceKeystroke
        self.isEnabledHere = isEnabledHere
        self.isMinimised = isMinimised
        self.rejectionsThisSession = rejectionsThisSession
        self.canDraw = canDraw
        self.isCommandLine = isCommandLine
        self.showsOwnList = showsOwnList
        self.writingDirectionKnown = writingDirectionKnown
    }
}
