internal import CoreGraphics
internal import Foundation
internal import Synchronization

/// The tap port a callback revives, and how often the system disabled it, read without a lock on the tap's thread.
final class TapPort: @unchecked Sendable {
    /// How many disables have counted against the tap inside the current window.
    private let disables = Atomic<Int>(0)
    /// When the last disable arrived, in nanoseconds on `clock`.
    private let lastDisable = Atomic<UInt64>(0)
    /// The port, retained here so the callback can re-enable it without a lock.
    private let pointer = Atomic<UnsafeMutableRawPointer?>(nil)
    /// The time disables are measured on, injected so a test can move it by hand.
    private let clock: ElapsedClock

    init(clock: some Clock<Duration>) {
        self.clock = ElapsedClock(clock)
    }

    deinit {
        if let held = pointer.load(ordering: .relaxed) { Unmanaged<CFMachPort>.fromOpaque(held).release() }
    }

    /// Keeps a new tap's port and forgets older disables, so each tap is judged alone.
    func adopt(_ port: CFMachPort) {
        forgetDisables()
        if let previous = pointer.exchange(Unmanaged.passRetained(port).toOpaque(), ordering: .releasing) {
            Unmanaged<CFMachPort>.fromOpaque(previous).release()
        }
    }

    /// Lets go of the port if it is still the one held, which its tap keeps alive for any callback still reading it.
    func relinquish(_ port: CFMachPort) {
        let expected = Unmanaged.passUnretained(port).toOpaque()
        if pointer.compareExchange(expected: expected, desired: nil, ordering: .releasing).exchanged {
            Unmanaged<CFMachPort>.fromOpaque(expected).release()
        }
    }

    /// The port to re-enable, read only on the path where the tap has already been disabled.
    func port() -> CFMachPort? {
        guard let held = pointer.load(ordering: .acquiring) else { return nil }
        return Unmanaged<CFMachPort>.fromOpaque(held).takeUnretainedValue()
    }

    /// Clears the disable history.
    func forgetDisables() {
        disables.store(0, ordering: .relaxed)
        lastDisable.store(0, ordering: .relaxed)
    }

    /// Whether to turn the tap back on, which it is unless it keeps being disabled in a short window.
    func shouldReEnable() -> Bool {
        let now = clock.nanoseconds
        let last = lastDisable.exchange(now, ordering: .relaxed)
        let (count, reEnable) = TapDisableWindow.decide(
            last: last, now: now, count: disables.load(ordering: .relaxed))
        disables.store(count, ordering: .relaxed)
        return reEnable
    }
}

/// What a tap's callback reads through its raw pointer, which holds the tap's port.
protocol TapPayload: AnyObject, Sendable {
    var tapPort: TapPort { get }
    /// Adopts the tap created for this payload, allowing payload-specific tap state to reset with its port.
    func adopt(_ port: CFMachPort)
    /// Enables a new tap on its run-loop thread, allowing payloads to reconcile their desired state first.
    func enableForRunLoop(_ port: CFMachPort)
}

extension TapPayload {
    /// Keeps the tap available to its callback and forgets disable history from earlier taps.
    func adopt(_ port: CFMachPort) { tapPort.adopt(port) }

    /// Starts generic taps enabled; stateful payloads can override this to apply their current desired state.
    func enableForRunLoop(_ port: CFMachPort) { CGEvent.tapEnable(tap: port, enable: true) }
}

/// A tap, its run loop source, and the thread the two live on, for any payload the callback reads.
final class EventTapThread<Payload: TapPayload>: @unchecked Sendable {
    /// Where the tap is in its life, read and written under one lock so `stop` and the thread agree.
    private struct Lifecycle {
        /// The run loop of the tap's own thread, known only once that thread has started.
        var loop: CFRunLoop?
        /// Whether `run` has handed the release of the payload to the thread.
        var started = false
        var stopped = false
    }

