// How the tidy route ended for recent pieces, counted per engine and never quoting a word.

/// How the router's route ended for one piece, in closed names only.
public struct TidyOutcome: Sendable, Equatable {
    /// The engine whose answer was kept, or `nil` when every engine on the route gave up.
    public let finishedBy: TransformerKind?
    public let refusals: [Refusal]
    public let failures: [Failure]
    public let unavailable: [Unavailable]

    /// An engine's answer thrown away by a guard.
    public struct Refusal: Sendable, Equatable {
        public let engine: TransformerKind
        public let kind: RefusalKind
    }

    /// An engine that ran and gave no answer.
    public struct Failure: Sendable, Equatable {
        public let engine: TransformerKind
        public let failureClass: ModelFailureClass
    }

    /// An engine stepped around before it ran.
    public struct Unavailable: Sendable, Equatable {
        public let engine: TransformerKind
        public let reason: TidyTally.UnavailableReason
    }

    public init(
        finishedBy: TransformerKind?, refusals: [Refusal] = [], failures: [Failure] = [],
        unavailable: [Unavailable] = []
    ) {
        self.finishedBy = finishedBy
        self.refusals = refusals
        self.failures = failures
        self.unavailable = unavailable
    }

    /// The outcome a router's record describes; an engine name this build does not know is dropped.
    public init(finishedBy: TransformerKind?, record: CleaningRecord?) {
        self.init(
            finishedBy: finishedBy,
            refusals: (record?.refusals ?? []).compactMap { refusal in
                TransformerKind(rawValue: refusal.engine).map { Refusal(engine: $0, kind: refusal.kind) }
            },
            failures: (record?.engineFailures ?? []).compactMap { failure in
                TransformerKind(rawValue: failure.engine).map {
                    Failure(engine: $0, failureClass: failure.failureClass)
                }
            },
            unavailable: (record?.unavailableEngines ?? []).compactMap { skipped in
                TransformerKind(rawValue: skipped.engine).map {
                    Unavailable(engine: $0, reason: TidyTally.UnavailableReason(skipped.reason))
                }
            })
    }
}

/// The last pieces' tidy outcomes, the one count every consumer reads. See `Docs/diagnostics-export.md`.
public struct TidyTally: Sendable, Equatable {
    /// How many pieces the window keeps.
    public static let capacity = 200

    /// Why an engine was skipped, closed: the free-text reason is folded into `other`.
    public enum UnavailableReason: String, Sendable, Equatable, CaseIterable {
        case appleIntelligenceDisabled, modelNotReady, deviceNotEligible, other

        public init(_ reason: TransformerUnavailableReason) {
            switch reason {
            case .appleIntelligenceDisabled: self = .appleIntelligenceDisabled
            case .modelNotReady: self = .modelNotReady
            case .deviceNotEligible: self = .deviceNotEligible
            case .other: self = .other
            }
        }
    }

    /// What one engine did across the window.
    public struct EngineCounts: Sendable, Equatable {
        public var accepted = 0
        public var refused: [RefusalKind: Int] = [:]
        public var failed: [ModelFailureClass: Int] = [:]
        public var unavailable: [UnavailableReason: Int] = [:]

        public init() {}
    }

    /// Oldest first.
    public private(set) var outcomes: [TidyOutcome] = []

    public init() {}

    /// Keeps `outcome`, dropping the oldest beyond ``capacity``.
    public mutating func add(_ outcome: TidyOutcome) {
        outcomes.append(outcome)
        if outcomes.count > Self.capacity { outcomes.removeFirst(outcomes.count - Self.capacity) }
    }

    /// How many pieces no engine finished.
    public var untidied: Int { outcomes.filter { $0.finishedBy == nil }.count }

    /// Every engine's counts over the window.
    public var counts: [TransformerKind: EngineCounts] {
        var counts: [TransformerKind: EngineCounts] = [:]
        for outcome in outcomes {
            if let engine = outcome.finishedBy { counts[engine, default: .init()].accepted += 1 }
            for refusal in outcome.refusals {
                counts[refusal.engine, default: .init()].refused[refusal.kind, default: 0] += 1
            }
            for failure in outcome.failures {
                counts[failure.engine, default: .init()].failed[failure.failureClass, default: 0] += 1
            }
            for skipped in outcome.unavailable {
                counts[skipped.engine, default: .init()].unavailable[skipped.reason, default: 0] += 1
            }
        }
        return counts
    }

    /// One entry per engine, then the untidied pieces: a closed name and its counts, so the text may leave this Mac.
    public var entries: [(name: String, counts: String)] {
        let counts = counts
        let engines = TransformerKind.allCases.filter { counts[$0] != nil }
        return engines.compactMap { engine in
            guard let count = counts[engine] else { return nil }
            var parts = ["accepted \(count.accepted)"]
            parts += Self.listed("refused", count.refused, RefusalKind.allCases)
            parts += Self.listed("failed", count.failed, ModelFailureClass.allCases)
            parts += Self.listed("skipped", count.unavailable, UnavailableReason.allCases)
            return (engine.rawValue, parts.joined(separator: ", "))
        } + (untidied == 0 ? [] : [(TransformerKind.untidied.rawValue, "\(untidied)")])
    }

    /// The entries as report lines.
    public var lines: [String] { entries.map { "\($0.name): \($0.counts)" } }

    private static func listed<Key: RawRepresentable<String>>(
        _ verb: String, _ counts: [Key: Int], _ order: [Key]
    ) -> [String] {
        order.compactMap { key in counts[key].map { "\(verb) \(key.rawValue) \($0)" } }
    }
}

/// Where the router reports each piece's outcome.
public protocol TidyOutcomeRecording: Sendable {
    func record(_ outcome: TidyOutcome) async
}

/// Discards every outcome, for callers with no tally.
public struct NoOpTidyOutcomeRecorder: TidyOutcomeRecording {
    public init() {}
    public func record(_ outcome: TidyOutcome) async {}
}
