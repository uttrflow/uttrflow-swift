// One engine's pass rate over another's on the same cases, with a paired-bootstrap interval.
import Foundation

/// How far a candidate's pass rate sits above a base's on paired cases. See Docs/bakeoff.md.
public struct PassRateLift: Sendable, Equatable {
    public let cases: Int
    public let basePassRate: Double
    public let candidatePassRate: Double
    /// The 95% interval of the lift; `nil` under two cases, where there is no spread to resample.
    public let interval: ClosedRange<Double>?

    public var lift: Double { candidatePassRate - basePassRate }

    /// Pairs `base[i]` with `candidate[i]`; a longer list's extra entries are not scored.
    public init(base: [Bool], candidate: [Bool]) {
        let paired = Array(zip(base, candidate))
        cases = paired.count
        basePassRate = Self.rate(paired.map(\.0))
        candidatePassRate = Self.rate(paired.map(\.1))
        let pairs = paired.map {
            PairedBootstrap.Pair(
                errorsBefore: $0.0 ? 0 : 1, wordsBefore: 1, errorsAfter: $0.1 ? 0 : 1, wordsAfter: 1)
        }
        // The bootstrap reports a change in error rate, which is the lift with its sign turned.
        interval = PairedBootstrap.standard.estimate(pairs).map {
            -$0.interval.upperBound...(-$0.interval.lowerBound)
        }
    }

    private static func rate(_ passed: [Bool]) -> Double {
        passed.isEmpty ? 0 : Double(passed.count(where: { $0 })) / Double(passed.count)
    }
}
