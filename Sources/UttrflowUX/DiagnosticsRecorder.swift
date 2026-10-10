// Keeps the stage timings the diagnostics page reports, in memory and bounded.
public import UttrflowCore

/// Keeps the stage timings the diagnostics page reports, in memory only, so nothing is written to disk.
public actor DiagnosticsRecorder: MetricsRecording, CleaningRecording, TidyOutcomeRecording {
    /// Six stages at a hundred dictations, computed from ``PipelineStage`` so a new stage cannot shorten it.
    public static let defaultCapacity = PipelineStage.allCases.count * 100

    /// How many measurements are kept.
    private let capacity: Int
    /// Oldest first.
    private var measurements: [StageMeasurement] = []

    /// Keeps up to `capacity` measurements; a nonsense capacity keeps none.
    public init(capacity: Int = DiagnosticsRecorder.defaultCapacity) {
        // Clamped rather than trusted: a negative capacity would trap in `removeFirst`.
        self.capacity = max(0, capacity)
    }

    /// Keeps a measurement, dropping the oldest once full.
    public func record(_ measurement: StageMeasurement) async {
        guard capacity > 0 else { return }
        measurements.append(measurement)
        if measurements.count > capacity {
            measurements.removeFirst(measurements.count - capacity)
        }
    }

    /// What each recognised piece cost beyond one decode, newest last and bounded like the measurements.
    public private(set) var decoding: [DecodeEffort] = []

    /// The last recogniser prompt, kept locally so the Dictionary page can explain what was offered.
    public private(set) var vocabularyPrompt: [String] = []

    public func recordVocabularyPrompt(_ words: [String]) async {
        guard capacity > 0 else { return }
        vocabularyPrompt = words
    }

    /// Whether the newest piece's decode could be conditioned on the user's words.
    public private(set) var conditioning: DecodeConditioning = .available
    /// How many pieces in a row ran unconditioned, so a lasting fault can be told from a single one.
    public private(set) var unconditionedRun = 0

    public func recordConditioning(_ conditioning: DecodeConditioning) async {
        self.conditioning = conditioning
        unconditionedRun = conditioning == .available ? 0 : unconditionedRun + 1
    }

    public func recordDecoding(_ effort: DecodeEffort) async {
        guard capacity > 0 else { return }
        decoding.append(effort)
        if decoding.count > capacity { decoding.removeFirst(decoding.count - capacity) }
    }

    /// The decoder's judgement of each recognised segment, newest last and bounded like the measurements.
    public private(set) var reliability: [SegmentReliability] = []

    public func recordReliability(_ segments: [SegmentReliability]) async {
        guard capacity > 0 else { return }
        reliability += segments
        if reliability.count > capacity { reliability.removeFirst(reliability.count - capacity) }
    }

    /// What each recording sounded like, newest last and bounded like the measurements.
    public private(set) var captureQualities: [CaptureQuality] = []

    public func recordCaptureQuality(_ quality: CaptureQuality) async {
        guard capacity > 0 else { return }
        captureQualities.append(quality)
        if captureQualities.count > capacity {
            captureQualities.removeFirst(captureQualities.count - capacity)
        }
    }

    /// Oldest first, which is the order they were measured in.
    public var recorded: [StageMeasurement] {
        measurements
    }

    /// What the clean-up steps did to the last dictation; keeping every one would be a transcript of the day.
    public private(set) var lastCleaning: CleaningRecord?

    public func record(_ record: CleaningRecord) async {
        lastCleaning = record
    }

    /// How the tidy route ended for the last pieces, counted without a word of them.
    public private(set) var tidyTally = TidyTally()

    public func record(_ outcome: TidyOutcome) async {
        tidyTally.add(outcome)
    }

    /// The last dictations' waits after key-up, each with its cause; numbers only, never words.
    public private(set) var waits = DictationWaits()

    public func recordWait(_ wait: TimedWait) async {
        guard capacity > 0 else { return }
        waits.keep(wait)
    }

    /// Why the last dictation's screen read carried no field text, or `nil` when it did or none was read.
    public private(set) var screenTextUnavailable: ContextUnavailableReason?

    public func recordScreenText(_ unavailable: ContextUnavailableReason?) async {
        screenTextUnavailable = unavailable
    }

    /// Which rung answered each screen read, per application, counted without a word of the field.
    public private(set) var readRungs = ContextReadTally()

    public func recordContextRead(_ rung: ContextReadRung, in bundleIdentifier: String) async {
        readRungs.add(rung, in: bundleIdentifier)
    }

    /// Drops the last dictation's words and the tallies, so a reset leaves none of them on the diagnostics page.
    public func forget() {
        tidyTally = TidyTally()
        readRungs = ContextReadTally()
        lastCleaning = nil
        vocabularyPrompt = []
    }
}
