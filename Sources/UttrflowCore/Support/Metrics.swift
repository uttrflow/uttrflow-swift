// Per-stage timing of a dictation: the stages, a recorder protocol, a tally and the latency summary.

/// A stage of the speak-to-inserted journey, declared in running order because reports iterate `allCases`.
public enum PipelineStage: String, Sendable, Equatable, CaseIterable, Codable {
    /// Microphone audio arriving.
    case capture
    /// Speech becoming text.
    case transcription
    /// The dictionary, consulted on what was heard before the tidier rewrites it.
    case correction
    /// The tidier rewriting the transcript.
    case transformation
    /// Snippets, expanded once the tidier has settled the sentence boundaries.
    case expansion
    /// Text reaching the focused field.
    case insertion
}

/// How long one stage took, and whether it worked.
public struct StageMeasurement: Sendable, Equatable {
    /// The stage measured.
    public let stage: PipelineStage
    /// How long it ran.
    public let duration: Duration
    /// Whether it returned rather than threw.
    public let succeeded: Bool

    /// A measurement of `stage`.
    public init(stage: PipelineStage, duration: Duration, succeeded: Bool) {
        self.stage = stage
        self.duration = duration
        self.succeeded = succeeded
    }
}

/// Collects timings and failure counts, which stay on the device and are never transmitted.
public protocol MetricsRecording: Sendable {
    /// Keeps one measurement.
    func record(_ measurement: StageMeasurement) async
}

/// A recorder that discards everything, for callers that do not care about timings.
public struct NoOpMetricsRecorder: MetricsRecording {
    /// A recorder with nothing to set up.
    public init() {}
    /// Discards the measurement.
    public func record(_ measurement: StageMeasurement) async {}
}

/// The one way every stage is timed, so none is left out of the numbers.
extension MetricsRecording {
    /// Times `operation` on the caller's actor, records success or failure, and passes the outcome through.
    public func measuring<Success, Failure: Error>(
        _ stage: PipelineStage,
        clock: some Clock<Duration>,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws(Failure) -> Success
    ) async throws(Failure) -> Success {
        let start = clock.now
        do {
            let value = try await operation()
            await record(.init(stage: stage, duration: start.duration(to: clock.now), succeeded: true))
            return value
        } catch {
            await record(.init(stage: stage, duration: start.duration(to: clock.now), succeeded: false))
            throw error
        }
    }
}

/// Adds up every measurement of a stage, so a dictation done in pieces reports one figure per stage.
public actor StageTally: MetricsRecording {
    /// The running total per stage.
    private var totals: [PipelineStage: StageMeasurement] = [:]

    /// An empty tally.
    public init() {}

    /// Adds the duration to the stage's total; the total succeeds only if every piece did.
    public func record(_ measurement: StageMeasurement) {
        let stage = measurement.stage
        let previous = totals[stage]
        totals[stage] = StageMeasurement(
            stage: stage,
            duration: (previous?.duration ?? .zero) + measurement.duration,
            succeeded: (previous?.succeeded ?? true) && measurement.succeeded)
    }

    /// One total per stage that was measured, in the order the journey runs.
    public var measurements: [StageMeasurement] {
        PipelineStage.allCases.compactMap { totals[$0] }
    }

    /// Hands every total on as a single measurement.
    public func report(to recorder: any MetricsRecording) async {
        for measurement in measurements { await recorder.record(measurement) }
    }
}

extension Duration {
    /// Seconds as a `Double`, for ratios and printing.
    public var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// What a set of measurements says about one stage; the median, not the mean, so a cold load cannot skew it.
public struct StageLatency: Sendable, Equatable {
    /// The stage summarised.
    public let stage: PipelineStage
    /// The median; with an even count the upper of the two, so it stays an observed duration.
    public let typical: Duration
    /// The longest sample.
    public let slowest: Duration
    /// How many measurements went into this.
    public let samples: Int
    /// How many of those samples were failures; a stage can be fast because it gave up.
    public let failures: Int

    /// A summary from figures already computed.
    public init(
        stage: PipelineStage, typical: Duration, slowest: Duration, samples: Int, failures: Int
    ) {
        self.stage = stage
        self.typical = typical
        self.slowest = slowest
        self.samples = samples
        self.failures = failures
    }

    /// Summarises one stage, or `nil` when nothing measured it; a zero would read as "instant".
    public static func summarise(
        _ measurements: [StageMeasurement], stage: PipelineStage
    ) -> StageLatency? {
        let forStage = measurements.filter { $0.stage == stage }
        let durations = forStage.map(\.duration).sorted()
        guard let slowest = durations.last else { return nil }
        return StageLatency(
            stage: stage,
            typical: durations[durations.count / 2],
            slowest: slowest,
            samples: durations.count,
            failures: forStage.count { !$0.succeeded }
        )
    }

    /// One entry per measured stage, in running order, driven by ``PipelineStage/allCases``.
    public static func summarise(_ measurements: [StageMeasurement]) -> [StageLatency] {
        PipelineStage.allCases.compactMap { summarise(measurements, stage: $0) }
    }

    /// The stages nothing measured, so a report can name them rather than imply they cost nothing.
    public static func unmeasuredStages(in measurements: [StageMeasurement]) -> [PipelineStage] {
        PipelineStage.allCases.filter { summarise(measurements, stage: $0) == nil }
    }
}
