/// A soft cap on one dictation: a warning first, then a finish that keeps everything said, never a cut.
public struct DictationLimit: Sendable, Equatable {
    /// When the user is told the end is coming.
    public let warnAfter: Duration
    /// When the dictation finishes itself.
    public let stopAfter: Duration

    /// A limit with its own two moments.
    public init(warnAfter: Duration, stopAfter: Duration) {
        self.warnAfter = warnAfter
        self.stopAfter = stopAfter
    }

    /// Three minutes to the warning, four to the end: six hundred spoken words, past any dictated paragraph.
    public static let `default` = DictationLimit(
        warnAfter: .seconds(180), stopAfter: .seconds(240))

    /// What should happen at this point in a dictation.
    public func advice(at elapsed: Duration) -> DictationAdvice {
        if elapsed >= stopAfter { return .finishNow }
        if elapsed >= warnAfter { return .approaching(remaining: stopAfter - elapsed) }
        return .keepGoing
    }
}

/// What to do about a dictation that has been running a while.
public enum DictationAdvice: Sendable, Equatable {
    /// Nothing to say yet.
    case keepGoing
    /// Said before the cap, with how long is left, so the user ends the sentence rather than having it ended.
    case approaching(remaining: Duration)
    /// The cap. The dictation finishes and is transcribed; nothing said is thrown away.
    case finishNow
}
