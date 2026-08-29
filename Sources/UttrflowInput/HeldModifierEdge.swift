public import UttrflowCore

/// Turns "the flags say the key is down" into a press and a release.
///
/// Extracted from ``HeldModifierMonitor`` because it is the only part of watching a
/// modifier that decides anything, and both of its rules fail in ways nobody sees:
///
/// - **macOS sends several flag changes for one press.** A monitor that yielded on each
///   would start a dictation inside a dictation. Only a change of state is an event.
/// - **A hold interrupted by stopping is a release.** Without that the thing listening
///   waits for an end that never comes and the microphone stays open — which is the
///   worst failure this product has, because the user cannot see it happening.
///
/// The rest of that type is `NSEvent` monitors and token bookkeeping, which no test can
/// reach without a window server. This is the half that can be, so it is.
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
