public import UttrflowCore

/// Runs the recorded corpus through one recogniser and measures what happened.
///
/// Knows nothing about which recogniser it is driving, exactly as ``EvaluationRunner``
/// knows nothing about which transformer it is driving. That is the only way two
/// engines' numbers can be compared honestly, and it keeps every line that touches
/// WhisperKit or the system recogniser out of the part that does the measuring.
public struct TranscriptionRunner: Sendable {
    /// What a recogniser did with one recording.
    public enum Attempt: Sendable, Equatable {
        case transcribed(String, stages: [StageMeasurement])
        case failed(TranscriptionFailure, stages: [StageMeasurement])

        /// Timings are carried even by a failure, because a stage that failed still took
        /// time — usually more than one that worked — and a latency figure that quietly
        /// dropped the slow failures would flatter the product.
        public var stages: [StageMeasurement] {
            switch self {
            case .transcribed(_, let stages), .failed(_, let stages): stages
            }
        }
    }

    private let normaliser: TextNormaliser

    public init(normaliser: TextNormaliser = .standard) {
        self.normaliser = normaliser
    }

    /// - Parameters:
    ///   - label: How this run is named in the report.
    ///   - recordings: What the operator read, in the order it should be reported.
    ///   - onScore: Called with each finished score, so a caller can write it to disk
    ///     before the next passage starts. An unattended run that dies on passage
    ///     fifteen should still be able to report the first fourteen.
    ///   - transcribe: Turns one recording into a transcript, or says why it could not.
    ///     Non-throwing on purpose: every way this can go wrong is a
    ///     ``TranscriptionFailure`` the report has a column for, and an error escaping
    ///     here would abandon the run over one bad passage.
    /// - Returns: A score per recording, in the order they were given.
    public func run(
        label: String,
        over recordings: [RecordedPassage],
        onScore: (@Sendable (PassageScore) -> Void)? = nil,
        transcribe: (RecordedPassage) async -> Attempt
    ) async -> TranscriptionReport {
        var scores: [PassageScore] = []
        for recording in recordings {
            let attempt = await transcribe(recording)
            let score =
                switch attempt {
                case .transcribed(let text, let stages):
                    TranscriptionScorer.score(
                        text, against: recording.passage, normaliser: normaliser, stages: stages,
                        // An engine that ran and returned nothing has not failed to run:
                        // it heard silence. That is a transcript of no words, scored as
                        // a complete deletion, and counted as its own kind of failure.
                        failure: text.allSatisfy(\.isWhitespace) ? .recognisedNothing : nil,
                        cohortID: recording.cohort?.id)
                case .failed(let failure, let stages):
                    TranscriptionScorer.score(
                        "", against: recording.passage, normaliser: normaliser, stages: stages,
                        failure: failure, cohortID: recording.cohort?.id)
                }
            scores.append(score)
            onScore?(score)
        }
        return TranscriptionReport(label: label, scores: scores)
    }
}

/// A ``MetricsRecording`` that keeps what it is given, so a caller can hand the runner
/// the stage timings it gathered.
///
/// `UttrflowTestSupport` has one of these, and this is not it: that module is test
/// scaffolding and is never linked into anything a person runs. Rather than widen its
/// remit, the harness keeps its own — nine lines, and the reason the timing code in
/// `uttrflow-eval` is a call to ``MetricsRecording/measuring(_:clock:isolation:operation:)``
/// rather than a stopwatch written out again per stage.
public actor CollectingMetricsRecorder: MetricsRecording {
    private var measurements: [StageMeasurement] = []

    public init() {}

    public func record(_ measurement: StageMeasurement) async {
        measurements.append(measurement)
    }

    /// Hands back everything recorded and starts again, so one recorder can serve a
    /// whole run without a passage inheriting the previous passage's timings.
    public func drain() -> [StageMeasurement] {
        defer { measurements = [] }
        return measurements
    }
}
