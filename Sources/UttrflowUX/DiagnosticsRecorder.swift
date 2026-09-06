// Keeps the stage timings the diagnostics page reports, in memory and bounded.
public import UttrflowCore

/// Keeps the stage timings the diagnostics page reports, in memory only, so nothing is written to disk.
public actor DiagnosticsRecorder: MetricsRecording, CleaningRecording {
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

    /// Oldest first, which is the order they were measured in.
    public var recorded: [StageMeasurement] {
        measurements
    }

    /// What the clean-up steps did to the last dictation; keeping every one would be a transcript of the day.
    public private(set) var lastCleaning: CleaningRecord?

    public func record(_ record: CleaningRecord) async {
        lastCleaning = record
    }

    /// Drops the last dictation's words, so a reset leaves none of them on the diagnostics page.
    public func forget() {
        lastCleaning = nil
    }
}
