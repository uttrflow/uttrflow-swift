// A HotkeyMonitoring that never reports a key.
public import UttrflowCore

/// A ``HotkeyMonitoring`` whose events never arrive: open until stopped, or ended from the start.
public final class SilentHotkeyMonitor: HotkeyMonitoring {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    /// A monitor whose events stay open until `stop()`, or, with `endsAtOnce`, end before anyone listens.
    public init(endsAtOnce: Bool = false) {
        (events, continuation) = AsyncStream.makeStream()
        if endsAtOnce { continuation.finish() }
    }

    @MainActor public func start(binding: HotkeyBinding) throws(HotkeyError) {}

    public func stop() { continuation.finish() }
}
