public import UttrflowCore

// Which layer owns each formatting class, so the prompt asks the model only for what the rules do not own.

/// The layer that decides one formatting class.
public enum FormattingOwner: String, Sendable, Equatable, CaseIterable {
    /// A cleaning pass decides it, and the model is not asked to.
    case rules
    /// Only the model decides it; no pass writes it.
    case model
    /// Both write it, and the passes after the model have the last word, so a rule's decision stands.
    case both
}

/// One class's owner, the passes that write it and why the line falls where it does.
public struct FormattingOwnership: Sendable, Equatable {
    public let owner: FormattingOwner
    /// The passes that write this class; empty exactly when the model owns it alone.
    public let passes: [PassID]
    public let reason: String
}

extension FormattingClass {
    /// Who owns this class; the switch is exhaustive, so a new class does not compile without an owner.
    public var ownership: FormattingOwnership {
        switch self {
        case .sentenceBoundaries:
            FormattingOwnership(
                owner: .both, passes: ["sentenceBoundary", .firstWord, .terminalStop],
                reason:
                    "The model places a boundary from the speech; the rules take back a run-on stop and cap and end it."
            )
        case .commas:
            FormattingOwnership(
                owner: .both, passes: [.spokenPunctuation],
                reason: "A spoken comma is a rule; a comma read from a pause or a conjunction is the model's."
            )
        case .questions:
            FormattingOwnership(
                owner: .both, passes: [.spokenPunctuation, .terminalStop],
                reason:
                    "The rules end a sentence whose word order asks; a question with no such shape is the model's."
            )
        case .quotesAndBrackets:
            FormattingOwnership(
                owner: .rules, passes: [.spokenPunctuation, "caretCloser"],
                reason: "Quotes and brackets come from spoken marks; a closer the model adds is taken back.")
        case .ellipses:
            FormattingOwnership(
                owner: .rules, passes: [.spokenPunctuation, .spacing],
                reason: "An ellipsis is spoken or comes from the recogniser, and is never inferred.")
        case .capitalisationAndTokens:
            FormattingOwnership(
                owner: .both, passes: [.spelledInitialism, .firstWord],
                reason:
                    "The rules join spelled letters and case the first word; a brand or address spelling is the model's."
            )
        case .numbers:
            FormattingOwnership(
                owner: .rules, passes: [.numberForms, "digitGrouping"],
                reason: "Numerals follow the destination's number policy, which only the rules read.")
        case .lists:
            FormattingOwnership(
                owner: .both, passes: [.layoutWords],
                reason: "A spoken list marker is a rule; the commas of an inline series are the model's.")
        case .paragraphs:
            FormattingOwnership(
                owner: .rules, passes: [.layoutWords],
                reason: "A break comes from a spoken layout word, never from the model's guess.")
        case .corrections:
            FormattingOwnership(
                owner: .rules, passes: [.fillers, .stammers, .repeatedPhrase, .selfCorrection],
                reason: "What the speaker took back is removed before the model sees the text.")
        case .perDestination:
            FormattingOwnership(
                owner: .both, passes: [.firstWord, .terminalStop],
                reason:
                    "The formatter's case and stop policies are rules; the place's style block is the model's."
            )
        case .codeAndMarkdown:
            FormattingOwnership(
                owner: .both, passes: [.codeEditorCommands, .spacing],
                reason:
                    "Spoken casing and symbol commands are rules; an identifier read off the screen is the model's."
            )
        case .hinglish:
            FormattingOwnership(
                owner: .model, passes: [],
                reason: "Romanising Hindi needs the sentence, which no pass reads.")
        case .abstention:
            FormattingOwnership(
                owner: .model, passes: [],
                reason: "Technical words used as ordinary speech need the sentence, which no pass reads.")
        case .textAfterCaret:
            FormattingOwnership(
                owner: .rules, passes: [.firstWord, .caretEcho, "caretCloser", .terminalStop],
                reason: "The caret's case, echo and closers are read off the field's text by the rules.")
        }
    }
}
