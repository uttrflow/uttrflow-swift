/// The sound that tells the user the microphone is live; in Core so the controller never depends on how.
public protocol RecordingCueing: Sendable {
    /// Plays the "listening" cue.
    func playStart()
    /// Plays the "stopped" cue.
    func playStop()
    /// Plays the warning that the dictation is nearing its cap.
    func playWarning()
    /// Plays the soft cue that a recording was cancelled and its words will not be typed.
    func playDiscarded()
    /// Whether the next cue is heard, so a spoken line can give way to it while the microphone is open.
    var isAudible: Bool { get }
}

extension RecordingCueing {
    /// Assumed silent, so a cue that cannot say otherwise never costs a VoiceOver user the spoken line.
    public var isAudible: Bool { false }
}

/// Says nothing, which is what the user gets when they turn sounds off.
public struct SilentCue: RecordingCueing {
    /// A cue with nothing to set up.
    public init() {}
    /// Plays nothing.
    public func playStart() {}
    /// Plays nothing.
    public func playStop() {}
    /// Plays nothing.
    public func playWarning() {}
    /// Plays nothing.
    public func playDiscarded() {}
}
