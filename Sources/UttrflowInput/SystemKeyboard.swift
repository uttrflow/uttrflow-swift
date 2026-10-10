import CoreGraphics
import Foundation
import Synchronization

public import UttrflowCore

/// The one place the product asks the window server what the keyboard is doing. See `Docs/shortcuts.md`.
public final class SystemKeyboard: KeyboardEventSource {
    /// The sink the tap reads; internal so tests can see a restart forget the old tap's disables.
    let delivery = Delivery()
    private let running = Mutex<RunningTap?>(nil)
    /// Builds the tap's port; `nil` is the real session tap, and tests pass a plain port.
    private let makePort: (@Sendable (UnsafeMutableRawPointer, Bool) -> CFMachPort?)?

    public init() { makePort = nil }

    /// Takes the port maker, so a test can run the real tap thread without Accessibility.
    init(makePort: @escaping @Sendable (UnsafeMutableRawPointer, Bool) -> CFMachPort?) {
        self.makePort = makePort
    }

    public func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        stop()
        delivery.set(deliver)
        delivery.setConsumeKeyDown(consumeKeyDown)
        guard let tap = RunningTap.create(delivery: delivery, consume: consumeKeyDown, makePort: makePort)
        else { throw .refused }
        tap.run()
        running.withLock { $0 = tap }
    }

    public func stop() {
        TeardownGuard.once(for: self) {
            running.withLock { current in
                current?.stop()
                current = nil
            }
            delivery.set(nil)
            delivery.forgetDisables()
        }
    }

    public func onGaveUp(_ handler: @escaping @Sendable () -> Void) {
        delivery.setGaveUpHandler(handler)
    }

    deinit { stop() }

    /// The domain reading of a CoreGraphics event, kept here so nothing else decodes flags.
    static func stroke(keyCode: UInt16, flags: CGEventFlags, phase: KeyPhase) -> KeyEvent {
        let modifiers = Set(HotkeyModifier.held(in: flags))
        let isFunctionDown = flags.contains(.maskSecondaryFn)
        return KeyEvent(
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
final class Delivery: TapPayload, @unchecked Sendable {
    /// The closure in a struct, since a bare closure read out of a `Mutex` is re-wrapped and written back.
    private struct Sink: Sendable {
        let call: @Sendable (KeyEvent) -> Void
    }

    private let sink = Mutex<Sink?>(nil)
    /// Whether the callback should return `nil` for key-down strokes, so a recorded ⌘Q does not also quit the app.
    private let consumeKeyDown = Atomic<Bool>(false)
    /// The port the callback revives and the disables counted against it.
    let tapPort: TapPort
    /// Told when the tap is left off for good, so the caller can notice and recover.
    private let gaveUpHandler = Mutex<(@Sendable () -> Void)?>(nil)

    /// Takes the clock disables are measured on, so a test can move it by hand.
    init(clock: some Clock<Duration> = ContinuousClock()) {
        tapPort = TapPort(clock: clock)
    }

    func set(_ value: (@Sendable (KeyEvent) -> Void)?) { sink.withLock { $0 = value.map(Sink.init) } }
    func setConsumeKeyDown(_ value: Bool) { consumeKeyDown.store(value, ordering: .relaxed) }
    func setGaveUpHandler(_ value: @escaping @Sendable () -> Void) { gaveUpHandler.withLock { $0 = value } }
    /// Hands the stroke to the sink and reports whether the callback should swallow the event.
    @discardableResult
    func send(_ stroke: KeyEvent) -> Bool {
        sink.withLock { $0 }?.call(stroke)
        return consumeKeyDown.load(ordering: .relaxed) && stroke.phase == .down
    }

    /// The port to revive, read only on the path where the system has already stopped delivering.
    func port() -> CFMachPort? { tapPort.port() }

    /// Clears the disable history, so a newly built tap is judged only on its own disables.
    func forgetDisables() { tapPort.forgetDisables() }

    /// Whether to turn the tap back on, which it is unless it keeps being disabled in a short window.
    func shouldReEnable() -> Bool {
        let reEnable = tapPort.shouldReEnable()
        if !reEnable {
            gaveUpHandler.withLock { $0 }?()
        }
        return reEnable
    }
}

/// The keyboard's tap, whose thread and stop handshake it shares with `KeyInterceptor`.
typealias RunningTap = EventTapThread<Delivery>

extension EventTapThread where Payload == Delivery {
    /// Listening rather than consuming, so every key keeps doing what it did before Uttrflow ran.
    static func create(
        delivery: Delivery, consume: Bool = false,
        makePort: ((UnsafeMutableRawPointer, Bool) -> CFMachPort?)? = nil,
        released: @escaping @Sendable () -> Void = {},
        beforeLoop: @escaping @Sendable () -> Void = {}
    ) -> RunningTap? {
        let build = makePort ?? RunningTap.keyboardTap
        return make(
            payload: delivery, name: "co.uttrflow.keyboard", makePort: { build($0, consume) },
            released: released, beforeLoop: beforeLoop)
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
}

/// The tap's callback, which reads an event into the domain and hands it on; internal so tests can drive it.
func systemKeyboardCallback(
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
    guard !SyntheticEvent.isOurs(event) else { return Unmanaged.passUnretained(event) }
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
