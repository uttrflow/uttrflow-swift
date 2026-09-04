public import struct Foundation.Date

/// Turns candidates and a moment into the one thing the surface should draw.
public enum PredictionEngine {
    /// How far ahead the leader must be to be shown alone, which is what certainty means here.
    public static let separationThreshold = 0.20

    /// How much evidence the leader needs before anything is worth drawing, below one plain use of a line.
    public static let supportFloor = 0.15

    /// How many candidates a list may hold before it stops being a choice and becomes a search.
    public static let maximumChoices = 4

    /// What to draw, given everything known at this keystroke.
    public static func suggestion(
        from candidates: [Candidate], in context: PredictionContext, now: Date
    ) -> Suggestion {
        decision(from: candidates, in: context, now: now).suggestion
    }

    /// What to draw and, when nothing is on offer, why, decided together so the two cannot disagree.
    public static func decision(
        from candidates: [Candidate], in context: PredictionContext, now: Date
    ) -> (suggestion: Suggestion, silence: Quieting.Reason?) {
        if let refused = Quieting.reason(context) { return (.silent, refused) }
        guard !context.isMinimised else { return (.minimised, .minimised) }

        let ranking = Ranking(candidates, now: now)
        guard let leader = ranking.candidates.first else { return (.silent, .nothingOffered) }
        guard ranking.support >= supportFloor else { return (.silent, .evidenceTooThin) }

        let separated = ranking.separation >= separationThreshold
        // An irreversible completion is offered only when it clearly beats a real rival, never alone on thin evidence.
        let dominatesRivals = separated && ranking.candidates.count > 1
        guard !leader.candidate.isIrreversible || dominatesRivals else {
            return (.silent, .irreversibleNotCertain)
        }
        guard !separated else { return (.certain(leader.text), nil) }

        let others =
            ranking.candidates
            .dropFirst()
            .filter { !$0.candidate.isIrreversible }
            .prefix(maximumChoices - 1)
            .map(\.text)
        return (others.isEmpty ? .certain(leader.text) : .choice(leader: leader.text, others: others), nil)
    }
}
