// What a refusal found, said without naming anything the speaker said.

/// The kind of thing that refused a rewrite, which a report may carry where the reason may not. See `Docs/ai-model-output.md`.
public enum RefusalKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// A word the speaker said is gone from the rewrite, or stands replaced by another.
    case lostWord
    /// A word nobody said appears in the rewrite.
    case inventedWord
    /// A word the speaker said appears somewhere else in the rewrite.
    case movedWord
    /// A word a pass took out is not put back, so the rewrite is missing it too.
    case removedWordNotRestored
    /// The rewrite used a reading of a doubtful run that was never offered to it.
    case unofferedReading
    /// The rewrite begins with something addressed to the reader rather than with what was said.
    case preamble
    /// The rewrite carries line breaks or a list the speaker did not ask for, or lost ones they did.
    case layout
    /// The rewrite has nothing in it.
    case emptyRewrite
    /// The rewrite is far longer than what was said.
    case tooLong
    /// The rewrite keeps too little of what was said to be a tidy of it.
    case tooShort
    /// The rewrite holds a number nobody said.
    case inventedNumber
    /// The rewrite wrote a number the speaker said as a different amount.
    case changedNumber
    /// A "not" the speaker said is gone from the rewrite.
    case negationDropped
    /// A "not" nobody said appears in the rewrite.
    case negationAdded
    /// A "not" the speaker said governs something else in the rewrite.
    case negationMoved
    /// The rewrite swapped more small words than tidying explains.
    case smallWordChurn
    /// The rewrite is not written in the Latin alphabet.
    case notLatinScript
    /// The rewrite repeats one of the worked examples it was shown.
    case echoedExample
    /// The rewrite translated what was said instead of romanising it.
    case translated

    /// What a pasted report calls this, which names the kind and never the words.
    public var summary: String {
        switch self {
        case .lostWord: "a word was lost or replaced"
        case .inventedWord: "a word was invented"
        case .movedWord: "a word was moved"
        case .removedWordNotRestored: "a word a step removed was not put back"
        case .unofferedReading: "a reading was used that was not offered"
        case .preamble: "the answer began with a preamble"
        case .layout: "the line breaks or the list were not what was spoken"
        case .emptyRewrite: "the answer was empty"
        case .tooLong: "the answer was far longer than what was said"
        case .tooShort: "the answer kept too little of what was said"
        case .inventedNumber: "a number was invented"
        case .changedNumber: "a number was written as another amount"
        case .negationDropped: "a negation was dropped"
        case .negationAdded: "a negation was added"
        case .negationMoved: "a negation was moved"
        case .smallWordChurn: "too many small words were swapped"
        case .notLatinScript: "the answer was not in the Latin alphabet"
        case .echoedExample: "the answer repeated a worked example"
        case .translated: "the answer was translated rather than romanised"
        }
    }
}
