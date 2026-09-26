import CoreGraphics
import Foundation
import Synchronization

public import UttrflowCore

/// The one place the product asks the window server what the keyboard is doing. See `Docs/shortcuts.md`.
public final class SystemKeyboard: KeyboardEventSource {
    private let delivery = Delivery()
    private let running = Mutex<RunningTap?>(nil)

    public init() {}

    public func start(
        _ deliver: @escaping @Sendable (KeyStroke) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        stop()
        delivery.set(deliver)
        delivery.setConsumeKeyDown(consumeKeyDown)
        guard let tap = RunningTap.create(delivery: delivery, consume: consumeKeyDown)
        else { throw .refused }
        tap.run()
        running.withLock { $0 = tap }
    }

    public func stop() {
        running.withLock { current in
            current?.stop()
            current = nil
        }
        delivery.set(nil)
    }

    deinit { stop() }

    /// The domain reading of a CoreGraphics event, kept here so nothing else decodes flags.
    static func stroke(keyCode: UInt16, flags: CGEventFlags, phase: KeyPhase) -> KeyStroke {
        var modifiers: Set<HotkeyModifier> = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        let isFunctionDown = flags.contains(.maskSecondaryFn)
        return KeyStroke(
            keyCode: keyCode, modifiers: modifiers, isFunctionDown: isFunctionDown, phase: phase,
            isKeyDown: isDown(
                keyCode: keyCode, phase: phase, modifiers: modifiers,
                isFunctionDown: isFunctionDown))
    }

    /// Whether the named key is down, which for a flags change is whether its own modifier survived.
    static func isDown(
        keyCode: UInt16, phase: KeyPhase, modifiers: Set<HotkeyModifier>, isFunctionDown: Bool
    ) -> Bool {
        switch phase {
        case .down: true
        case .up: false
        case .modifiersChanged:
            if keyCode == HotkeyBinding.functionKeyCode {
                isFunctionDown
            } else if let named = HotkeyBinding.modifier(ofKeyCode: keyCode) {
                modifiers.contains(named)
            } else {
                false
            }
        }
    }
}

/// Holds the sink across the C callback boundary and the port to revive; internal so tests can drive it.
final class Delivery: @unchecked Sendable {
    /// The closure in a struct, since a bare closure read out of a `Mutex` is re-wrapped and written back.
    private struct Sink: Sendable {
        let call: @Sendable (KeyStroke) -> Void
    }

    private let sink = Mutex<Sink?>(nil)
    /// Whether the callback should return `nil` for key-down strokes, so a recorded ⌘Q does not also quit the app.
    private let consumeKeyDown = Atomic<Bool>(false)
    /// How many disables have counted against the tap inside the current window.
    private let disables = Atomic<Int>(0)
    /// When the last disable arrived, so two close together read as one fault.
    private let lastDisable = Atomic<UInt64>(0)
    /// The port, kept where the callback can revive the tap without taking a lock.
    private let tapPointer = Atomic<UnsafeMutableRawPointer?>(nil)

    deinit {
        if let held = tapPointer.load(ordering: .relaxed) {
            Unmanaged<CFMachPort>.fromOpaque(held).release()
        }
    }

    func set(_ value: (@Sendable (KeyStroke) -> Void)?) { sink.withLock { $0 = value.map(Sink.init) } }
    func setConsumeKeyDown(_ value: Bool) { consumeKeyDown.store(value, ordering: .relaxed) }
    /// Hands the stroke to the sink and reports whether the callback should swallow the event.
    @discardableResult
    func send(_ stroke: KeyStroke) -> Bool {
        sink.withLock { $0 }?.call(stroke)
        return consumeKeyDown.load(ordering: .relaxed) && stroke.phase == .down
    }

    /// Keeps the port the callback re-enables; the tap exists only after its own callback is written.
    func adopt(_ port: CFMachPort) {
        if let previous = tapPointer.exchange(
            Unmanaged.passRetained(port).toOpaque(), ordering: .releasing)
        {
            Unmanaged<CFMachPort>.fromOpaque(previous).release()
        }
    }

    /// The port to revive, read only on the path where the system has already stopped delivering.
    func port() -> CFMachPort? {
        guard let held = tapPointer.load(ordering: .acquiring) else { return nil }
        return Unmanaged<CFMachPort>.fromOpaque(held).takeUnretainedValue()
    }

