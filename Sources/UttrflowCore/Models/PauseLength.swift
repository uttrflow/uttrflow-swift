/// How long the person pauses while speaking, which sets how long a pause must be before a piece or a sentence ends.
public enum PauseLength: String, Sendable, Equatable, Codable, CaseIterable {
    /// The shipped thresholds, unchanged.
    case usual
    /// Every pause threshold two and a half times as long, and no cut before the first five seconds.
    case long
    /// No pause ends a piece or a sentence; a piece is cut only at the recogniser's own window.
    case veryLong
}

extension SpeechWindowing {
    /// This windowing as it applies to a person who pauses for `pauses`.
    public func adjusted(for pauses: PauseLength) -> SpeechWindowing {
        var adjusted = self
        switch pauses {
        case .usual:
            return self
        case .long:
            // Each threshold before the fifteen-second ramp lands above a 1.5 s pause left mid-sentence.
            let scale = 2.5
            adjusted.earlyLength = Swift.max(earlyLength, minimumLength)
            adjusted.earlyPause = earlyPause * scale
            adjusted.longPause = longPause * scale
            adjusted.sentencePause = sentencePause * scale
            adjusted.anyPause = anyPause * scale
        case .veryLong:
            // A pause as long as the whole window can never end it, so only the window's own cut is left.
            adjusted.earlyLength = Swift.max(earlyLength, minimumLength)
            adjusted.earlyPause = maximumLength
            adjusted.longPause = maximumLength
            adjusted.sentencePause = maximumLength
            adjusted.anyPause = maximumLength
        }
        return adjusted
    }
}
