// A speaker's own pause rhythm in one dictation, and the rank a new gap takes within it.
import UttrflowCore

/// The gaps heard so far from one speaker, with the detector's floor taken off, and where a new gap ranks among them.
public struct SpeakerRhythm: Sendable, Equatable {
    /// What the audio measure reports for no pause at all, in milliseconds, from the zero-pause row of `Docs/pause-timing.md`.
    public static let detectorFloor = 40.0
    /// The least spread, in milliseconds, so near-identical gaps do not make every other gap extreme.
    static let leastSpread = 20.0
    /// Gaps heard before a rank is given.
    public static let warmUp = 5
    /// Scales the median absolute deviation to the standard deviation of a normal spread.
    private static let spreadScale = 1.4826

    private var gaps: [Double] = []

    public init() {}

    /// Adds a gap measured in milliseconds, less the detector's floor and never below zero.
    public mutating func add(_ milliseconds: Double) {
        gaps.append(max(0, milliseconds - Self.detectorFloor))
    }

    /// The median of the gaps heard; zero before the first.
    public var median: Double { PauseTiming.median(gaps) }

    /// The scaled median absolute deviation of the gaps heard, never below the least spread.
    public var spread: Double {
        max(Self.leastSpread, Self.spreadScale * PauseTiming.median(gaps.map { abs($0 - median) }))
    }

    /// How many spreads `milliseconds` lies above the median; `nil` until the warm-up count of gaps is heard.
    public func rank(of milliseconds: Double) -> Double? {
        guard gaps.count >= Self.warmUp else { return nil }
        return (max(0, milliseconds - Self.detectorFloor) - median) / spread
    }
}

/// One gap measured from a clip, and whether the speaker meant it as a break.
public struct GapObservation: Sendable, Equatable {
    public let milliseconds: Double
    public let isBreak: Bool

    public init(milliseconds: Double, isBreak: Bool) {
        self.milliseconds = milliseconds
        self.isBreak = isBreak
    }
}

/// How a gap is judged a break: against a fixed length, or by its rank among the speaker's own gaps.
public enum PauseRule: Sendable, Equatable {
    case fixed(milliseconds: Double)
    case relative(spreads: Double)

    /// Reads `gaps` in the order they were heard, each judged with only the gaps up to and including it.
    public func score(_ gaps: [GapObservation]) -> BreakScore {
        var rhythm = SpeakerRhythm()
        var score = BreakScore()
        for gap in gaps {
            rhythm.add(gap.milliseconds)
            score.record(called: calls(gap.milliseconds, rhythm), truth: gap.isBreak)
        }
        return score
    }

    private func calls(_ milliseconds: Double, _ rhythm: SpeakerRhythm) -> Bool {
        switch self {
        case .fixed(let length): return milliseconds >= length
        case .relative(let spreads): return (rhythm.rank(of: milliseconds) ?? -.infinity) >= spreads
        }
    }
}

/// Break calls counted against the breaks the speaker meant.
public struct BreakScore: Sendable, Equatable {
    public private(set) var truePositives = 0
    public private(set) var falsePositives = 0
    public private(set) var falseNegatives = 0

    public init() {}

    mutating func record(called: Bool, truth: Bool) {
        switch (called, truth) {
        case (true, true): truePositives += 1
        case (true, false): falsePositives += 1
        case (false, true): falseNegatives += 1
        case (false, false): break
        }
    }

    /// Share of called breaks that were meant; `nil` when none was called.
    public var precision: Double? {
        let called = truePositives + falsePositives
        return called == 0 ? nil : Double(truePositives) / Double(called)
    }

    /// Share of meant breaks that were called; `nil` when none was meant.
    public var recall: Double? {
        let meant = truePositives + falseNegatives
        return meant == 0 ? nil : Double(truePositives) / Double(meant)
    }

    /// Harmonic mean of precision and recall; zero when either is missing or both are zero.
    public var f1: Double {
        guard let precision, let recall, precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    public static func + (left: Self, right: Self) -> Self {
        var sum = Self()
        sum.truePositives = left.truePositives + right.truePositives
        sum.falsePositives = left.falsePositives + right.falsePositives
        sum.falseNegatives = left.falseNegatives + right.falseNegatives
        return sum
    }
}

/// The mean change between paired scores and the half-width of its 95% interval.
public struct PairedChange: Sendable, Equatable {
    public let mean: Double
    public let bound: Double

    /// Two-sided 95% normal quantile.
    private static let quantile = 1.96

    /// `after` less `before`, pair by pair; both lists must be the same length.
    public init(before: [Double], after: [Double]) {
        let changes = zip(after, before).map { $0 - $1 }
        let count = Double(changes.count)
        let average = changes.isEmpty ? 0 : changes.reduce(0, +) / count
        let squares = changes.map { ($0 - average) * ($0 - average) }.reduce(0, +)
        let variance = changes.count < 2 ? 0 : squares / (count - 1)
        mean = average
        bound = changes.count < 2 ? .infinity : Self.quantile * (variance / count).squareRoot()
    }

    /// Whether the change is positive by more than its bound.
    public var isGain: Bool { mean > bound }
}
