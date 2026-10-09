// Per-stage timing of a dictation: the stages, a recorder protocol, a tally and the latency summary.

/// A stage of the speak-to-inserted journey, declared in running order because reports iterate `allCases`.
public enum PipelineStage: String, Sendable, Equatable, CaseIterable, Codable {
    /// The microphone opening: the graph built, the tap installed, the engine started.
    case microphoneOpen
    /// From the shortcut going down until its first audio samples arrive.
    case keyDownToAudio
    /// Microphone audio arriving.
    case capture
    /// Waiting for the piece that was already being transcribed when the key came up.
    case drain
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
    /// The dictation that produced it, when recorded by a pipeline.
    public let generation: Int?

    /// A measurement of `stage`.
    public init(stage: PipelineStage, duration: Duration, succeeded: Bool, generation: Int? = nil) {
        self.stage = stage
        self.duration = duration
        self.succeeded = succeeded
        self.generation = generation
    }
}

/// Collects timings and failure counts, which stay on the device and are never transmitted.
public protocol MetricsRecording: Sendable {
    /// Keeps one measurement.
    func record(_ measurement: StageMeasurement) async

    /// Keeps what one piece cost the recogniser beyond a single decode.
    func recordDecoding(_ effort: DecodeEffort) async

    /// Keeps the decoder's own judgement of each segment of one piece, as numbers only.
    func recordReliability(_ segments: [SegmentReliability]) async

    /// Keeps the exact personal dictionary spellings in the last recogniser prompt, in memory only.
    func recordVocabularyPrompt(_ words: [String]) async

    /// Keeps what one recording sounded like, as aggregates only.
    func recordCaptureQuality(_ quality: CaptureQuality) async
    /// Records whether a piece's decode could be conditioned on the user's words.
    func recordConditioning(_ conditioning: DecodeConditioning) async
    /// Keeps what reading the screen cost one dictation, apart from the stages since reads overlap them.
    func recordScreenReads(_ reads: ScreenReadCost) async
    /// Keeps why the dictation's last screen read carried no field text, or `nil` when it did.
    func recordScreenText(_ unavailable: ContextUnavailableReason?) async
    /// Keeps one dictation's wait after key-up and the cause named for it.
    func recordWait(_ wait: TimedWait) async
}

/// How many times one dictation read the screen, and how long those reads took together.
public struct ScreenReadCost: Sendable, Equatable {
    /// The number of reads.
    public let reads: Int
    /// Their durations added together.
    public let duration: Duration

    /// A cost of `reads` reads taking `duration` in all.
    public init(reads: Int, duration: Duration) {
        self.reads = reads
        self.duration = duration
    }

    /// This cost with one more read of `elapsed`.
    public func adding(_ elapsed: Duration) -> ScreenReadCost {
        ScreenReadCost(reads: reads + 1, duration: duration + elapsed)
    }
}

extension MetricsRecording {
    /// Most recorders care only about timings, so reporting decode effort is optional.
    public func recordDecoding(_ effort: DecodeEffort) async {}

    /// Most recorders do not judge the recogniser's segments.
    public func recordReliability(_ segments: [SegmentReliability]) async {}

    /// Most recorders do not expose personal prompt contents.
    public func recordVocabularyPrompt(_ words: [String]) async {}

    /// Most recorders do not describe the audio.
    public func recordCaptureQuality(_ quality: CaptureQuality) async {}

    /// Most recorders do not track recogniser health.
    public func recordConditioning(_ conditioning: DecodeConditioning) async {}

    /// Most recorders do not track screen reads.
    public func recordScreenReads(_ reads: ScreenReadCost) async {}

    /// Most recorders do not track why the screen carried no text.
    public func recordScreenText(_ unavailable: ContextUnavailableReason?) async {}

    /// Most recorders do not track the wait after key-up.
    public func recordWait(_ wait: TimedWait) async {}
}

/// A recorder that discards everything, for callers that do not care about timings.
public struct NoOpMetricsRecorder: MetricsRecording {
    /// A recorder with nothing to set up.
    public init() {}
    /// Discards the measurement.
    public func record(_ measurement: StageMeasurement) async {}
}

/// Hands every measurement to each recorder in turn, for a pipeline that takes only one.
public struct MetricsFanOut: MetricsRecording {
    /// The recorders, in the order they are told.
    private let recorders: [any MetricsRecording]

