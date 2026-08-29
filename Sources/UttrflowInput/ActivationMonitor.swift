import Synchronization

public import UttrflowCore

/// Watches for whatever the user chose, whichever mechanism that needs.
///
/// Two mechanisms, because macOS offers no one way to do both. A combination is
/// *registered* with the window server, which then delivers it. A held modifier cannot
/// be: `RegisterEventHotKey` accepts a modifier on its own and then never fires it, so Fn
/// has to be *watched* instead. See ``CarbonHotkeyMonitor`` and ``HeldModifierMonitor``.
///
/// Callers should not have to know that. ``DictationController`` is handed one monitor
/// and asks it to start a binding; which of the two answers is this type's business, and
/// changing the shortcut from ⌥Space to Fn is the same call it always was.
///
/// A fresh underlying monitor per `start`, deliberately. An `AsyncStream` has one
/// consumer: reusing an instance would mean iterating a stream a cancelled task had
/// already been reading, and events arriving during the changeover would go to whichever
/// iteration won. Monitors are cheap; ambiguity about where a keypress went is not.
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
        // The monitor first: it is what produces events, and stopping it is what lets a
        // held key report the release the pipeline is waiting for.
        monitor?.stop()
        forwarding?.cancel()
        monitor = nil
        forwarding = nil
    }
}
