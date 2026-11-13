// The share of a person's dictated words that went into each kind of destination, projected from the style rows.

/// What the person dictates into, computed on read from `StyleSignals`' word counts; it writes no row of its own.
public enum DomainMix {
    /// Fewer words than this in all, and no mix is claimed, so a few dictations do not read as a habit.
    public static let minimumWords = 200

    /// Each destination's share of the dictated words, summing to 1; empty below ``minimumWords``.
    public static func project(_ rows: [EvidenceRow]) -> [Destination: Double] {
        var words: [Destination: Int] = [:]
        for row in rows where row.kind == .styleWords {
            guard let destination = Destination(rawValue: row.subject) else { continue }
            words[destination, default: 0] += row.weight
        }
        // Signed, as `StyleSignals.project` sums them; a destination's total is clamped, never one row.
        let kept = words.filter { $0.value > 0 }
        let total = kept.values.reduce(0, +)
        guard total >= minimumWords else { return [:] }
        return kept.mapValues { Double($0) / Double(total) }
    }
}
