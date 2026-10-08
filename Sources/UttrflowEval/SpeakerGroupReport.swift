// Per-group error and decision rates over real speakers, with intervals that resample speakers rather than clips.
private import Foundation

/// Where a group's accent label comes from; the two kinds are never pooled into one row.
public enum AccentLabelKind: String, Sendable, Equatable, Comparable, CaseIterable {
    /// From the dataset's speaker metadata.
    case verified
    /// As the contributor described their own accent.
    case selfDescribed = "self-described"

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One clip's counts, carrying no audio and no words.
public struct SpeakerClip: Sendable, Equatable {
    public let speaker: String
    public let group: String
    public let label: AccentLabelKind
    public let errors: Int
    public let words: Int
    /// Correction decisions in the clip, and how many of them override a right word.
    public let decisions: Int
    public let falseOverrides: Int

    public init(
        speaker: String, group: String, label: AccentLabelKind, errors: Int, words: Int, decisions: Int = 0,
        falseOverrides: Int = 0
    ) {
        self.speaker = speaker
        self.group = group
        self.label = label
        self.errors = errors
        self.words = words
        self.decisions = decisions
        self.falseOverrides = falseOverrides
    }
}

/// The report Docs/eval-methodology.md "Real-speaker accent slices" specifies.
public struct SpeakerGroupReport: Sendable, Equatable {
    /// What a decision rate may claim: a bound, or nothing because the sample is too small.
    public enum DecisionClaim: Sendable, Equatable {
        case insufficientEvidence(needed: Int)
        case upperBound(Double)
    }

    public struct Row: Sendable, Equatable {
        public let group: String
        public let label: AccentLabelKind
        public let speakers: Int
        public let words: Int
        public let decisions: Int
        public let errorRate: Double
        /// Nil under two speakers, where there is no speaker spread to resample.
        public let interval: ClosedRange<Double>?
        public let minimumDetectableDifference: Double?
        public let decisionClaim: DecisionClaim
    }

    public struct Difference: Sendable, Equatable {
        public let first: String
        public let second: String
        public let label: AccentLabelKind
        public let interval: ClosedRange<Double>
        public let minimumDetectableDifference: Double
        /// True only when the interval excludes zero.
        public var isDetected: Bool { interval.lowerBound > 0 || interval.upperBound < 0 }
    }

    public let rows: [Row]
    public let differences: [Difference]

    /// Builds the report; `decisionBound` is the false-override rate a row must be able to bound, by the 3/n rule.
    public init(clips: [SpeakerClip], decisionBound: Double = 0.001) {
        self.init(clips: clips, decisionBound: decisionBound, bootstrap: .standard)
    }

    init(clips: [SpeakerClip], decisionBound: Double, bootstrap: PairedBootstrap) {
        let grouped = Dictionary(grouping: clips) { GroupKey(group: $0.group, label: $0.label) }
        let keys = grouped.keys.sorted()
        let speakersByKey = keys.map { key in Self.speakers(grouped[key] ?? []) }
        let needed = Int((3 / decisionBound).rounded(.up))
        var generator = SplitMix(state: bootstrap.seed)
        var rows: [Row] = []
        for (key, speakers) in zip(keys, speakersByKey) {
            let total = speakers.reduce(Counts.zero, +)
            let draws = Self.resampledRates(speakers, bootstrap.resamples, &generator)
            let estimate = speakers.count >= 2 ? Self.interval(draws, bootstrap) : nil
            rows.append(
                Row(
                    group: key.group, label: key.label, speakers: speakers.count, words: total.words,
                    decisions: total.decisions, errorRate: total.errorRate, interval: estimate?.interval,
                    minimumDetectableDifference: estimate?.reach,
                    decisionClaim: Self.decisionClaim(speakers, total, needed, bootstrap, &generator)))
        }
        var differences: [Difference] = []
        for first in keys.indices {
            for second in keys.indices where second > first && keys[first].label == keys[second].label {
                let left = speakersByKey[first]
                let right = speakersByKey[second]
                guard left.count >= 2, right.count >= 2 else { continue }
                let leftDraws = Self.resampledRates(left, bootstrap.resamples, &generator)
                let rightDraws = Self.resampledRates(right, bootstrap.resamples, &generator)
                let deltas = zip(leftDraws, rightDraws).map { $0 - $1 }
                guard let estimate = Self.interval(deltas, bootstrap) else { continue }
                differences.append(
                    Difference(
                        first: keys[first].group, second: keys[second].group, label: keys[first].label,
                        interval: estimate.interval, minimumDetectableDifference: estimate.reach))
            }
        }
        self.rows = rows
        self.differences = differences
    }

