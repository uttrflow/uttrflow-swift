import AppKit
import Synchronization

public import UttrflowCore

/// Watches for a modifier held down, rather than registering a shortcut.
///
/// `RegisterEventHotKey` — which ``CarbonHotkeyMonitor`` uses for every other binding —
/// accepts a modifier on its own and then never fires it. The window server simply does
/// not deliver a hot key whose key *is* a modifier. So Fn is watched instead: the flags
/// change when it goes down and again when it comes up, and those two are the press and
/// the release that hold-to-talk is built on.
///
/// Two monitors, because one is not enough. A global monitor sees every app except this
/// one; a local monitor sees only this one. Uttrflow is a menu-bar app that people
/// dictate *into other applications* from, so the global monitor is the one that matters
/// — but without the local one the shortcut would be dead in Uttrflow's own windows,
/// which is exactly where somebody tries it first after turning it on.
///
/// **This cannot suppress what macOS does with Fn.** An `NSEvent` monitor observes; it
/// cannot consume. If the Mac is set to show the emoji picker or start Apple's own
/// dictation on Fn, that still happens, and both fire alongside this. The setting lives
/// in System Settings → Keyboard → "Press 🌐 to", and the only honest thing to do is say
/// so where the shortcut is chosen rather than let it look like a bug here.
public final class HeldModifierMonitor: HotkeyMonitoring {
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    public let events: AsyncStream<HotkeyEvent>

    /// The two monitor tokens and whether the key is currently down, under one lock.
    ///
    /// A `Mutex` rather than main-actor storage for the reason ``CarbonHotkeyMonitor``
    /// uses one: the type is `Sendable`, `deinit` can run anywhere, and `stop()` is not
    /// main-actor isolated in the protocol.
    ///
    /// The edge it is tracking is ``HeldModifierEdge``, which is where both of the rules
    /// that matter live — a flags change reports what the flags *are* rather than what
    /// changed, and a hold interrupted by stopping still owes a release. Kept there
    /// rather than here because this type cannot be tested and that one can.
    private let state = Mutex<Watch>(Watch())

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `stop()`: that is main-actor isolated and this can be released anywhere.
        // Removing a monitor is safe from any thread, and the continuation must be
        // finished or a consumer awaits a stream nothing will ever write to again.
        state.withLock { $0.removeMonitors() }
        continuation.finish()
    }

    /// The exact flags this binding is a hold of. Read by ``handle(_:)`` on every flags
    /// change, so it is stored rather than recomputed from a key code each time.
    private let watched = Mutex<NSEvent.ModifierFlags>([])

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        guard binding.heldModifier != nil else { throw .shortcutUnavailable }
        watched.withLock { $0 = Self.flags(for: binding) }

        // The global half needs the same Accessibility grant the typing does. Asked for
        // rather than assumed, so a Mac that has not granted it is told which failure it
        // met instead of watching a shortcut silently do nothing.
        guard AXIsProcessTrusted() else { throw .observationNotPermitted }

        stop()

        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handle($0)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            // Passed on, always. Uttrflow's own windows need their modifiers.
            return event
        }
        state.withLock {
            $0.global = global
            $0.local = local
        }
    }

    /// The flags a binding is a hold of.
    ///
    /// Fn is its own flag and carries none of the four this app names, which is why it is
    /// answered first rather than falling through to an empty set.
    static func flags(for binding: HotkeyBinding) -> NSEvent.ModifierFlags {
        if binding.isFunctionHold { return .function }
        var flags: NSEvent.ModifierFlags = []
        for modifier in binding.modifiers {
            switch modifier {
            case .command: flags.insert(.command)
            case .option: flags.insert(.option)
            case .control: flags.insert(.control)
            case .shift: flags.insert(.shift)
            }
        }
        return flags
    }

    /// Every flag this monitor is willing to consider, so that a flag the binding does not
    /// name can be told apart from one it does.
    private static let considered: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift, .function,
    ]

    private func handle(_ event: NSEvent) {
        let wanted = watched.withLock { $0 }
        // **Equality, not containment.** ⌃⌥ and ⌃⌥⌘ are different holds, and matching a
        // superset would mean a ⌃⌥ binding firing on the way to every ⌃⌥⌘ shortcut —
        // dictation starting and stopping under somebody reaching for something else.
        // Comparing only the flags this monitor considers keeps Caps Lock or a numeric
        // keypad flag from counting as a difference.
        let present = event.modifierFlags.intersection(Self.considered)
        let isDownNow = !wanted.isEmpty && present == wanted
        let happened = state.withLock { $0.edge.flagsChanged(isDownNow: isDownNow) }
        guard let happened else { return }
        continuation.yield(happened)
    }

    public func stop() {
        // A hold interrupted by stopping is a release, or whatever was listening waits
        // for an end that never comes and the microphone stays open. See
        // ``HeldModifierEdge``, where that rule is stated once and tested.
        let owed = state.withLock { watch -> HotkeyEvent? in
            watch.removeMonitors()
            return watch.edge.stopped()
        }
        if let owed { continuation.yield(owed) }
    }
}

/// What one watch owns: the two monitor tokens, and the edge it is tracking.
private struct Watch: @unchecked Sendable {
    /// `Any?` is what `NSEvent` hands back. It carries no Swift state of ours to race
    /// over, and removing one is documented as safe from any thread.
    var global: Any?
    var local: Any?
    var edge = HeldModifierEdge()

    mutating func removeMonitors() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
}
