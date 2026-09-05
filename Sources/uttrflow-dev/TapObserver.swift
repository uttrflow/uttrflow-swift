private import CoreGraphics
private import Foundation
private import Synchronization

/// Holds an event tap open, swallowing Tab and counting what the system does to it.
final class TapObserver: @unchecked Sendable {
    private struct Counts {
        var tabsSwallowed = 0
        var otherKeys = 0
        var disables = 0
        var reEnables = 0
    }

    private let counts = Mutex(Counts())
    private let stalls: Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Tab's virtual key code, the one key this probe takes.
    private static let tabKeyCode: Int64 = 48

    init(stalling: Bool) {
        self.stalls = stalling
    }

    /// Opens the tap on this thread's run loop, answering whether the system allowed it.
    func start() -> Bool {
        let mask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: forward,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Closes the tap, leaving the keyboard exactly as it was found.
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Decides one event, swallowing Tab and re-enabling the tap when the system disables it.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            counts.withLock { $0.disables += 1 }
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                counts.withLock { $0.reEnables += 1 }
            }
            return nil
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.tabKeyCode else {
            counts.withLock { $0.otherKeys += 1 }
            return Unmanaged.passUnretained(event)
        }
        if stalls { Thread.sleep(forTimeInterval: 2) }
        counts.withLock { $0.tabsSwallowed += 1 }
        return nil
    }

    /// What the run proved, in the order the phase 0 report wants it.
    func summary() -> String {
        let seen = counts.withLock { $0 }
        return """
            Tab swallowed          \(seen.tabsSwallowed)
            Other keys passed on   \(seen.otherKeys)
            Disabled by the system \(seen.disables)
            Re-enabled             \(seen.reEnables)
            """
    }
}

/// Bridges the C callback back to the observer that owns the tap.
private func forward(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TapObserver>.fromOpaque(refcon).takeUnretainedValue()
        .handle(type: type, event: event)
}
