public import struct Foundation.Date

/// Turns candidates and a moment into the one thing the surface should draw.
public enum PredictionEngine {
    /// How far ahead the leader must be to be shown alone, which is what certainty means here.
    public static let separationThreshold = 0.20

    /// How much evidence the leader needs before anything is worth drawing.
    public static let supportFloor = 0.6

    /// How many candidates a list may hold before it stops being a choice and becomes a search.
    public static let maximumChoices = 4

    /// What to draw, given everything known at this keystroke.
    public static func suggestion(
        from candidates: [Candidate], in context: PredictionContext, now: Date
    ) -> Suggestion {
        guard !Quieting.refuses(context) else { return .silent }
        guard !context.isMinimised else { return .minimised }

        let ranking = Ranking(candidates, now: now)
        guard let leader = ranking.candidates.first, ranking.support >= supportFloor else {
            return .silent
        }

        let separated = ranking.separation >= separationThreshold
        // An irreversible completion is offered only when it clearly beats a real rival, never alone on thin evidence.
        let dominatesRivals = separated && ranking.candidates.count > 1
        guard !leader.candidate.isIrreversible || dominatesRivals else { return .silent }
        guard !separated else { return .certain(leader.text) }

        let others =
            ranking.candidates
            .dropFirst()
            .filter { !$0.candidate.isIrreversible }
            .prefix(maximumChoices - 1)
            .map(\.text)
        return others.isEmpty ? .certain(leader.text) : .choice(leader: leader.text, others: others)
    }
}