    /// The lock around `Lifecycle`, in a class so the thread can hold it without holding the tap.
    private final class LifecycleLock: Sendable {
        let lock = Mutex(Lifecycle())
    }

    /// What the tap's thread borrows, emptied on that thread before it reports the payload released.
    private final class Loan: @unchecked Sendable {
        var tap: CFMachPort?
        var source: CFRunLoopSource?

        init(tap: CFMachPort, source: CFRunLoopSource) {
            self.tap = tap
            self.source = source
        }
    }

    private let tap: CFMachPort
    private let source: CFRunLoopSource
    /// The payload the callback reads, retained until no callback can still be running.
    private let held: Unmanaged<Payload>
    private let name: String
    /// Shared with the tap's thread, which never holds the tap object itself.
    private let lifecycle = LifecycleLock()
    /// Called once the payload is released and the thread lets go of the port, which tests wait on instead of a clock.
    private let released: @Sendable () -> Void
    /// Runs on the tap's thread after its source is added and before its run loop runs.
    private let beforeLoop: @Sendable () -> Void

    private init(
        tap: CFMachPort, source: CFRunLoopSource, held: Unmanaged<Payload>, name: String,
        released: @escaping @Sendable () -> Void, beforeLoop: @escaping @Sendable () -> Void
    ) {
        self.tap = tap
        self.source = source
        self.held = held
        self.name = name
        self.released = released
        self.beforeLoop = beforeLoop
    }

    /// Stops a tap nobody stopped, so a discarded tap still gives back its port and payload.
    deinit { stop() }

    /// Builds the tap around `payload`, or `nil` when the system would not.
    static func make(
        payload: Payload, name: String,
        makePort: (UnsafeMutableRawPointer) -> CFMachPort?,
        released: @escaping @Sendable () -> Void,
        beforeLoop: @escaping @Sendable () -> Void
    ) -> EventTapThread? {
        let held = Unmanaged.passRetained(payload)
        guard
            let tap = makePort(held.toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            held.release()
            return nil
        }
        payload.adopt(tap)
        return EventTapThread(
            tap: tap, source: source, held: held, name: name, released: released, beforeLoop: beforeLoop)
    }

    /// A thread of its own, because a tap starved by a busy run loop is a tap the system disables.
    func run() {
        let starting = lifecycle.lock.withLock { life in
            guard !life.stopped, !life.started else { return false }
            life.started = true
            return true
        }
        guard starting else { return }
        let loan = Loan(tap: tap, source: source)
        let thread = Thread { [lifecycle, held, released, beforeLoop] in
            Self.serve(
                loan, payload: held.takeUnretainedValue(), lifecycle: lifecycle, beforeLoop: beforeLoop)
            // Callbacks run only inside this thread's run loop, so none can be in flight past this line.
            held.release()
            released()
        }
        thread.name = name
        // Above the default, so a keystroke is decided before the app about to receive it wakes.
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs the tap's run loop until `stop`, then empties the loan so the thread holds nothing of the tap.
    private static func serve(
        _ loan: Loan, payload: Payload, lifecycle: LifecycleLock, beforeLoop: () -> Void
    ) {
        guard let tap = loan.tap, let source = loan.source else { return }
        loan.tap = nil
        loan.source = nil
        let live = lifecycle.lock.withLock { life in
            guard !life.stopped else { return false }
            life.loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            return true
        }
        guard live else { return }
        beforeLoop()
        payload.enableForRunLoop(tap)
        CFRunLoopRun()
    }

    /// Stops the tap from any thread; the payload is released once the tap's thread has left its run loop.
    func stop() {
        let (first, started, loop) = lifecycle.lock.withLock { life in
            defer { life.stopped = true }
            return (!life.stopped, life.started, life.loop)
        }
        guard first else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        held.takeUnretainedValue().tapPort.relinquish(tap)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(tap)
        if let loop {
            // Queued on the loop, so it is heard even when the loop has not started running yet.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(loop)
        }
        if !started {
            held.release()
            released()
        }
    }
}
