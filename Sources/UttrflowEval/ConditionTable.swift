// Word error rate per audio condition, each condition paired against one reference condition.
public import UttrflowCore

/// Pooled rates per condition over a group of passages, each one replayed under several conditions.
public struct ConditionTable<Condition: Equatable & Sendable>: Sendable, Equatable {
    /// What one passage scored under one condition.
    public struct Outcome: Sendable, Equatable {
        public let condition: Condition
        public let rate: WordErrorRate

        public init(condition: Condition, rate: WordErrorRate) {
            self.condition = condition
            self.rate = rate
        }
    }

    /// One condition, pooled over every passage replayed under it.
    public struct Row: Sendable, Equatable {
        public let condition: Condition
        public let passages: Int
        public let referenceWords: Int
        public let errors: Int
        public let insertions: Int
        /// Pooled word error rate minus the reference condition's, a paired 95% interval; `nil` if unpaired.
        public let change: ClosedRange<Double>?

        public var wordErrorRate: Double { rate(errors) }
        public var insertionRate: Double { rate(insertions) }

        /// Whether this condition is worse than the reference by more than resampling explains.
        public var isMeasurablyWorse: Bool { (change?.lowerBound ?? 0) > 0 }

        private func rate(_ count: Int) -> Double {
            referenceWords > 0 ? Double(count) / Double(referenceWords) : 0
        }
    }

    /// The condition every other is compared with.
    public let reference: Condition
    /// One row per condition, in the order the conditions first appear.
    public let rows: [Row]

    /// Pools `passages`, each one passage's outcomes across the conditions replayed for it.
    public init(passages: [[Outcome]], reference: Condition) {
        self.reference = reference
        var conditions: [Condition] = []
        for outcome in passages.joined() where !conditions.contains(outcome.condition) {
            conditions.append(outcome.condition)
        }
        rows = conditions.map { condition in
            let scored = passages.compactMap { $0.first { $0.condition == condition } }
            let pairs = passages.compactMap { passage -> PairedBootstrap.Pair? in
                guard condition != reference,
                    let before = passage.first(where: { $0.condition == reference }),
                    let after = passage.first(where: { $0.condition == condition })
                else { return nil }
                return PairedBootstrap.Pair(
                    errorsBefore: before.rate.errors, wordsBefore: before.rate.referenceWordCount,
                    errorsAfter: after.rate.errors, wordsAfter: after.rate.referenceWordCount)
            }
            return Row(
                condition: condition,
                passages: scored.count,
                referenceWords: scored.reduce(0) { $0 + $1.rate.referenceWordCount },
                errors: scored.reduce(0) { $0 + $1.rate.errors },
                insertions: scored.reduce(0) { $0 + $1.rate.insertions },
                change: PairedBootstrap.standard.estimate(pairs)?.interval)
        }
    }

    /// The reference condition's row, if any passage was scored under it.
    public var referenceRow: Row? { rows.first { $0.condition == reference } }
}
