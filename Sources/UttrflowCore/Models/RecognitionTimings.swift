// Where one piece's recognition time went, sub-stage by sub-stage, as the recogniser measured it.

/// Seconds and step counts per recognition sub-stage, summed over every window of a piece.
public struct RecognitionTimings: Sendable, Equatable {
    /// Turning audio into the mel spectrogram.
    public let melSeconds: Double
    /// Running the audio encoder.
    public let encodeSeconds: Double
    /// Setting up the decoder's inputs before the first step.
    public let decoderSetupSeconds: Double
    /// Filling the decoder's key-value cache with the task tokens before the loop, outside every other sub-stage.
    public let prefillSeconds: Double
    /// How many decoder steps ran, prompt and output tokens together.
    public let decodeSteps: Int
    /// Time spent inside the decoder model across those steps.
    public let decodeSeconds: Double
    /// Of `decodeSteps`, the steps that fed a forced prompt token rather than sampling one.
    public let promptSteps: Int
    /// Of `decodeSeconds`, the time spent inside the decoder model on those prompt steps.
    public let promptStepSeconds: Double
    /// Of the sampled steps, those that produced a timestamp token rather than a word.
    public let timestampSteps: Int
    /// Filtering, sampling and cache updates between the decoder model's calls.
    public let decodeOverheadSeconds: Double
    /// How many times word timings were aligned.
    public let wordTimingRuns: Int
    /// Time spent aligning word timings.
    public let wordTimingSeconds: Double
    /// The recogniser's own wall-clock time for the piece, which the sub-stages sit inside.
    public let recognitionSeconds: Double

    /// Nothing measured, which is what a backend that reports no timings means.
    public static let zero = RecognitionTimings()

    public init(
        melSeconds: Double = 0, encodeSeconds: Double = 0, decoderSetupSeconds: Double = 0,
        decodeSteps: Int = 0, decodeSeconds: Double = 0, wordTimingRuns: Int = 0,
        wordTimingSeconds: Double = 0, recognitionSeconds: Double = 0, prefillSeconds: Double = 0,
        promptSteps: Int = 0, promptStepSeconds: Double = 0, timestampSteps: Int = 0,
        decodeOverheadSeconds: Double = 0
    ) {
        self.melSeconds = melSeconds
        self.encodeSeconds = encodeSeconds
        self.decoderSetupSeconds = decoderSetupSeconds
        self.decodeSteps = decodeSteps
        self.decodeSeconds = decodeSeconds
        self.wordTimingRuns = wordTimingRuns
        self.wordTimingSeconds = wordTimingSeconds
        self.recognitionSeconds = recognitionSeconds
        self.prefillSeconds = prefillSeconds
        self.promptSteps = promptSteps
        self.promptStepSeconds = promptStepSeconds
        self.timestampSteps = timestampSteps
        self.decodeOverheadSeconds = decodeOverheadSeconds
    }

    /// Both pieces of work together, since a retry or a later window runs every sub-stage again.
    public func adding(_ other: RecognitionTimings) -> RecognitionTimings {
        RecognitionTimings(
            melSeconds: melSeconds + other.melSeconds,
            encodeSeconds: encodeSeconds + other.encodeSeconds,
            decoderSetupSeconds: decoderSetupSeconds + other.decoderSetupSeconds,
            decodeSteps: decodeSteps + other.decodeSteps,
            decodeSeconds: decodeSeconds + other.decodeSeconds,
            wordTimingRuns: wordTimingRuns + other.wordTimingRuns,
            wordTimingSeconds: wordTimingSeconds + other.wordTimingSeconds,
            recognitionSeconds: recognitionSeconds + other.recognitionSeconds,
            prefillSeconds: prefillSeconds + other.prefillSeconds,
            promptSteps: promptSteps + other.promptSteps,
            promptStepSeconds: promptStepSeconds + other.promptStepSeconds,
            timestampSteps: timestampSteps + other.timestampSteps,
            decodeOverheadSeconds: decodeOverheadSeconds + other.decodeOverheadSeconds)
    }

    /// Recognition time no sub-stage accounts for, such as the recogniser's windowing between decodes.
    public var unattributedSeconds: Double {
        let named =
            melSeconds + encodeSeconds + decoderSetupSeconds + prefillSeconds + decodeSeconds
            + decodeOverheadSeconds + wordTimingSeconds
        return recognitionSeconds - named
    }
}
