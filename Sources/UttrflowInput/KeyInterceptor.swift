internal import ApplicationServices
internal import CoreGraphics
internal import Dispatch
private import Foundation
internal import Synchronization
public import UttrflowPredict

/// Why the tap is not running.
public enum KeyInterceptorFailure: Error, Sendable, Equatable {
    /// macOS will not let this process watch the keyboard.
    case accessibilityDenied
    /// The system refused to create the tap even with Accessibility granted.
    case tapRefused
    /// The system disabled the tap twice, so it is not being armed a third time.
    case disabledTwice
}

/// One thing the tap has to say.
public enum InterceptedEvent: Sendable, Equatable {
    /// An armed keystroke the tap took, which the application never sees.
    case swallowed(KeyStroke)
    /// The tap has stopped and nothing more will be taken.
    case stopped(KeyInterceptorFailure)
}

/// Takes the keys a suggestion has claimed and passes every other key through. See `Docs/predict-accept.md`.
public final class KeyInterceptor: Sendable {
    /// What the tap took, in the order it took it.
    public let events: AsyncStream<InterceptedEvent>

    /// Everything the C callback touches, which outlives any one run of the tap.
    private let state: TapState
    /// The source the callback signals, on whose queue the taken keystrokes are turned into events.
    private let drain: any DispatchSourceUserDataAdd
    /// The tap in force, or `nil` when nothing is watching the keyboard.
    private let running = Mutex<InterceptorTap?>(nil)

    public init() {
        let (events, continuation) = AsyncStream<InterceptedEvent>.makeStream()
        self.events = events
        let source = DispatchSource.makeUserDataAddSource(
            queue: DispatchQueue(label: "co.uttrflow.key-interceptor"))
        drain = source
        state = TapState(signal: source)
        source.setEventHandler { [state] in
            for event in state.take() { continuation.yield(event) }
        }
        source.resume()
    }

    deinit {
        running.withLock { $0?.stop() }
        // Also breaks the cycle between the source and the state that signals it.
        drain.setEventHandler(handler: nil)
        drain.cancel()
    }

    /// Which keystrokes to take, which is the one atomic the callback reads.
    public func arm(_ keys: ArmedKeys) {
        state.armed.store(keys.rawValue, ordering: .relaxed)
    }

    /// Creates the tap and gives it a thread with a run loop of its own.
    public func start() throws(KeyInterceptorFailure) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard running.withLock({ $0 == nil }) else { return }
        let tap = try InterceptorTap.create(state: state)
        running.withLock { $0 = tap }
        tap.run()
    }

    /// Stops the tap and lets its thread's run loop finish.
    public func stop() {
        running.withLock { tap in
            tap?.stop()
            tap = nil
        }
        state.armed.store(0, ordering: .relaxed)
    }
}

/// The tap, its run loop source, and the thread the two live on.
final class InterceptorTap: @unchecked Sendable {
    /// Where the tap is in its life, read and written under one lock so `stop` and the thread agree.
    private struct Lifecycle {
        /// The run loop of the tap's own thread, known only once that thread has started.
        var loop: CFRunLoop?
        /// Whether `run` has handed the release of the state to the thread.
        var started = false
        var stopped = false
    }

    /// What the tap's thread borrows, emptied on that thread before it reports the state released.
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
    /// The state the callback reads, retained until no callback can still be running.
    private let held: Unmanaged<TapState>
    /// Shared with the tap's thread, which never holds the tap object itself.
    private let lifecycle = LifecycleLock()
    /// Called once the state is released and the thread lets go of the port, which tests wait on instead of a clock.
    private let released: @Sendable () -> Void
    /// Runs on the tap's thread after its source is added and before its run loop runs.
    private let beforeLoop: @Sendable () -> Void

    /// The lock around `Lifecycle`, in a class so the thread can hold it without holding the tap.
    private final class LifecycleLock: Sendable {
        let lock = Mutex(Lifecycle())
    }

