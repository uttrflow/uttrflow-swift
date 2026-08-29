/// I8 — how long one dictation may run, and what is said on the way to the end.
///
/// The specification is precise about the shape: *a soft cap with a warning before it is
/// hit, not a silent truncation after.* Those are two different products. A hard cut at
/// four minutes loses the last sentence somebody said and tells them afterwards, which is
/// the worst moment to find out; a warning at three lets them finish the thought.
///
/// "Soft" is the other half. Reaching the cap **finishes** the dictation — everything said
/// so far is transcribed and inserted — rather than discarding it. A cap that threw the
/// audio away would be a worse outcome than no cap at all, and the reason a cap exists is
/// memory and transcription time, both of which are served by stopping and keeping.
public struct DictationLimit: Sendable, Equatable {
    /// When the user is told the end is coming.
    public let warnAfter: Duration
    /// When the dictation finishes itself.
    public let stopAfter: Duration

    public init(warnAfter: Duration, stopAfter: Duration) {
        self.warnAfter = warnAfter
        self.stopAfter = stopAfter
    }

    /// Three minutes to the warning, four to the end.
    ///
    /// Set by what a dictation *is* rather than by what the machine could bear. Speech is
    /// about 150 words a minute, so four minutes is six hundred words — far past any
    /// message, comment or paragraph somebody dictates into another application, and the
    /// point beyond which a single utterance is almost always a microphone left running.
    ///
    /// The minute between them is deliberate: long enough to finish a sentence and stop
    /// deliberately, which is the whole difference between a soft cap and a hard one.
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
    case keepGoing
    /// I8 — said *before* the cap, with how long is left, so the user can end the sentence
    /// themselves rather than have it ended for them.
    case approaching(remaining: Duration)
    /// The cap. The dictation finishes and is transcribed; nothing said is thrown away.
    case finishNow
}
