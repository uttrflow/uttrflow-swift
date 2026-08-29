/// A stage of the speak-to-inserted journey, measured independently so a regression
/// can be attributed rather than merely observed.
///
/// Declared in the order the journey runs, because ``CaseIterable/allCases`` is what
/// every report orders its rows by — so a stage put in the wrong place here draws a
/// journey that never happened.
///
/// Every stage the pipeline runs has a case, including the two that usually change
/// nothing. Consulting a dictionary that matches no word still costs the dictation the
/// consultation, and a stage left out of this enumeration is time the totals cannot see
/// — which makes the fast path look faster than it is.
public enum PipelineStage: String, Sendable, Equatable, CaseIterable, Codable {
    case capture
    case transcription
    /// The dictionary, consulted on what was heard — before the tidier rewrites it.
    case correction
    case transformation
    /// Snippets, expanded once the tidier has settled the sentence boundaries.
    case expansion
    case insertion
}

/// How long one stage took, and whether it worked.
public struct StageMeasurement: Sendable, Equatable {
    public let stage: PipelineStage
    public let duration: Duration
    public let succeeded: Bool

    public init(stage: PipelineStage, duration: Duration, succeeded: Bool) {
        self.stage = stage
        self.duration = duration
        self.succeeded = succeeded
    }
}

/// Collects timings and failure counts.
///
/// V1 keeps everything on the device: §22's numbers exist to be read in the debug
/// panel and by the evaluation harness, and are never transmitted.
public protocol MetricsRecording: Sendable {
    func record(_ measurement: StageMeasurement) async
}

/// A recorder that discards everything, for callers that do not care about timings.
public struct NoOpMetricsRecorder: MetricsRecording {
    public init() {}
    public func record(_ measurement: StageMeasurement) async {}
}

extension MetricsRecording {
    /// Times `operation`, records the result — success or failure — and passes the
    /// outcome straight through.
    ///
    /// Every stage is measured by calling this, so no stage can be accidentally left
    /// out of the latency numbers and no stage duplicates timing code.
    /// - Parameters:
    ///   - stage: Which part of the journey is being timed.
    ///   - clock: The clock to measure against.
    ///   - isolation: Inherits the caller's actor, so a stage that touches actor state
    ///     is timed in place rather than being sent across an isolation boundary.
    ///   - operation: The work to time.
    /// - Returns: Whatever `operation` returned.
    /// - Throws: Rethrows whatever `operation` threw, after recording the failure.
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

extension Duration {
    /// Seconds as a `Double`, for arithmetic and for printing.
    ///
    /// `components` is exact and unwieldy, and everything that reads a duration here is
    /// either taking a ratio or putting two decimal places on it — neither needs
    /// attosecond fidelity. Here rather than beside each caller because two identical
    /// private copies of this had already appeared.
    public var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// What a set of measurements says about one stage.
///
/// The typical is the median rather than the mean: one pathological dictation — a model
/// loading for the first time, a machine that went to sleep — drags a mean somewhere no
/// real dictation has ever been, and the figure is there to answer "what is this usually
/// like".
public struct StageLatency: Sendable, Equatable {
    public let stage: PipelineStage
    /// The median. With an even number of samples this is the upper of the two, which
    /// keeps the answer an observed duration rather than an average of two.
    public let typical: Duration
    public let slowest: Duration
    public let samples: Int
    /// How many of those samples were failures. A stage can be fast because it gave up.
    public let failures: Int

    public init(
        stage: PipelineStage, typical: Duration, slowest: Duration, samples: Int, failures: Int
    ) {
        self.stage = stage
        self.typical = typical
        self.slowest = slowest
        self.samples = samples
        self.failures = failures
    }

    /// Summarises one stage, or `nil` when nothing measured it.
    ///
    /// `nil` rather than a zero-valued summary, and that distinction is the point: the
    /// evaluation harness reads audio off disk so it never times capture, and a zero
    /// would read as "instant" rather than "not measured". Callers are expected to name
    /// the unmeasured stage instead of drawing it.
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

    /// One entry per stage that was measured, in the order the journey runs.
    ///
    /// Driven by ``PipelineStage/allCases``, so a stage added to the pipeline appears
    /// here the moment something times it, rather than when somebody remembers to add
    /// it to a list.
    public static func summarise(_ measurements: [StageMeasurement]) -> [StageLatency] {
        PipelineStage.allCases.compactMap { summarise(measurements, stage: $0) }
    }

    /// The stages nothing measured, so a report can name them rather than imply they
    /// were free.
    public static func unmeasuredStages(in measurements: [StageMeasurement]) -> [PipelineStage] {
        PipelineStage.allCases.filter { summarise(measurements, stage: $0) == nil }
    }
}
