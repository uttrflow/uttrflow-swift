/// Why a finished suggestion line was deliberately kept out of the local corpus.
public enum CaptureSkipReason: String, Sendable, Equatable, CaseIterable {
    /// The line included text that did not come from the observed keyboard input.
    case insertedText
    /// The line did not match the keyboard input the field reported.
    case unmatchedKeys
}
