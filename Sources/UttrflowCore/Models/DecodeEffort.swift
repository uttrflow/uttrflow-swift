// How hard the recogniser worked for one piece: the re-decodes nothing else records.

/// What one piece cost the recogniser beyond a single decode, so a slow dictation can name its cause.
public struct DecodeEffort: Sendable, Equatable {
    /// How many times a window was decoded again at a higher temperature.
    public let fallbacks: Int
    /// How long those re-decodes took.
    public let fallbackSeconds: Double
    /// How many times the audio encoder ran.
    public let encoderRuns: Int
    /// Whether a prompted decode returned nothing and the piece was transcribed again unprompted.
    public let retriedWithoutPrompt: Bool
    /// Whether a decode stopped at the token cap and no point could be found to resume from, so later audio may be missing.
    public let capUnresolved: Bool
    /// Whether the retry chain stops at its time budget and returns what it has rather than decoding again.
    public let retryBudgetSpent: Bool
    /// Where the recognition time went, which says nothing about extra effort and so never makes a piece worth reporting.
    public let timings: RecognitionTimings

    /// One decode, no fallback and no retry, which is what a backend that reports nothing means.
    public static let none = DecodeEffort()

    public init(
        fallbacks: Int = 0, fallbackSeconds: Double = 0, encoderRuns: Int = 0,
        retriedWithoutPrompt: Bool = false, capUnresolved: Bool = false,
        retryBudgetSpent: Bool = false, timings: RecognitionTimings = .zero
    ) {
        self.fallbacks = fallbacks
        self.fallbackSeconds = fallbackSeconds
        self.encoderRuns = encoderRuns
        self.retriedWithoutPrompt = retriedWithoutPrompt
        self.capUnresolved = capUnresolved
        self.retryBudgetSpent = retryBudgetSpent
        self.timings = timings
    }

    /// Whether anything happened worth reporting.
    public var isPlain: Bool { DecodeEffort(timings: timings) == self }

    /// This effort with a retry's effort added, since the retry decodes the same audio over again.
    public func addingRetry(_ retry: DecodeEffort) -> DecodeEffort {
        DecodeEffort(
            fallbacks: fallbacks + retry.fallbacks,
            fallbackSeconds: fallbackSeconds + retry.fallbackSeconds,
            encoderRuns: encoderRuns + retry.encoderRuns,
            retriedWithoutPrompt: true, capUnresolved: capUnresolved || retry.capUnresolved,
            retryBudgetSpent: retryBudgetSpent || retry.retryBudgetSpent,
            timings: timings.adding(retry.timings))
    }

    /// One decode's effort with another's, with flags OR'd, since a tail retry decodes a different slice at the same vocabulary.
    public func adding(_ other: DecodeEffort) -> DecodeEffort {
        DecodeEffort(
            fallbacks: fallbacks + other.fallbacks,
            fallbackSeconds: fallbackSeconds + other.fallbackSeconds,
            encoderRuns: encoderRuns + other.encoderRuns,
            retriedWithoutPrompt: retriedWithoutPrompt || other.retriedWithoutPrompt,
            capUnresolved: capUnresolved || other.capUnresolved,
            retryBudgetSpent: retryBudgetSpent || other.retryBudgetSpent,
            timings: timings.adding(other.timings))
    }

    /// This effort marked as having stopped at the cap with no resume point.
    public func markingCapUnresolved() -> DecodeEffort {
        DecodeEffort(
            fallbacks: fallbacks, fallbackSeconds: fallbackSeconds, encoderRuns: encoderRuns,
            retriedWithoutPrompt: retriedWithoutPrompt, capUnresolved: true,
            retryBudgetSpent: retryBudgetSpent, timings: timings)
    }

    /// This effort marked as stopping its retries at the chain's time budget.
    public func markingRetryBudgetSpent() -> DecodeEffort {
        DecodeEffort(
            fallbacks: fallbacks, fallbackSeconds: fallbackSeconds, encoderRuns: encoderRuns,
            retriedWithoutPrompt: retriedWithoutPrompt, capUnresolved: capUnresolved,
            retryBudgetSpent: true, timings: timings)
    }
}
