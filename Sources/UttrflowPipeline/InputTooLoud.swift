// The one wording every surface uses when the microphone input clipped enough to cost accuracy.

/// What the dock and VoiceOver say about a dictation whose input was clipped past the measured cliff.
enum InputTooLoud {
    /// The clipped share of samples at which accuracy was measurably worse in a paired comparison.
    static let clippedFractionThreshold = 0.17
    /// The short headline, sized for the dock.
    static let line = "Inserted — input too loud"
    /// The second line under the headline, saying what the person should do.
    static let detail = "Lower the microphone input volume"
    /// The full sentence read aloud, which never abbreviates.
    static let sentence = "Your microphone input is too loud. Lower the input volume."

    /// Whether a clipped share of samples is past the point where accuracy falls.
    static func isTooLoud(clippedFraction: Double) -> Bool {
        clippedFraction >= clippedFractionThreshold
    }
}
