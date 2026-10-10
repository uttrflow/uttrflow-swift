/// One piece of evidence for or against writing a kind of notation, held as data. See `Docs/adapters.md` §1.
public enum AdapterCue: String, Sendable, Equatable, CaseIterable {
    /// The caret stands in executable source, or in a string inside it.
    case caretInCode
    /// The destination runs what is typed, so every word is part of a command line.
    case commandLine
    /// The caret is in a query editor and the speech opens a statement, which a sentence about a query does not.
    case queryStatement
    /// The caret stands in a comment, a docstring or a prose body, where the words are prose.
    case caretInProse
    /// The speech holds a word code is never dictated with, such as an article.
    case proseWord

    /// How much the cue counts toward activation when it speaks for the notation.
    public var weight: Double {
        switch self {
        case .caretInCode, .commandLine, .queryStatement: 1
        case .caretInProse, .proseWord: 0
        }
    }
}

/// Whether a kind of notation fits what is being written, and on what evidence; abstaining is the ordinary answer.
public enum Applicability: Sendable, Equatable {
    /// Nothing said either way.
    case noEvidence
    /// A cue says this is not the notation's place.
    case ruledOut(by: AdapterCue)
    /// The cues that speak for the notation, and the confidence they add up to.
    case evidenced(confidence: Double, by: [AdapterCue])

    /// The applicability the cues give: any cue against rules it out, otherwise their weights add up.
    public init(cues: [AdapterCue]) {
        if let against = cues.first(where: { $0.weight == 0 }) {
            self = .ruledOut(by: against)
        } else if cues.isEmpty {
            self = .noEvidence
        } else {
            self = .evidenced(confidence: min(1, cues.reduce(0) { $0 + $1.weight }), by: cues)
        }
    }

    /// The cues behind this answer, in the order they were read.
    public var cues: [AdapterCue] {
        switch self {
        case .noEvidence: []
        case .ruledOut(let cue): [cue]
        case .evidenced(_, let cues): cues
        }
    }

    /// The same evidence with more cues read, such as the speech's after the screen's.
    public func adding(_ more: [AdapterCue]) -> Applicability {
        Applicability(cues: cues + more)
    }

    /// Whether the notation may fire: only on evidence at or above the threshold, never on missing evidence.
    public func activates(at threshold: Double) -> Bool {
        guard case .evidenced(let confidence, _) = self else { return false }
        return confidence >= threshold
    }
}
