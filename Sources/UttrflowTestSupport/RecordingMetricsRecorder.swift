// A MetricsRecording that keeps every measurement for assertion.
public import UttrflowCore

/// A ``MetricsRecording`` that keeps every measurement for assertion.
public actor RecordingMetricsRecorder: MetricsRecording {
    public private(set) var measurements: [StageMeasurement] = []

    public init() {}

    public func record(_ measurement: StageMeasurement) async {
        measurements.append(measurement)
    }

    public func measurements(for stage: PipelineStage) -> [StageMeasurement] {
        measurements.filter { $0.stage == stage }
    }
}