    /// The printed report: one line per group, then one per same-label pair.
    public var lines: [String] {
        func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
        func points(_ value: Double) -> String { String(format: "%+.1f", value * 100) }
        var lines = ["group\tlabel\tspeakers\twords\tdecisions\tWER\tinterval\tMDD\tfalse override"]
        for row in rows {
            let interval = row.interval.map { "\(points($0.lowerBound))..\(points($0.upperBound))" }
            let rate = row.interval == nil ? "insufficient evidence" : percent(row.errorRate)
            let claim: String
            switch row.decisionClaim {
            case .insufficientEvidence(let needed):
                claim = "insufficient evidence (needs \(needed) decisions)"
            case .upperBound(let bound): claim = "<= \(percent(bound))"
            }
            lines.append(
                [
                    row.group, row.label.rawValue, "\(row.speakers)", "\(row.words)", "\(row.decisions)",
                    rate,
                    interval ?? "-", row.minimumDetectableDifference.map(points) ?? "-", claim,
                ].joined(separator: "\t"))
        }
        for difference in differences {
            let interval =
                "\(points(difference.interval.lowerBound))..\(points(difference.interval.upperBound))"
            let verdict =
                difference.isDetected
                ? "difference detected"
                : "no difference detectable at this sample (MDD \(points(difference.minimumDetectableDifference)))"
            lines.append(
                "\(difference.first) - \(difference.second) [\(difference.label.rawValue)]: \(interval) \(verdict)"
            )
        }
        return lines
    }

    private struct GroupKey: Hashable, Comparable {
        let group: String
        let label: AccentLabelKind

        static func < (lhs: Self, rhs: Self) -> Bool { (lhs.label, lhs.group) < (rhs.label, rhs.group) }
    }

    private struct Counts {
        var errors = 0
        var words = 0
        var decisions = 0
        var falseOverrides = 0

        static let zero = Counts()
        var errorRate: Double { words > 0 ? Double(errors) / Double(words) : 0 }
        var overrideRate: Double { decisions > 0 ? Double(falseOverrides) / Double(decisions) : 0 }

        static func + (lhs: Self, rhs: Self) -> Self {
            Counts(
                errors: lhs.errors + rhs.errors, words: lhs.words + rhs.words,
                decisions: lhs.decisions + rhs.decisions,
                falseOverrides: lhs.falseOverrides + rhs.falseOverrides)
        }
    }

    /// Every clip of a speaker summed into one unit, so a resample draws the speaker with all their clips.
    private static func speakers(_ clips: [SpeakerClip]) -> [Counts] {
        let bySpeaker = Dictionary(grouping: clips, by: \.speaker)
        return bySpeaker.keys.sorted().map { speaker in
            (bySpeaker[speaker] ?? []).reduce(Counts.zero) {
                $0
                    + Counts(
                        errors: $1.errors, words: $1.words, decisions: $1.decisions,
                        falseOverrides: $1.falseOverrides)
            }
        }
    }

    private static func resampled(
        _ speakers: [Counts], _ resamples: Int, _ generator: inout SplitMix
    ) -> [Counts] {
        guard !speakers.isEmpty else { return [] }
        return (0..<resamples).map { _ in
            (0..<speakers.count).reduce(Counts.zero) { sum, _ in
                sum + speakers[Int(generator.next() % UInt64(speakers.count))]
            }
        }
    }

    private static func resampledRates(
        _ speakers: [Counts], _ resamples: Int, _ generator: inout SplitMix
    ) -> [Double] {
        resampled(speakers, resamples, &generator).map(\.errorRate)
    }

    private static func interval(
        _ draws: [Double], _ bootstrap: PairedBootstrap
    ) -> (interval: ClosedRange<Double>, reach: Double)? {
        guard draws.count >= 2 else { return nil }
        let sorted = draws.sorted()
        let tail = (1 - bootstrap.confidence) / 2
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let spread = (sorted.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sorted.count)).squareRoot()
        let reach =
            PairedBootstrap.standardNormalQuantile(1 - tail)
            + PairedBootstrap.standardNormalQuantile(bootstrap.power)
        return (
            PairedBootstrap.quantile(sorted, tail)...PairedBootstrap.quantile(sorted, 1 - tail),
            reach * spread
        )
    }

    private static func decisionClaim(
        _ speakers: [Counts], _ total: Counts, _ needed: Int, _ bootstrap: PairedBootstrap,
        _ generator: inout SplitMix
    ) -> DecisionClaim {
        guard total.decisions >= needed, speakers.count >= 2 else {
            return .insufficientEvidence(needed: needed)
        }
        if total.falseOverrides == 0 { return .upperBound(3 / Double(total.decisions)) }
        let draws = resampled(speakers, bootstrap.resamples, &generator).map(\.overrideRate).sorted()
        return .upperBound(PairedBootstrap.quantile(draws, 1 - (1 - bootstrap.confidence) / 2))
    }
}
