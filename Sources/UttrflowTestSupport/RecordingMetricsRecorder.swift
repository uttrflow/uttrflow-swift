// A MetricsRecording that keeps every measurement for assertion.
public import UttrflowCore

/// A ``MetricsRecording`` that keeps every measurement for assertion.
public actor RecordingMetricsRecorder: MetricsRecording {
    public private(set) var measurements: [StageMeasurement] = []

    public init() {}

    public func record(_ measurement: StageMeasurement) async {
        measurements.append(measurement)
    }

    /// What each recognised piece cost beyond one decode, in the order the pieces were recognised.
    public private(set) var decoding: [DecodeEffort] = []

    public func recordDecoding(_ effort: DecodeEffort) async {
        decoding.append(effort)
    }

    /// The decoder's judgement of each piece's segments, one entry per piece in the order recognised.
    public private(set) var reliability: [[SegmentReliability]] = []

    public func recordReliability(_ segments: [SegmentReliability]) async {
        reliability.append(segments)
    }

    /// What each recording sounded like, in the order they were measured.
    public private(set) var captureQualities: [CaptureQuality] = []

    public func recordCaptureQuality(_ quality: CaptureQuality) async {
        captureQualities.append(quality)
    }

    /// What reading the screen cost each dictation, in the order they settled.
    public private(set) var screenReads: [ScreenReadCost] = []

    public func recordScreenReads(_ reads: ScreenReadCost) async {
        screenReads.append(reads)
    }

    /// Why each dictation's last screen read carried no field text, `nil` where it did, in the order they settled.
    public private(set) var screenText: [ContextUnavailableReason?] = []

    public func recordScreenText(_ unavailable: ContextUnavailableReason?) async {
        screenText.append(unavailable)
    }

    /// Each screen read's rung and application, in the order they were read.
    public private(set) var contextReads: [ContextRead] = []

    public func recordContextRead(_ rung: ContextReadRung, in bundleIdentifier: String) async {
        contextReads.append(ContextRead(rung: rung, bundleIdentifier: bundleIdentifier))
    }

    /// Each dictation's wait after key-up and its named cause, in the order they ended.
    public private(set) var waits: [TimedWait] = []

    public func recordWait(_ wait: TimedWait) async {
        waits.append(wait)
    }

    public func measurements(for stage: PipelineStage) -> [StageMeasurement] {
        measurements.filter { $0.stage == stage }
    }
}

/// One screen read as a recorder saw it: the rung that answered and the application, with no field text.
public struct ContextRead: Sendable, Equatable {
    public let rung: ContextReadRung
    public let bundleIdentifier: String
}
