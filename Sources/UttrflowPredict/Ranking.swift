import struct Foundation.Date

/// Every candidate scored and compared, which is what separation and support are read from.
struct Ranking: Sendable, Equatable {
    /// The candidates, best first.
    let candidates: [ScoredCandidate]

    /// Ranks candidates as they stand at one moment.
    init(_ candidates: [Candidate], now: Date) {
        let scored = candidates.map { ($0, Frecency.score($0, now: now)) }.filter { $0.1 > 0 }
        let total = scored.reduce(0) { $0 + $1.1 }
        self.candidates =
            scored
            .map { ScoredCandidate(candidate: $0.0, score: $0.1, share: total > 0 ? $0.1 / total : 0) }
            .sorted { ($0.score, $1.text) > ($1.score, $0.text) }
    }

    /// How much evidence stands behind the best candidate, which decides whether to speak at all.
    var support: Double { candidates.first?.score ?? 0 }

    /// How far the best candidate leads the second, which decides whether to speak of one or several.
    var separation: Double {
        guard let first = candidates.first else { return 0 }
        guard candidates.count > 1 else { return 1 }
        return first.share - candidates[1].share
    }

    var isEmpty: Bool { candidates.isEmpty }
}