    /// Whether to turn the tap back on, which it is unless it keeps being disabled in a short window.
    func shouldReEnable() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let last = lastDisable.exchange(now, ordering: .relaxed)
        let (count, reEnable) = TapDisableWindow.decide(
            last: last, now: now, count: disables.load(ordering: .relaxed))
        disables.store(count, ordering: .relaxed)
        return reEnable
    }
}

/// The tap, its run loop source, and the thread the two live on.
final class RunningTap: @unchecked Sendable {
    /// Where the tap is in its life, read and written under one lock so `stop` and the thread agree.
    private struct Lifecycle {
        var loop: CFRunLoop?
        /// Whether `run` has handed the release of the delivery to the thread.
        var started = false
        var stopped = false
    }

    /// The lock around `Lifecycle`, in a class so the thread can hold it without holding the tap.
    private final class LifecycleLock: Sendable {
        let lock = Mutex(Lifecycle())
    }

    /// What the tap's thread borrows, since the CoreFoundation types are not `Sendable`.
    private struct Loan: @unchecked Sendable {
        let tap: CFMachPort
        let source: CFRunLoopSource
    }

    private let tap: CFMachPort
    private let source: CFRunLoopSource
    /// The delivery the callback reads, retained until no callback can still be running.
    private let held: Unmanaged<Delivery>
    private let lifecycle = LifecycleLock()
    /// Called once the delivery is released, which tests wait on instead of a clock.
    private let released: @Sendable () -> Void
    /// Runs on the tap's thread before its run loop runs; tests use it to hold the thread mid-flight.
    private let beforeLoop: @Sendable () -> Void

    private init(
        tap: CFMachPort, source: CFRunLoopSource, held: Unmanaged<Delivery>,
        released: @escaping @Sendable () -> Void, beforeLoop: @escaping @Sendable () -> Void
    ) {
        self.tap = tap
        self.source = source
        self.held = held
        self.released = released
        self.beforeLoop = beforeLoop
    }

    /// Listening rather than consuming, so every key keeps doing what it did before Uttrflow ran.
    static func create(
        delivery: Delivery, consume: Bool = false,
        makePort: ((UnsafeMutableRawPointer, Bool) -> CFMachPort?)? = nil,
        released: @escaping @Sendable () -> Void = {},
        beforeLoop: @escaping @Sendable () -> Void = {}
    ) -> RunningTap? {
        let held = Unmanaged.passRetained(delivery)
        let make = makePort ?? RunningTap.keyboardTap
        guard
            let tap = make(held.toOpaque(), consume),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            held.release()
            return nil
        }
        delivery.adopt(tap)
        return RunningTap(
            tap: tap, source: source, held: held, released: released, beforeLoop: beforeLoop)
    }

    /// The session tap on key and modifier changes that `create` uses outside tests.
    static func keyboardTap(userInfo: UnsafeMutableRawPointer, consume: Bool) -> CFMachPort? {
        let mask =
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        // `defaultTap` is the only mode whose return value reaches the window server, so the recorder can swallow a key-down.
        let options: CGEventTapOptions = consume ? .defaultTap : .listenOnly
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
            eventsOfInterest: mask, callback: systemKeyboardCallback, userInfo: userInfo)
    }

    /// A thread of its own, for the reason `KeyInterceptor` uses one: a starved tap is a disabled tap.
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
        thread.name = "co.uttrflow.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs the tap's run loop until `stop`.
    private static func serve(_ loan: Loan, lifecycle: LifecycleLock, beforeLoop: () -> Void) {
        let (tap, source) = (loan.tap, loan.source)
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

    /// Stops the tap from any thread; the delivery is released once the tap's thread has left its run loop.
    func stop() {
        let (first, started, loop) = lifecycle.lock.withLock { life in
            defer { life.stopped = true }
            return (!life.stopped, life.started, life.loop)
        }
        guard first else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
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

/// The tap's callback, which reads an event into the domain and hands it on.
private func systemKeyboardCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let delivery = Unmanaged<Delivery>.fromOpaque(userInfo).takeUnretainedValue()
    // A tap the system switched off delivers nothing until it is asked back on. See KeyInterceptor.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if delivery.shouldReEnable(), let port = delivery.port() {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    let phase: KeyPhase? =
        switch type {
        case .flagsChanged: .modifiersChanged
        case .keyDown: .down
        case .keyUp: .up
        default: nil
        }
    if let phase {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let stroke = SystemKeyboard.stroke(keyCode: keyCode, flags: event.flags, phase: phase)
        if delivery.send(stroke) { return nil }
    }
    return Unmanaged.passUnretained(event)
}
