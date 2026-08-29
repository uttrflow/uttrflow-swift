/// The sound that tells the user the microphone is live.
///
/// Declared here rather than beside the audio engine because the controller that
/// decides *when* to play it must not depend on the code that knows *how*.
public protocol RecordingCueing: Sendable {
    func playStart()
    func playStop()
}

/// Says nothing. What the user gets when they turn sounds off.
public struct SilentCue: RecordingCueing {
    public init() {}
    public func playStart() {}
    public func playStop() {}
}
