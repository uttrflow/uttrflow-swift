import CoreGraphics
import Foundation
import Synchronization

/// Holds the reader across the C callback boundary, and owns the lock guarding it.
private final class Reception: @unchecked Sendable {
    private let reader = Mutex<(@Sendable (UInt64) -> Void)?>(nil)

    func set(_ value: (@Sendable (UInt64) -> Void)?) { reader.withLock { $0 = value } }
    func read(_ flags: UInt64) { reader.withLock { $0 }?(flags) }
}

/// Reads modifier flags from a session tap, which reports Fn where an `NSEvent` monitor reports nothing.
public final class HeldModifierTap: Sendable {
    private let reception = Reception()
    private let running = Mutex<RunningFlagsTap?>(nil)

    public init() {}

    /// Starts watching, or says the system refused the tap, which it does without Accessibility.
    public func start(reader: @escaping @Sendable (UInt64) -> Void) throws(HeldModifierTapError) {
        stop()
        reception.set(reader)
        guard let tap = RunningFlagsTap.create(reception: reception) else { throw .tapRefused }
        tap.run()
        running.withLock { $0 = tap }
    }

    public func stop() {
        running.withLock { current in
            current?.stop()
            current = nil
        }
        reception.set(nil)
    }

    deinit { stop() }
}

/// Why the flags tap could not be put in place.
public enum HeldModifierTapError: Error {
    /// The system refused the tap, which it does without the Accessibility grant.
    case tapRefused
}

/// The tap, its run loop source, and the thread the two live on.
private final class RunningFlagsTap: @unchecked Sendable {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let loop = Mutex<CFRunLoop?>(nil)
    private let held: Unmanaged<Reception>

    private init(tap: CFMachPort, source: CFRunLoopSource, held: Unmanaged<Reception>) {
        self.tap = tap
        self.source = source
        self.held = held
    }

    /// Listening rather than consuming, so Fn keeps doing whatever the Mac is set to do with it.
    static func create(reception: Reception) -> RunningFlagsTap? {
        let held = Unmanaged.passRetained(reception)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue,
                callback: heldModifierTapCallback,
                userInfo: held.toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            held.release()
            return nil
        }
        return RunningFlagsTap(tap: tap, source: source, held: held)
    }

    /// A thread of its own, for the reason `KeyInterceptor` uses one: a starved tap is a disabled tap.
    func run() {
        let thread = Thread { [self] in
            loop.withLock { $0 = CFRunLoopGetCurrent() }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "co.uttrflow.held-modifier-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(tap)
        if let loop = loop.withLock({ $0 }) { CFRunLoopStop(loop) }
        held.release()
    }
}

/// The tap's callback; a tap the system disables is re-enabled rather than left silent for ever.
private func heldModifierTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let reception = Unmanaged<Reception>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .flagsChanged { reception.read(event.flags.rawValue) }
    return Unmanaged.passUnretained(event)
}
