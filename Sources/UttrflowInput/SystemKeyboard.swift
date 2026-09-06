import CoreGraphics
import Foundation
import Synchronization

public import UttrflowCore

/// The one place the product asks the window server what the keyboard is doing. See `Docs/shortcuts.md`.
public final class SystemKeyboard: KeyboardEventSource {
    private let delivery = Delivery()
    private let running = Mutex<RunningTap?>(nil)

    public init() {}

    public func start(_ deliver: @escaping @Sendable (KeyStroke) -> Void) throws(KeyboardSourceError) {
        stop()
        delivery.set(deliver)
        guard let tap = RunningTap.create(delivery: delivery) else { throw .refused }
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
        return KeyStroke(
            keyCode: keyCode, modifiers: modifiers,
            isFunctionDown: flags.contains(.maskSecondaryFn), phase: phase)
    }
}

/// Holds the sink across the C callback boundary, and owns the lock guarding it.
private final class Delivery: @unchecked Sendable {
    private let sink = Mutex<(@Sendable (KeyStroke) -> Void)?>(nil)

    func set(_ value: (@Sendable (KeyStroke) -> Void)?) { sink.withLock { $0 = value } }
    func send(_ stroke: KeyStroke) { sink.withLock { $0 }?(stroke) }
}

/// The tap, its run loop source, and the thread the two live on.
private final class RunningTap: @unchecked Sendable {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let loop = Mutex<CFRunLoop?>(nil)
    private let held: Unmanaged<Delivery>

    private init(tap: CFMachPort, source: CFRunLoopSource, held: Unmanaged<Delivery>) {
        self.tap = tap
        self.source = source
        self.held = held
    }

    /// Listening rather than consuming, so every key keeps doing what it did before Uttrflow ran.
    static func create(delivery: Delivery) -> RunningTap? {
        let held = Unmanaged.passRetained(delivery)
        let mask =
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: systemKeyboardCallback, userInfo: held.toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            held.release()
            return nil
        }
        return RunningTap(tap: tap, source: source, held: held)
    }

    /// A thread of its own, for the reason `KeyInterceptor` uses one: a starved tap is a disabled tap.
    func run() {
        let thread = Thread { [self] in
            loop.withLock { $0 = CFRunLoopGetCurrent() }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "co.uttrflow.keyboard"
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

/// The tap's callback, which reads an event into the domain and hands it on.
private func systemKeyboardCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let delivery = Unmanaged<Delivery>.fromOpaque(userInfo).takeUnretainedValue()
    let phase: KeyPhase? =
        switch type {
        case .flagsChanged: .modifiersChanged
        case .keyDown: .down
        case .keyUp: .up
        default: nil
        }
    if let phase {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        delivery.send(SystemKeyboard.stroke(keyCode: keyCode, flags: event.flags, phase: phase))
    }
    return Unmanaged.passUnretained(event)
}
