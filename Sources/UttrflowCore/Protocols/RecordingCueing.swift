/// The sound that tells the user the microphone is live; in Core so the controller never depends on how.
public protocol RecordingCueing: Sendable {
    /// Plays the "listening" cue.
    func playStart()
    /// Plays the "stopped" cue.
    func playStop()
}

/// Says nothing, which is what the user gets when they turn sounds off.
public struct SilentCue: RecordingCueing {
    /// A cue with nothing to set up.
    public init() {}
    /// Plays nothing.
    public func playStart() {}
    /// Plays nothing.
    public func playStop() {}
}
