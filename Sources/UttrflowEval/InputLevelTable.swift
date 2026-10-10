// Word error rate by input level, from passages each replayed at every level of the gain sweep.
public import UttrflowCore

/// What one passage scored at one level, and how much of that replay sat on the rail.
public struct InputLevelOutcome: Sendable, Equatable {
    public let level: InputLevel
    public let rate: WordErrorRate
    /// The share of clipped samples, as ``CaptureQuality`` counts them for the recording.
    public let clippedFraction: Double

    public init(level: InputLevel, rate: WordErrorRate, clippedFraction: Double) {
        self.level = level
        self.rate = rate
        self.clippedFraction = clippedFraction
    }
}

/// Pooled rates per level over a group of passages, each level paired against the unclipped full-scale one.
public struct InputLevelTable: Sendable, Equatable {
    /// The level every other is compared with: as loud as the clip goes with nothing clipped.
    public static let referenceLevel = InputLevel.peak(decibels: 0)

    /// One level, pooled over every passage replayed at it.
    public struct Row: Sendable, Equatable {
        public let level: InputLevel
        public let passages: Int
        public let referenceWords: Int
        public let errors: Int
        public let insertions: Int
        public let meanClippedFraction: Double
        /// Pooled word error rate minus the reference level's, a paired 95% interval; `nil` if unpaired.
        public let change: ClosedRange<Double>?

        public var wordErrorRate: Double { rate(errors) }
        public var insertionRate: Double { rate(insertions) }

        /// Whether this level is worse than the reference by more than resampling explains.
        public var isMeasurablyWorse: Bool { (change?.lowerBound ?? 0) > 0 }

        private func rate(_ count: Int) -> Double {
            referenceWords > 0 ? Double(count) / Double(referenceWords) : 0
        }
    }

    /// One row per level, in the order the levels first appear.
    public let rows: [Row]

    /// Pools `passages`, each one passage's outcomes across the levels it was replayed at.
    public init(passages: [[InputLevelOutcome]]) {
        var levels: [InputLevel] = []
        for outcome in passages.joined() where !levels.contains(outcome.level) {
            levels.append(outcome.level)
        }
        rows = levels.map { level in
            let scored = passages.compactMap { $0.first { $0.level == level } }
            let pairs = passages.compactMap { passage -> PairedBootstrap.Pair? in
                guard level != Self.referenceLevel,
                    let before = passage.first(where: { $0.level == Self.referenceLevel }),
                    let after = passage.first(where: { $0.level == level })
                else { return nil }
                return PairedBootstrap.Pair(
                    errorsBefore: before.rate.errors, wordsBefore: before.rate.referenceWordCount,
                    errorsAfter: after.rate.errors, wordsAfter: after.rate.referenceWordCount)
            }
            return Row(
                level: level,
                passages: scored.count,
                referenceWords: scored.reduce(0) { $0 + $1.rate.referenceWordCount },
                errors: scored.reduce(0) { $0 + $1.rate.errors },
                insertions: scored.reduce(0) { $0 + $1.rate.insertions },
                meanClippedFraction: scored.isEmpty
                    ? 0 : scored.reduce(0) { $0 + $1.clippedFraction } / Double(scored.count),
                change: PairedBootstrap.standard.estimate(pairs)?.interval)
        }
    }
}
