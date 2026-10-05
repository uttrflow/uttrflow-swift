// The stage-by-stage account of one tidied dictation that `uttrflow-dev explain` prints.
import Foundation
public import UttrflowCore

/// What each stage of one dictation took in, gave out and decided. See `Docs/dictation-trace.md`.
public struct DictationExplanation: Sendable, Equatable {
    /// What the recogniser handed over, words and confidences included.
    public let request: TransformationRequest
    /// The words after the passes that run before any model, which is the line a model is given.
    public let spoken: String
    /// The half-heard runs the sources offered readings for, as the model is shown them.
    public let doubtful: [DoubtfulSpan]
    /// What the router kept, with the record of the steps, refusals and skipped engines.
    public let result: TransformationResult

    public init(
        request: TransformationRequest, spoken: String, doubtful: [DoubtfulSpan],
        result: TransformationResult
    ) {
        self.request = request
        self.spoken = spoken
        self.doubtful = doubtful
        self.result = result
    }

    /// Tidies the request through `cleaner`, keeping what the stages before the model saw.
    public static func tracing(
        _ request: TransformationRequest, through cleaner: any TranscriptCleaning
    ) async throws(TransformationError) -> DictationExplanation {
        let draft = CleaningPipeline.beforeModel(
            for: .standard(for: request.situation), situation: request.situation
        ).run(Draft(transcription: request.transcription))
        let doubtful = await DoubtfulWords.standard.spans(in: draft, for: request.situation)
        let result = try await cleaner.clean(request)
        return DictationExplanation(
            request: request, spoken: draft.text, doubtful: doubtful, result: result)
    }

    /// The account, one labelled line per fact, in the order the stages ran.
    public var lines: [String] {
        [Self.row("heard", request.transcription.text), Self.row("words", scores)]
            + doubtfulRows + [Self.row("for model", spoken)] + cleaningRows
            + [
                Self.row("tidied by", result.producedBy.rawValue),
                Self.row("result", result.text.replacingOccurrences(of: "\n", with: "⏎")),
            ]
    }

    /// Every word with its confidence, or why there are none rather than a stand-in score.
    private var scores: String {
        let draft = Draft(transcription: request.transcription)
        guard draft.confidencesAreReal else {
            return "not scored: the recogniser gave no confidences that spell the text"
        }
        return draft.words.map { "\($0.heard) \(Self.score($0.confidence))" }.joined(separator: ", ")
    }

    private var doubtfulRows: [String] {
        guard !doubtful.isEmpty else { return [Self.row("doubtful", "none with another reading")] }
        return doubtful.map {
            let readings = $0.candidates.map(\.spelling).joined(separator: ", ")
            return Self.row("doubtful", "\"\($0.heard)\" at \(Self.score($0.confidence)) → \(readings)")
        }
    }

    private var cleaningRows: [String] {
        guard let record = result.cleaning else {
            return [Self.row("steps", "no record kept by \(result.producedBy.rawValue)")]
        }
        return record.unavailableEngines.map {
            Self.row("skipped", "\($0.engine): \($0.reason.diagnosticDescription)")
        }
            + record.engineFailures.map { Self.row("failed", "\($0.engine): \($0.failureClass.rawValue)") }
            + record.refusals.map { Self.row("refused", "\($0.engine): \($0.reason)") }
            + record.changes.map {
                Self.row(
                    "step",
                    "\(CleaningSteps.name(of: $0.step)): "
                        + $0.summary(quoting: CleaningRecord.wordLimit))
            }
            + record.switchedOff.map { Self.row("off", CleaningSteps.name(of: $0)) }
    }

    /// The width of the label column, wide enough for the longest label.
    private static let labelWidth = 11

    private static func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: labelWidth, withPad: " ", startingAt: 0) + value
    }

    private static func score(_ confidence: Double) -> String {
        String(format: "%.2f", confidence)
    }
}
