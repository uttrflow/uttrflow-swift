/// Ends a recording once the person has been quiet for the wait they chose. See `Docs/silence.md`.
public struct SilenceStop: Sendable, Equatable {
    /// The waits a person can choose, in seconds; any other value is off.
    public static let choices = [2, 4, 8]

    /// How often the end of the recording is checked.
    public static let poll: Duration = .milliseconds(500)

    /// Audio read before the wait on each check, so the last word is inside what the check sees.
    static let context: Duration = .seconds(5)

    /// How long the quiet must last.
    public let wait: Duration

    /// The stop for a chosen wait, or `nil` when `seconds` is not one of ``choices``.
    public init?(seconds: Int) {
        guard Self.choices.contains(seconds) else { return nil }
        wait = .seconds(seconds)
    }

    /// How many samples at `sampleRate` each check reads: the wait and the context before it.
    public func lookBack(atRate sampleRate: Int) -> Int {
        Int((wait + Self.context) / .seconds(1) * Double(sampleRate))
    }

    /// Whether `samples` end in a quiet at least as long as the wait, after speech.
    public func isReached(in samples: [Float], sampleRate: Int) -> Bool {
        quiet(in: samples, sampleRate: sampleRate).map { $0 >= wait } ?? false
    }

    /// How long `samples` have been quiet since the last speech, or `nil` when none was heard.
    public func quiet(in samples: [Float], sampleRate: Int) -> Duration? {
        VoiceActivity.trailingSilence(in: samples, sampleRate: sampleRate)
    }

    /// Whole seconds left, at least 1, once `quiet` passes half the wait and before it ends the recording; otherwise `nil`.
    public func secondsLeft(afterQuiet quiet: Duration?) -> Int? {
        guard let quiet, quiet > wait / 2, quiet < wait else { return nil }
        return Swift.max(1, Int(((wait - quiet) / .seconds(1)).rounded(.up)))
    }

    /// The dock's words for the countdown.
    public static func phrase(secondsLeft: Int) -> String { "Ending in \(secondsLeft) sec" }

    /// The spoken form of the countdown, once per countdown.
    public static func sentence(secondsLeft: Int) -> String {
        "Dictation ends in \(secondsLeft) \(secondsLeft == 1 ? "second" : "seconds")."
    }
}
