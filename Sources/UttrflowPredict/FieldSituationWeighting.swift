public import struct Foundation.Date

/// How much a candidate's recorded situation lifts it, multiplied onto the evidence rather than mixed into it.
public enum FieldSituationWeighting {
    /// How much a candidate tagged with exactly this situation may be lifted.
    public static let agreementLift = 0.6

    /// How far a candidate tagged with a conflicting situation may be lowered, kept small so it stays offerable.
    public static let conflictDrop = 0.25

    /// The multiplier for a candidate tagged `tag`, judged in the situation the user is in now.
    public static func weight(for tag: FieldSituation?, in current: FieldSituation) -> Double {
        guard let tag, !tag.isEmpty, !current.isEmpty else { return 1 }
        let signed = (tag.similarity(to: current) - FieldSituation.unknownAgreement) * 2
        return 1 + signed * (signed >= 0 ? agreementLift : conflictDrop)
    }

    /// What a candidate is worth here, which is what it is worth anywhere times what its tag says.
    public static func score(
        _ candidate: Candidate, tagged tag: FieldSituation?, in current: FieldSituation, now: Date
    ) -> Double {
        Frecency.score(candidate, now: now) * weight(for: tag, in: current)
    }
}
