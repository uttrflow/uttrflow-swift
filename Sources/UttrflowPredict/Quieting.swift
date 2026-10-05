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

    /// Why nothing may be drawn; only the field's own marked text gates on composition, never the input-source guess. See `Docs/predict-ime.md`.
    public static func reason(_ context: PredictionContext) -> Reason? {
        if !context.isEnabledHere { return .turnedOffHere }
        if context.isSecure { return .secureField }
        if context.markedText == .present { return .composing }
        if !context.writingDirectionKnown { return .unknownWritingDirection }
        if !context.canDraw { return .nowhereToDraw }
        if context.hasSelection { return .textSelected }
        if !context.caretAtLineEnd { return .caretInsideText }
        if context.showsOwnList { return .applicationPicker }
        if context.applicationSupportsPickers, AppPicker.isOpen(after: context.typed) {
            return .applicationPicker
        }
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
        /// The field reports marked text, so an input method owns the line, Escape and the arrows.
        case composing
        /// The adjacent glyph bounds do not establish which side the continuation belongs on.
        case unknownWritingDirection
        /// The field reports no caret, so there is no place on its line to draw.
        case nowhereToDraw
        /// Text is selected, which the next keystroke would replace.
        case textSelected
        /// The caret is not at the end of its line.
        case caretInsideText
        /// The application's own picker or list is open over the line, by the word typed or by the field's word, and owns Tab and Escape.
        case applicationPicker
        /// Enough suggestions were typed past in this field to silence it.
        case rejectedTooOften
        /// A prose writer is still in flow and has not paused.
        case writingFluently
        /// No field has the focus.
        case nothingFocused
        /// An empty line is not a prefix of anything.
        case emptyLine
        /// A list line holding only its marker, so nothing of the item has been typed yet.
        case listMarkerOnly
        /// A line past `SuggestionSession.maximumTypedLength` is a document, not a prefix.
        case lineTooLong
        /// The line holds another script, where nothing Uttrflow may write belongs. See `Docs/predict.md`.
        case nonLatinLine
        /// The user pressed ⎋, so only the dot remains.
        case minimised
        /// Nothing extends the line: no candidate, none the gates allowed, or nothing usable from the model.
        case nothingOffered
        /// Every line the model wrote names a program, a path or a branch this machine does not have.
        case notOnThisMachine
        /// The leader has less evidence than `PredictionEngine.supportFloor`.
        case evidenceTooThin
        /// The model's own line scored under the floor it needed, or could not be scored at all. See `Docs/predict-precision.md`.
        case modelUnsure
        /// The leader, or every close rival to it, cannot be undone, so nothing is offered.
        case irreversibleNotCertain
        /// The turn ran past `SuggestionSession.turnBudgetInMilliseconds`.
        case overBudget
        /// Quiet mode dropped a list the session was unsure about.
        case quietModeChoice
    }
}