    private init(
        tap: CFMachPort, source: CFRunLoopSource, held: Unmanaged<TapState>,
        released: @escaping @Sendable () -> Void, beforeLoop: @escaping @Sendable () -> Void
    ) {
        self.tap = tap
        self.source = source
        self.held = held
        self.released = released
        self.beforeLoop = beforeLoop
    }

    /// Stops a tap nobody stopped, so a discarded tap still gives back its port and state.
    deinit { stop() }

    /// Builds the tap, or says that the system would not; `makePort`, `released` and `beforeLoop` are replaced only by tests.
    static func create(
        state: TapState,
        makePort: (UnsafeMutableRawPointer) -> CFMachPort? = InterceptorTap.keyDownTap,
        released: @escaping @Sendable () -> Void = {},
        beforeLoop: @escaping @Sendable () -> Void = {}
    ) throws(KeyInterceptorFailure) -> InterceptorTap {
        let held = Unmanaged.passRetained(state)
        guard
            let tap = makePort(held.toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            held.release()
            throw .tapRefused
        }
        state.adopt(tap)
        return InterceptorTap(
            tap: tap, source: source, held: held, released: released, beforeLoop: beforeLoop)
    }

    /// The session tap on key-down that `create` uses outside tests.
    static func keyDownTap(userInfo: UnsafeMutableRawPointer) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: keyInterceptorCallback,
            userInfo: userInfo)
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
            Self.serve(loan, lifecycle: lifecycle, beforeLoop: beforeLoop)
            // Callbacks run only inside this thread's run loop, so none can be in flight past this line.
            held.release()
            released()
        }
        thread.name = "co.uttrflow.key-interceptor"
        // Above the default, so a keystroke is decided before the app about to receive it wakes.
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs the tap's run loop until `stop`, then empties the loan so the thread holds nothing of the tap.
    private static func serve(_ loan: Loan, lifecycle: LifecycleLock, beforeLoop: () -> Void) {
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
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    /// Stops the tap; the state is released once the tap's thread has left its run loop.
    func stop() {
        let (first, started, loop) = lifecycle.lock.withLock { life in
            defer { life.stopped = true }
            return (!life.stopped, life.started, life.loop)
        }
        guard first else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        held.takeUnretainedValue().relinquish(tap)
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

/// Everything the C callback may touch, held where a raw pointer can reach it.
final class TapState: @unchecked Sendable {
    /// How many taken keystrokes may wait for the drain; while it is that far behind, newer ones are dropped.
    static let capacity = 64

    /// Which slots are being taken, and the only thing the callback loads.
    let armed = Atomic<UInt32>(0)

    /// Written by the tap's thread and read by the drain; a slot is written again only once the drain has read it.
    private let ring: UnsafeMutablePointer<UInt32>
    /// Set when the tap gives up, kept out of the ring so a full ring cannot lose it.
    private let gaveUp = Atomic<Bool>(false)
    /// How many keystrokes have ever been written into the ring.
    private let written = Atomic<UInt64>(0)
    /// How many the drain has ever taken out of it.
    private let read = Atomic<UInt64>(0)
    /// How many disables have counted against the tap inside the current window.
    private let disables = Atomic<Int>(0)
    /// When the last disable arrived, in uptime nanoseconds.
    private let lastDisable = Atomic<UInt64>(0)
    /// The tap port, retained here so the callback can re-enable it without a lock.
    private let tapPointer = Atomic<UnsafeMutableRawPointer?>(nil)
    /// Woken on every write, so the drain runs off the tap's own thread.
    private let signal: any DispatchSourceUserDataAdd

    init(signal: any DispatchSourceUserDataAdd) {
        self.signal = signal
        ring = .allocate(capacity: Self.capacity)
        ring.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        if let held = tapPointer.load(ordering: .relaxed) { Unmanaged<CFMachPort>.fromOpaque(held).release() }
        ring.deinitialize(count: Self.capacity)
        ring.deallocate()
    }

    /// Keeps the port where the callback can re-enable the tap without taking a lock, releasing the one it replaces.
    func adopt(_ port: CFMachPort) {
        if let previous = tapPointer.exchange(Unmanaged.passRetained(port).toOpaque(), ordering: .releasing) {
            Unmanaged<CFMachPort>.fromOpaque(previous).release()
        }
    }

    /// Lets go of the port if it is still the one held, which its tap keeps alive for any callback still reading it.
    func relinquish(_ port: CFMachPort) {
        let expected = Unmanaged.passUnretained(port).toOpaque()
        if tapPointer.compareExchange(expected: expected, desired: nil, ordering: .releasing).exchanged {
            Unmanaged<CFMachPort>.fromOpaque(expected).release()
        }
    }

    /// The port to re-enable, read only on the path where the tap has already been disabled.
    func port() -> CFMachPort? {
        guard let held = tapPointer.load(ordering: .acquiring) else { return nil }
        return Unmanaged<CFMachPort>.fromOpaque(held).takeUnretainedValue()
    }

    /// Records one taken keystroke, or drops it and returns false when the drain is a whole ring behind.
    @discardableResult
    func enqueue(_ slot: UInt32) -> Bool {
        let next = written.load(ordering: .relaxed)
        // Acquiring pairs with the drain's releasing store, so a slot is read before it is written again.
        guard next &- read.load(ordering: .acquiring) < UInt64(Self.capacity) else { return false }
        ring[Int(next % UInt64(Self.capacity))] = slot
        written.store(next &+ 1, ordering: .releasing)
        signal.add(data: 1)
        return true
    }

    /// Whether the tap should be turned back on, which it is unless it keeps being disabled within a short window.
    func shouldReEnable() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let last = lastDisable.exchange(now, ordering: .relaxed)
        let (count, reEnable) = TapDisableWindow.decide(
            last: last, now: now, count: disables.load(ordering: .relaxed))
        disables.store(count, ordering: .relaxed)
        if !reEnable {
            gaveUp.store(true, ordering: .releasing)
            signal.add(data: 1)
        }
        return reEnable
    }

    /// Everything written since the last drain, oldest first, then the tap giving up if it has.
    func take() -> [InterceptedEvent] {
        // Read before `written`, so every keystroke taken before the tap gave up is drained with it.
        let stopped = gaveUp.exchange(false, ordering: .acquiring)
        let end = written.load(ordering: .acquiring)
        var cursor = read.load(ordering: .relaxed)
        var events: [InterceptedEvent] = []
        while cursor < end {
            let slot = ring[Int(cursor % UInt64(Self.capacity))]
            if let stroke = ArmedKeys.stroke(of: ArmedKeys(rawValue: slot)) {
                events.append(.swallowed(stroke))
            }
            cursor &+= 1
        }
        // Releasing, so the tap writes these slots again only after they have been read.
        read.store(cursor, ordering: .releasing)
        if stopped { events.append(.stopped(.disabledTwice)) }
        return events
    }
}

/// The one function macOS calls per keypress, which loads a single atomic and returns.
private let keyInterceptorCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<TapState>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .keyDown:
        // The feature's own inserted keys reach this tap upstream; passing them through stops the loop.
        guard !SyntheticEvent.isOurs(event) else { return Unmanaged.passUnretained(event) }
        let stroke = KeyStroke(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: KeyModifiers(event.flags))
        let slot = ArmedKeys.slot(of: stroke)
        guard !slot.isEmpty, state.armed.load(ordering: .relaxed) & slot.rawValue != 0 else {
            return Unmanaged.passUnretained(event)
        }
        // Swallowing a navigation key claims Return here and now, so a fast Down-then-Return never runs the command.
        if slot == .downArrow || slot == .upArrow {
            state.armed.bitwiseOr(ArmedKeys.return.rawValue, ordering: .relaxed)
        }
        state.enqueue(slot.rawValue)
        return nil
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // Not the keystroke path: by the time this runs the system has already stopped delivering.
        if state.shouldReEnable(), let port = state.port() {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}

extension KeyModifiers {
    /// The window server's flags, narrowed to the four that change what a key means.
    fileprivate init(_ flags: CGEventFlags) {
        var modifiers = KeyModifiers()
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
