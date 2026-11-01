/// Why a line break, paragraph break or list mark stands in a draft, so a verifier can ask what justified it.
public enum BreakEvidence: Sendable, Equatable {
    /// The speaker said the break: "new line", "new paragraph", "bullet point".
    case spokenCommand
    /// A pause of this length before the sentence that opens after the break.
    case longPause(Duration)
    /// A phrase a speaker moves on to a new topic with.
    case topicCue
    /// A counted sequence the speaker enumerated: "first", "second", "number three".
    case ordinalEnumeration
    /// A series the speaker announced with a count ("the following three items") and then spoke in full, that many members.
    case announcedSeries
    /// The break was already in a piece that was laid out and checked before the pieces were joined.
    case carried

    /// Whether the speaker asked for the break, which no legality row overrules.
    public var isSpoken: Bool { self == .spokenCommand }

    /// Whether the break was inferred from the shape of the speech rather than asked for or already checked.
    public var isInferred: Bool {
        switch self {
        case .longPause, .topicCue, .ordinalEnumeration: true
        case .spokenCommand, .carried, .announcedSeries: false
        }
    }
}
