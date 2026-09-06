import Synchronization

public import UttrflowCore

/// Watches for the chosen shortcut through whichever monitor delivers it. See `Docs/shortcuts.md`.
public final class ActivationMonitor: HotkeyMonitoring {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let current = Mutex<Current>(Current())

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        current.withLock { $0.tearDown() }
        continuation.finish()
    }

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        stop()

        // A fresh monitor each time: an `AsyncStream` has one consumer to iterate.
        let monitor: any HotkeyMonitoring =
            binding.heldModifier != nil ? HeldModifierMonitor() : CarbonHotkeyMonitor()
        // Before the forwarding task, so a monitor that refuses leaves nothing behind.
        try monitor.start(binding: binding)

        let stream = monitor.events
        let continuation = continuation
        let forwarding = Task {
            for await event in stream { continuation.yield(event) }
        }
        current.withLock {
            $0.monitor = monitor
            $0.forwarding = forwarding
        }
    }

    public func stop() {
        current.withLock { $0.tearDown() }
    }
}

/// The monitor in force and the task draining it, so neither can outlive the other.
private struct Current {
    var monitor: (any HotkeyMonitoring)?
    var forwarding: Task<Void, Never>?

    mutating func tearDown() {
        // The monitor first: stopping it is what lets a held key report the release owed.
        monitor?.stop()
        forwarding?.cancel()
        monitor = nil
        forwarding = nil
    }
}
