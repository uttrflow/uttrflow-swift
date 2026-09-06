/// Where a candidate came from, which decides how much it is trusted on its own.
public enum CandidateSource: Sendable, Equatable, CaseIterable {
    /// Something the user has entered in this field before.
    case personal
    /// Something that exists on this machine right now, such as a branch or a filename.
    case environment
    /// What usually follows what the user last entered here.
    case succession
}

/// One thing the user might be about to type, before it has been ranked.
public struct Candidate: Sendable, Equatable {
    /// The whole text, including the part already typed.
    public let text: String
    /// Where it came from, which decides how much it is trusted on its own.
    public let source: CandidateSource
    /// What the corpus knows about it, absent for a candidate the environment supplied.
    public let evidence: Entry?
    /// How many edits separate the typed characters from this candidate's opening.
    public let editDistance: Int
    /// Whether taking it cannot be undone, which bars it from being offered on thin evidence.
    public let isIrreversible: Bool

    /// One thing the user might be about to type, with whatever is known about it.
    public init(
        text: String, source: CandidateSource, evidence: Entry? = nil, editDistance: Int = 0,
        isIrreversible: Bool = false
    ) {
        self.text = text
        self.source = source
        self.evidence = evidence
        self.editDistance = editDistance
        self.isIrreversible = isIrreversible
    }
}

/// A candidate with the score that decided its place.
struct ScoredCandidate: Sendable, Equatable {
    /// The candidate this score belongs to.
    let candidate: Candidate
    /// The raw score, which says how much evidence there is.
    let score: Double
    /// The score as a share of every candidate's, which says how it compares.
    let share: Double

    /// The whole line the candidate stands for.
    var text: String { candidate.text }
}
