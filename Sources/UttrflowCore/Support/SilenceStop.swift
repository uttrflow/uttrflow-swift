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
        VoiceActivity.trailingSilence(in: samples, sampleRate: sampleRate).map { $0 >= wait } ?? false
    }
}