    /// Tells every one of `recorders`, in order.
    public init(_ recorders: [any MetricsRecording]) {
        self.recorders = recorders
    }

    /// Passes the measurement to every recorder.
    public func record(_ measurement: StageMeasurement) async {
        for recorder in recorders { await recorder.record(measurement) }
    }

    /// Passes the decode effort to every recorder.
    public func recordDecoding(_ effort: DecodeEffort) async {
        for recorder in recorders { await recorder.recordDecoding(effort) }
    }

    /// Passes the segments' reliability to every recorder.
    public func recordReliability(_ segments: [SegmentReliability]) async {
        for recorder in recorders { await recorder.recordReliability(segments) }
    }

    /// Passes the in-memory prompt words to the recorders that expose local diagnostics.
    public func recordVocabularyPrompt(_ words: [String]) async {
        for recorder in recorders { await recorder.recordVocabularyPrompt(words) }
    }

    /// Passes the recording's quality to every recorder.
    public func recordCaptureQuality(_ quality: CaptureQuality) async {
        for recorder in recorders { await recorder.recordCaptureQuality(quality) }
    }

    public func recordConditioning(_ conditioning: DecodeConditioning) async {
        for recorder in recorders { await recorder.recordConditioning(conditioning) }
    }

    public func recordScreenReads(_ reads: ScreenReadCost) async {
        for recorder in recorders { await recorder.recordScreenReads(reads) }
    }

    public func recordScreenText(_ unavailable: ContextUnavailableReason?) async {
        for recorder in recorders { await recorder.recordScreenText(unavailable) }
    }

    public func recordWait(_ wait: TimedWait) async {
        for recorder in recorders { await recorder.recordWait(wait) }
    }
}

/// The one way every stage is timed, so none is left out of the numbers.
extension MetricsRecording {
    /// Times `operation` on the caller's actor, records success or failure, and passes the outcome through.
    public func measuring<Success, Failure: Error>(
        _ stage: PipelineStage,
        clock: some Clock<Duration>,
        generation: Int? = nil,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws(Failure) -> Success
    ) async throws(Failure) -> Success {
        let start = clock.now
        do {
            let value = try await operation()
            await record(
                .init(
                    stage: stage, duration: start.duration(to: clock.now), succeeded: true,
                    generation: generation))
            return value
        } catch {
            await record(
                .init(
                    stage: stage, duration: start.duration(to: clock.now), succeeded: false,
                    generation: generation))
            throw error
        }
    }

    /// Times a stage run under `withStageTimeout`, recording its `nil` for an expiry as a failure.
    public func measuringInTime<Success, Failure: Error>(
        _ stage: PipelineStage,
        clock: some Clock<Duration>,
        generation: Int? = nil,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws(Failure) -> Success?
    ) async throws(Failure) -> Success? {
        let start = clock.now
        do {
            let value = try await operation()
            await record(
                .init(
                    stage: stage, duration: start.duration(to: clock.now), succeeded: value != nil,
                    generation: generation))
            return value
        } catch {
            await record(
                .init(
                    stage: stage, duration: start.duration(to: clock.now), succeeded: false,
                    generation: generation))
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
            succeeded: (previous?.succeeded ?? true) && measurement.succeeded,
            generation: previous.map {
                $0.generation == measurement.generation ? measurement.generation : nil
            }
                ?? measurement.generation)
    }

    /// What each piece cost the recogniser beyond one decode, kept per piece rather than added up.
    private var decoding: [DecodeEffort] = []

    public func recordDecoding(_ effort: DecodeEffort) {
        decoding.append(effort)
    }

    /// What each piece cost the recogniser, in the order recognised.
    public var efforts: [DecodeEffort] { decoding }

    /// The decoder's judgement of each segment, kept per piece so the report keeps the pieces apart.
    private var reliability: [[SegmentReliability]] = []

    // Async like the requirement, so a direct call cannot pick the protocol's no-op default instead.
    public func recordReliability(_ segments: [SegmentReliability]) async {
        reliability.append(segments)
    }

    /// One total per stage that was measured, in the order the journey runs.
    public var measurements: [StageMeasurement] {
        PipelineStage.allCases.compactMap { totals[$0] }
    }

    /// Hands every total on as a single measurement.
    public func report(to recorder: any MetricsRecording) async {
        for measurement in measurements { await recorder.record(measurement) }
        for effort in decoding { await recorder.recordDecoding(effort) }
        for segments in reliability { await recorder.recordReliability(segments) }
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
