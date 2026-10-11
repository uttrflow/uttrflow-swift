import struct Foundation.Date

/// Every candidate scored and compared, which is what separation and support are read from.
struct Ranking: Sendable, Equatable {
    /// The candidates, best first.
    let candidates: [ScoredCandidate]

    /// Ranks candidates as they stand at one moment.
    init(_ candidates: [Candidate], now: Date) {
        let scored = candidates.map { ($0, Frecency.score($0, now: now)) }.filter { $0.1 > 0 }
        let merged = Dictionary(grouping: scored, by: { $0.0.text.lowercased() }).values.compactMap {
            variants -> (Candidate, Double)? in
            guard
                let representative = variants.sorted(by: {
                    ($0.1, $1.0.text) > ($1.1, $0.0.text)
                }).first
            else { return nil }
            let candidate = Candidate(
                text: representative.0.text, source: representative.0.source,
                evidence: representative.0.evidence, editDistance: representative.0.editDistance,
                isIrreversible: variants.contains { $0.0.isIrreversible })
            return (candidate, variants.reduce(0) { $0 + $1.1 })
        }
        let total = merged.reduce(0) { $0 + $1.1 }
        self.candidates =
            merged
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

    /// Whether nothing survived scoring, so there is nothing to measure.
    var isEmpty: Bool { candidates.isEmpty }
}
