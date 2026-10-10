/// Notices, while a recording runs, that the microphone sends nothing a refusal would accept. See `Docs/silence.md`.
public struct InputSilence: Sendable, Equatable {
    /// How long the input must stay below the floor before the person is told, in seconds.
    public static let patience = 2.0

    /// What the dock shows and VoiceOver says while the input stays below the floor.
    public static let line = "Can't hear you. Check the microphone."

    /// Since when every reading has been below the floor, or `nil` once one reached it.
    private var quietSince: Double?

    /// Whether the person is being told the microphone is not picking them up.
    public private(set) var isSilent = false

    public init() {}

    /// Takes one level reading as RMS at `time` seconds; `true` only on the reading that starts the warning.
    public mutating func read(_ level: Float, at time: Double) -> Bool {
        // A `nan` from a misbehaving driver is not a signal.
        guard level.isFinite, level >= VoiceActivity.absoluteFloor else {
            let since = quietSince ?? time
            quietSince = since
            guard !isSilent, time - since >= Self.patience else { return false }
            isSilent = true
            return true
        }
        quietSince = nil
        isSilent = false
        return false
    }
}
