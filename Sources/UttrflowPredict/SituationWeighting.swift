public import struct Foundation.Date

/// How much a candidate's recorded situation lifts it, multiplied onto the evidence rather than mixed into it.
public enum SituationWeighting {
    /// How much a candidate tagged with exactly this situation may be lifted.
    public static let agreementLift = 0.6

    /// How far a candidate tagged with a conflicting situation may be lowered, kept small so it stays offerable.
    public static let conflictDrop = 0.25

    /// The multiplier for a candidate tagged `tag`, judged in the situation the user is in now.
    public static func weight(for tag: Situation?, in current: Situation) -> Double {
        guard let tag, !tag.isEmpty, !current.isEmpty else { return 1 }
        let signed = (tag.similarity(to: current) - Situation.unknownAgreement) * 2
        return 1 + signed * (signed >= 0 ? agreementLift : conflictDrop)
    }

    /// What a candidate is worth here, which is what it is worth anywhere times what its tag says.
    public static func score(
        _ candidate: Candidate, tagged tag: Situation?, in current: Situation, now: Date
    ) -> Double {
        Frecency.score(candidate, now: now) * weight(for: tag, in: current)
    }

    /// The candidates in the order this situation puts them, ties broken as the ranking breaks them.
    public static func ordered(
        _ tagged: [(candidate: Candidate, situation: Situation?)], in current: Situation, now: Date
    ) -> [Candidate] {
        tagged
            .map { ($0.candidate, score($0.candidate, tagged: $0.situation, in: current, now: now)) }
            .sorted { ($0.1, $1.0.text) > ($1.1, $0.0.text) }
            .map(\.0)
    }
}
