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
        let ranked = ranked(from: candidates, in: context, now: now)
        return (ranked.suggestion, ranked.silence)
    }

    /// The decision with the ranking it was read from, nil only when the context refused before ranking.
    static func ranked(
        from candidates: [Candidate], in context: PredictionContext, now: Date
    ) -> (suggestion: Suggestion, silence: Quieting.Reason?, ranking: Ranking?) {
        if let refused = Quieting.reason(context) { return (.silent, refused, nil) }
        guard !context.isMinimised else { return (.minimised, .minimised, nil) }

        let ranking = Ranking(candidates, now: now)
        let decided = decision(from: ranking)
        return (decided.suggestion, decided.silence, ranking)
    }

    /// What to draw from an already built ranking, once the context has allowed speaking.
    private static func decision(from ranking: Ranking) -> (suggestion: Suggestion, silence: Quieting.Reason?)
    {
        guard let leader = ranking.candidates.first else { return (.silent, .nothingOffered) }
        guard ranking.support >= supportFloor else { return (.silent, .evidenceTooThin) }

        // An irreversible leader is never offered, and never stepped past to promote a rival it outranked.
        guard !leader.candidate.isIrreversible else { return (.silent, .irreversibleNotCertain) }
        guard ranking.separation < separationThreshold else { return (.certain(leader.text), nil) }

        // A rival that differs from a line already offered only in case is the same line, not a second option.
        var offered: Set<String> = [leader.text.lowercased()]
        let rivals = ranking.candidates.dropFirst().filter { offered.insert($0.text.lowercased()).inserted }
        guard !rivals.isEmpty else { return (.certain(leader.text), nil) }
        let others =
            rivals
            .filter { !$0.candidate.isIrreversible }
            .prefix(maximumChoices - 1)
            .map(\.text)
        // A close race whose every rival was barred is still unseparated, so it is not shown as certain.
        guard !others.isEmpty else { return (.silent, .irreversibleNotCertain) }
        return (.choice(leader: leader.text, others: others), nil)
    }
}
