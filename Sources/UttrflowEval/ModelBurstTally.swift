// Tallies a burst probe of the clean-up model: how often a request was throttled, and from which piece.
public import UttrflowCore

/// The outcome of every request in a burst probe, and the rate-limit figures the probe reports.
public struct ModelBurstTally: Sendable, Equatable {
    /// One request: its burst, its place in that burst, how long it took, and why it failed if it did.
    public struct Request: Sendable, Equatable {
        public let burst: Int
        public let piece: Int
        public let duration: Duration
        public let failure: ModelFailureClass?

        public init(burst: Int, piece: Int, duration: Duration, failure: ModelFailureClass?) {
            self.burst = burst
            self.piece = piece
            self.duration = duration
            self.failure = failure
        }
    }

    public private(set) var requests: [Request] = []

    public init() {}

    /// Records one request's outcome.
    public mutating func record(_ request: Request) {
        requests.append(request)
    }

    /// Requests the system throttled or refused as concurrent.
    public var rateLimited: Int {
        requests.count { $0.failure == .rateLimited }
    }

    /// Throttled requests per 1,000 sent, or `nil` when none were sent.
    public var rateLimitedPerThousand: Double? {
        requests.isEmpty ? nil : Double(rateLimited) * 1_000 / Double(requests.count)
    }

    /// The lowest place in a burst, counted from 1, at which any request was throttled.
    public var firstThrottledPiece: Int? {
        requests.filter { $0.failure == .rateLimited }.map(\.piece).min()
    }

    /// How many requests failed for each class, rate limits included.
    public var failuresByClass: [ModelFailureClass: Int] {
        requests.compactMap(\.failure).reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
