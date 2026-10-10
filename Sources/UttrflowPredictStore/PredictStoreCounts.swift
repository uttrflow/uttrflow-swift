import UttrflowCore

/// Counts the values currently kept in the suggestion corpus.
public struct PredictionCorpusCounts: Sendable, Equatable {
    public let entries: Int
    public let uses: Int
    public let accepted: Int
    public let rejected: Int
    public let selfSourced: Int

    /// Builds the aggregate from stored entry fields.
    public init(entries: Int, uses: Int, accepted: Int, rejected: Int, selfSourced: Int) {
        self.entries = entries
        self.uses = uses
        self.accepted = accepted
        self.rejected = rejected
        self.selfSourced = selfSourced
    }
}

extension PredictStore {
    /// Counts the corpus totals that Insights can show without estimating offer quality.
    public func corpusCounts() throws(PredictStoreError) -> PredictionCorpusCounts {
        let totals = try database.rows(
            "SELECT COUNT(*), SUM(count), SUM(accepted), SUM(rejected), SUM(self_sourced) FROM entry",
            { _ in }
        ) {
            PredictionCorpusCounts(
                entries: $0.integer(0), uses: $0.integer(1),
                accepted: $0.integer(2), rejected: $0.integer(3), selfSourced: $0.integer(4))
        }
        return totals.first
            ?? PredictionCorpusCounts(entries: 0, uses: 0, accepted: 0, rejected: 0, selfSourced: 0)
    }

    /// How many entries each application has taught, keyed by bundle identifier.
    public func entryCountsByApplication() throws(PredictStoreError) -> [String: Int] {
        let counted = try database.rows(
            """
            SELECT bundle_id, COUNT(*) FROM entry
            JOIN surface ON surface.id = entry.surface_id
            GROUP BY bundle_id
            """, { _ in }
        ) { ($0.text(0), $0.integer(1)) }
        return Dictionary(counted, uniquingKeysWith: +)
    }

    /// The newest lines anywhere in one application, newest first, leaving out our own suggestions.
    public func recentLines(
        inApplication bundleIdentifier: String, limit: Int
    ) throws(PredictStoreError) -> [String] {
        guard limit > 0 else { return [] }
        return try database.rows(
            """
            SELECT entry.text FROM entry
            JOIN surface ON surface.id = entry.surface_id
            WHERE surface.bundle_id = ? AND entry.superseded_by IS NULL AND entry.count > entry.self_sourced
            ORDER BY entry.last_used DESC LIMIT ?
            """,
            {
                $0.bind(1, ApplicationKey.of(bundleIdentifier))
                $0.bind(2, Int64(limit))
            }
        ) { $0.text(0) }
    }

    /// How many entries the corpus holds across every surface.
    public func entryCount() throws(PredictStoreError) -> Int {
        try database.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) }.first ?? 0
    }
}
