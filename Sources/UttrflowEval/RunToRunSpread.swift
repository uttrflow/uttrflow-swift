// How far repeated runs of one recogniser over the same audio disagree with each other.

/// The noise floor a regression verdict has to sit above, measured from repeated runs of one configuration.
public struct RunToRunSpread: Sendable, Equatable {
    /// One passage across every run that transcribed it.
    public struct Passage: Sendable, Equatable {
        public let id: String
        /// How many runs produced a score for this passage.
        public let runs: Int
        /// How many different transcripts the runs gave, compared character for character.
        public let distinctTranscripts: Int
        /// The share of runs that gave the most frequent transcript; 1 means every run agreed.
        public let identicalTextRate: Double
        /// The lowest and highest rate any run scored; `nil` when no run had a scorable transcript.
        public let lowestRate: Double?
        public let highestRate: Double?

        /// Highest minus lowest rate, in percentage points, the unit a comparison's interval is printed in.
        public var spreadPercentagePoints: Double? {
            guard let lowestRate, let highestRate else { return nil }
            return (highestRate - lowestRate) * 100
        }

        public var isIdentical: Bool { distinctTranscripts <= 1 }
    }

    /// Every passage, in the order the first run reported it.
    public let passages: [Passage]
    /// Each run's headline rate, in run order; `nil` for a run with nothing scored.
    public let overallRates: [Double?]

    public init(runs: [TranscriptionReport]) {
        var order: [String] = []
        var byPassage: [String: [PassageScore]] = [:]
        for score in runs.flatMap(\.scores) {
            if byPassage[score.id] == nil { order.append(score.id) }
            byPassage[score.id, default: []].append(score)
        }
        passages = order.map { id in Self.passage(id: id, scores: byPassage[id] ?? []) }
        overallRates = runs.map(\.overall.rate)
    }

    /// Passages where at least one run's transcript differs from another's.
    public var differing: [Passage] { passages.filter { !$0.isIdentical } }

    /// The share of passages every run transcribed identically.
    public var identicalPassageRate: Double? {
        guard !passages.isEmpty else { return nil }
        return Double(passages.count - differing.count) / Double(passages.count)
    }

    /// Highest minus lowest headline rate across runs, in percentage points.
    public var overallSpreadPercentagePoints: Double? {
        let rates = overallRates.compactMap(\.self)
        guard let lowest = rates.min(), let highest = rates.max() else { return nil }
        return (highest - lowest) * 100
    }

    /// The row `Docs/eval-methodology.md` records, so the table is pasted from a run rather than typed.
    public func tableRow(on machine: MachineDescription) -> String {
        let identical = identicalPassageRate.map {
            "\(passages.count - differing.count) of \(passages.count) (\(Self.percent($0)))"
        }
        let spread = overallSpreadPercentagePoints.map { Self.points($0) }
        let names = differing.isEmpty ? "none" : differing.map(\.id).joined(separator: ", ")
        let cells = [
            machine.chip, machine.operatingSystem, "\(overallRates.count)", identical ?? "n/a",
            spread ?? "n/a",
            names,
        ]
        return "| " + cells.joined(separator: " | ") + " |"
    }

    private static func percent(_ share: Double) -> String {
        "\((share * 1000).rounded() / 10)%"
    }

    private static func points(_ value: Double) -> String {
        "\((value * 100).rounded() / 100)"
    }

    private static func passage(id: String, scores: [PassageScore]) -> Passage {
        let counts = scores.reduce(into: [String: Int]()) { $0[$1.transcript, default: 0] += 1 }
        let rates = scores.compactMap { $0.wordErrorRate?.rate }
        let agreeing = counts.values.max() ?? 0
        return Passage(
            id: id, runs: scores.count, distinctTranscripts: counts.count,
            identicalTextRate: scores.isEmpty ? 0 : Double(agreeing) / Double(scores.count),
            lowestRate: rates.min(), highestRate: rates.max())
    }
}
