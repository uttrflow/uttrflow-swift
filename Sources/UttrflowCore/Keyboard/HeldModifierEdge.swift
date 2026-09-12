/// Turns "the flags say the key is down" into a press and a release. See `Docs/stuck-recording.md`.
public struct HeldModifierEdge: Sendable, Equatable {
    /// Whether the key is currently held, as far as this has been told.
    public private(set) var isDown = false

    public init() {}

    /// The flags changed. Answers the event that represents, or `nil` when nothing did.
    public mutating func flagsChanged(isDownNow: Bool) -> HotkeyEvent? {
        guard isDownNow != isDown else { return nil }
        isDown = isDownNow
        return isDownNow ? .pressed : .released
    }

    /// Watching stopped. Answers the release owed to a hold that was in progress.
    public mutating func stopped() -> HotkeyEvent? {
        guard isDown else { return nil }
        isDown = false
        return .released
    }
}
