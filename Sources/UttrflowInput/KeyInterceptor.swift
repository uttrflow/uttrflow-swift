private import ApplicationServices
private import CoreGraphics
private import Dispatch
private import Foundation
private import Synchronization
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
    /// This keystroke was armed, so it was taken and the application never saw it.
    case swallowed(KeyStroke)
    /// The tap has stopped and nothing more will be taken.
    case stopped(KeyInterceptorFailure)
}

/// Takes the keys a suggestion has claimed and passes every other key through. See `Docs/predict-accept.md`.
public final class KeyInterceptor: Sendable {
    /// What was taken, in the order it was taken.
    public let events: AsyncStream<InterceptedEvent>

    private let state: TapState
    private let drain: any DispatchSourceUserDataAdd
    private let running = Mutex<RunningTap?>(nil)

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
        let tap = try RunningTap.create(state: state)
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
private final class RunningTap: @unchecked Sendable {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let loop = Mutex<CFRunLoop?>(nil)

    private init(tap: CFMachPort, source: CFRunLoopSource) {
        self.tap = tap
        self.source = source
    }

    /// Builds the tap, or says that the system would not.
    static func create(state: TapState) throws(KeyInterceptorFailure) -> RunningTap {
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
                callback: keyInterceptorCallback,
                userInfo: state.pointer),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { throw .tapRefused }
        state.adopt(tap)
        return RunningTap(tap: tap, source: source)
    }

    /// A thread of its own, because a tap starved by a busy run loop is a tap the system disables.
    func run() {
        let thread = Thread { [self] in
            loop.withLock { $0 = CFRunLoopGetCurrent() }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "co.uttrflow.key-interceptor"
        // Above the default, so a keystroke is decided before the app about to receive it wakes.
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(tap)
        if let loop = loop.withLock({ $0 }) { CFRunLoopStop(loop) }
    }
}

/// Everything the C callback may touch, held where a raw pointer can reach it.
private final class TapState: @unchecked Sendable {
    /// How many taken keystrokes may wait for the drain before the oldest are dropped.
    static let capacity = 64

    /// The ring value that stands for the tap giving up rather than for a key.
    static let gaveUp: UInt32 = .max

    /// Which slots are being taken, and the only thing the callback loads.
    let armed = Atomic<UInt32>(0)

    /// Written by the tap's thread and read by the drain, so one producer meets one consumer.
    private let ring: UnsafeMutablePointer<UInt32>
    private let written = Atomic<UInt64>(0)
    private let read = Atomic<UInt64>(0)
    private let disables = Atomic<Int>(0)
    private let tapPointer = Atomic<UnsafeMutableRawPointer?>(nil)
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

    /// The pointer handed to `tapCreate`, which is this object without a retain.
    var pointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    /// Keeps the port where the callback can re-enable the tap without taking a lock.
    func adopt(_ port: CFMachPort) {
        tapPointer.store(Unmanaged.passRetained(port).toOpaque(), ordering: .releasing)
    }

    /// The port to re-enable, read only on the path where the tap has already been disabled.
    func port() -> CFMachPort? {
        guard let held = tapPointer.load(ordering: .acquiring) else { return nil }
        return Unmanaged<CFMachPort>.fromOpaque(held).takeUnretainedValue()
    }

    /// Records one taken keystroke, in two stores and one dispatch call.
    func enqueue(_ slot: UInt32) {
        let next = written.load(ordering: .relaxed)
        ring[Int(next % UInt64(Self.capacity))] = slot
        written.store(next &+ 1, ordering: .releasing)
        signal.add(data: 1)
    }

    /// Whether the tap should be turned back on, which it is once and not twice.
    func shouldReEnable() -> Bool {
        guard disables.wrappingAdd(1, ordering: .relaxed).newValue < 2 else {
            enqueue(Self.gaveUp)
            return false
        }
        return true
    }

    /// Everything written since the last drain, oldest first.
    func take() -> [InterceptedEvent] {
        let end = written.load(ordering: .acquiring)
        var cursor = read.load(ordering: .relaxed)
        // A producer this far ahead has lapped the ring, so the oldest keystrokes are gone.
        if end &- cursor > UInt64(Self.capacity) { cursor = end &- UInt64(Self.capacity) }
        var events: [InterceptedEvent] = []
        while cursor < end {
            let slot = ring[Int(cursor % UInt64(Self.capacity))]
            if slot == Self.gaveUp {
                events.append(.stopped(.disabledTwice))
            } else if let stroke = ArmedKeys.stroke(of: ArmedKeys(rawValue: slot)) {
                events.append(.swallowed(stroke))
            }
            cursor &+= 1
        }
        read.store(cursor, ordering: .relaxed)
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
