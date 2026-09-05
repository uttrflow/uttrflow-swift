public import UttrflowCore

/// Runs the recorded corpus through one recogniser it knows nothing about and measures what happens.
public struct TranscriptionRunner: Sendable {
    /// What a recogniser did with one recording.
    public enum Attempt: Sendable, Equatable {
        case transcribed(String, stages: [StageMeasurement])
        case failed(TranscriptionFailure, stages: [StageMeasurement])

        /// Timings, carried by failures too, because a stage that failed still took time.
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

    /// Scores every recording in order; `onScore` fires per passage and `transcribe` never throws.
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
                        // An engine that returns nothing heard silence: no words, and its own failure kind.
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

/// A ``MetricsRecording`` that keeps what it is given; the harness's own, since test support is never linked.
public actor CollectingMetricsRecorder: MetricsRecording {
    private var measurements: [StageMeasurement] = []

    public init() {}

    public func record(_ measurement: StageMeasurement) async {
        measurements.append(measurement)
    }

    /// Hands back everything recorded and starts again, so a passage never inherits the last one's timings.
    public func drain() -> [StageMeasurement] {
        defer { measurements = [] }
        return measurements
    }
}
