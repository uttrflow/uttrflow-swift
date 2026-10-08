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
        drain.setEventHandler(handler: nil)  // Also breaks the source-to-state cycle.
        drain.cancel()
    }

    /// Which keystrokes to take; the tap is off while none are and nothing is held, so no keystroke waits here.
    public func arm(_ keys: ArmedKeys) {
        _ = state.arm(keys)
    }

    /// Lets native application menus handle their own keyboard gestures until they close.
    public func setNativeMenuIsOpen(_ isOpen: Bool) {
        state.setNativeMenuIsOpen(isOpen)
    }

    /// Replays the keys held back since the last swallowed keystroke, once that keystroke has been carried out.
    public func releaseHeldKeys() {
        _ = state.releaseHeldKeys()
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
        state.stop()
    }
}

/// The key interceptor's tap, whose thread and stop handshake it shares with `SystemKeyboard`.
typealias InterceptorTap = EventTapThread<TapState>

extension EventTapThread where Payload == TapState {
    /// Builds the tap, or says that the system would not; `makePort`, `released` and `beforeLoop` are replaced only by tests.
    static func create(
        state: TapState,
        makePort: (UnsafeMutableRawPointer) -> CFMachPort? = InterceptorTap.keyDownTap,
        released: @escaping @Sendable () -> Void = {},
        beforeLoop: @escaping @Sendable () -> Void = {}
    ) throws(KeyInterceptorFailure) -> InterceptorTap {
        guard
            let tap = make(
                payload: state, name: "co.uttrflow.key-interceptor", makePort: makePort,
                released: released, beforeLoop: beforeLoop)
        else { throw .tapRefused }
        return tap
    }

    /// The session tap on key-down and key-up that `create` uses outside tests.
    static func keyDownTap(userInfo: UnsafeMutableRawPointer) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest:
                CGEventMask(1) << CGEventType.keyDown.rawValue
                | CGEventMask(1) << CGEventType.keyUp.rawValue,
            callback: keyInterceptorCallback,
            userInfo: userInfo)
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
        return state.takes(event) ? nil : Unmanaged.passUnretained(event)
    case .keyUp:
        // The tap listens for key-up so the autorepeat window closes on a real release, not when the insert finishes.
        guard !SyntheticEvent.isOurs(event) else { return Unmanaged.passUnretained(event) }
        state.keyUp(event)
        return Unmanaged.passUnretained(event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // Not the keystroke path: by the time this runs the system has already stopped delivering.
        state.reEnableIfListening()
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
