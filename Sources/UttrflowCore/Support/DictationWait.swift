// Where one dictation's wait after key-up went, and the log that names the cause of each slow one.

/// One dictation's wait from key-up to the words placed, split by the causes that can make it slow.
public struct DictationWait: Sendable, Equatable {
    /// The wait a dictation is expected to keep to: the measured spoken-reply p95. See `Docs/performance-dictation.md`.
    public static let target: Duration = .seconds(4)

    /// From key-up until the words were placed.
    public let wait: Duration
    /// The time each cause took inside that wait; ``SlowDictationCause/other`` is what none accounts for.
    public let spent: [SlowDictationCause: Duration]

    /// A wait with its time already split.
    public init(wait: Duration, spent: [SlowDictationCause: Duration]) {
        self.wait = wait
        self.spent = spent
    }

    /// Splits `wait` using the stages timed after key-up, the pieces' decode effort and the screen reads.
    public init(
        wait: Duration, stages: [StageMeasurement], decoding: [DecodeEffort], screenReads: Duration
    ) {
        var spent: [SlowDictationCause: Duration] = [:]
        spent[.fallbackDecode] = .seconds(decoding.reduce(0) { $0 + $1.fallbackSeconds })
        spent[.contextRead] = screenReads
        for stage in stages {
            switch stage.stage {
            case .transformation where !stage.succeeded: spent[.tidyTimeout] = stage.duration
            case .insertion: spent[.insertionConfirmation] = stage.duration
            default: break
            }
        }
        let named = spent.values.reduce(Duration.zero, +)
        spent[.other] = max(.zero, wait - named)
        self.init(wait: wait, spent: spent.filter { $0.value > .zero })
    }
}

/// A dictation's wait and the one cause named for it; `cause` is `nil` when the wait kept to the target.
public struct TimedWait: Sendable, Equatable {
    /// The wait and its split.
    public let wait: DictationWait
    /// Why it ran past the target, if it did.
    public let cause: SlowDictationCause?

    /// A wait already classified.
    public init(wait: DictationWait, cause: SlowDictationCause?) {
        self.wait = wait
        self.cause = cause
    }
}

/// The last dictations' waits, which give each cause its usual cost so the next slow one can be named.
public struct DictationWaits: Sendable, Equatable {
    /// How many dictations are kept, which is how many Diagnostics reports on.
    public static let capacity = 100

    /// Oldest first.
    public private(set) var timed: [TimedWait]

    /// A log holding `timed`, trimmed to the newest ``capacity``.
    public init(_ timed: [TimedWait] = []) {
        self.timed = Array(timed.suffix(Self.capacity))
    }

    /// Names the cause of `wait` against the median of each cause over the kept dictations, then keeps it.
    @discardableResult
    public mutating func classify(_ wait: DictationWait) -> TimedWait {
        var typical: [SlowDictationCause: Duration] = [:]
        if !timed.isEmpty {
            for cause in SlowDictationCause.allCases {
                let costs = timed.map { $0.wait.spent[cause] ?? .zero }.sorted()
                typical[cause] = costs[costs.count / 2]
            }
        }
        let classified = TimedWait(
            wait: wait,
            cause: SlowDictationCause.of(
                wait: wait.wait, target: DictationWait.target, spent: wait.spent, typical: typical))
        keep(classified)
        return classified
    }

    /// Keeps an already classified wait, dropping the oldest once full.
    public mutating func keep(_ classified: TimedWait) {
        timed.append(classified)
        if timed.count > Self.capacity { timed.removeFirst(timed.count - Self.capacity) }
    }

    /// The median wait; with an even count the upper of the two, so it stays an observed wait.
    public var typical: Duration? { percentile(50) }

    /// The 95th-percentile wait, by nearest rank.
    public var tail: Duration? { percentile(95) }

    /// How many kept dictations each cause was named for, leaving out causes never named.
    public var causeCounts: [SlowDictationCause: Int] {
        timed.reduce(into: [:]) { counts, entry in
            if let cause = entry.cause { counts[cause, default: 0] += 1 }
        }
    }

    private func percentile(_ percent: Int) -> Duration? {
        let waits = timed.map(\.wait.wait).sorted()
        guard !waits.isEmpty else { return nil }
        let rank = (percent * waits.count + 99) / 100
        return waits[min(waits.count - 1, max(0, percent == 50 ? waits.count / 2 : rank - 1))]
    }
}
