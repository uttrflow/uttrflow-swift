public import UttrflowCore

/// Keeps the stage timings the diagnostics page reports.
///
/// The pipeline measures every stage and then hands the measurement to whatever it was
/// given; the app ships a recorder that throws them away. This one keeps them, which is
/// the whole difference between a diagnostics page that reports and one that invents.
///
/// In memory and bounded, deliberately. §22's numbers are for reading on the machine
/// that produced them, so writing them to disk would create a file about the user's
/// habits that nobody asked for — and the page says in as many words that the window it
/// covers begins when the app starts.
public actor DiagnosticsRecorder: MetricsRecording, CleaningRecording {
    /// Enough that a heavy day is still fully represented — six stages at a hundred
    /// dictations — and small enough to be uninteresting to hold.
    ///
    /// Computed from ``PipelineStage``, not written down beside it: a hand-kept literal
    /// is how the window silently shortened to two-thirds of a journey when the two V2
    /// stages were added, while the page went on saying it began when Uttrflow started.
    public static let defaultCapacity = PipelineStage.allCases.count * 100

    private let capacity: Int
    private var measurements: [StageMeasurement] = []

    public init(capacity: Int = DiagnosticsRecorder.defaultCapacity) {
        // Clamped rather than trusted, matching the recent-dictation list: a negative
        // capacity would trap in `removeFirst`, and no diagnostics is better than a crash.
        self.capacity = max(0, capacity)
    }

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
