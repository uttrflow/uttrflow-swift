import AppKit
import CoreGraphics
import Synchronization

public import UttrflowCore

/// Watches for a modifier held down, which the window server will not deliver as a hot key. See `Docs/shortcuts.md`.
public final class HeldModifierMonitor: HotkeyMonitoring {
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    public let events: AsyncStream<HotkeyEvent>

    /// The two monitor tokens and the edge, under one lock because `deinit` runs anywhere.
    private let state = Mutex<Watch>(Watch())

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `stop()`, which is main-actor isolated, and this can be released anywhere.
        tap.stop()
        reconciliation.withLock { $0?.cancel() }
        state.withLock { $0.removeMonitors() }
        continuation.finish()
    }

    /// The exact flags this binding is a hold of, stored rather than recomputed per event.
    private let watchedFlags = Mutex<NSEvent.ModifierFlags>([])

    /// The timer comparing the real key state against what events have reported.
    private let reconciliation = Mutex<(any DispatchSourceTimer)?>(nil)

    /// The session tap, which is the only one of the three that ever reports Fn.
    private let tap = HeldModifierTap()

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        guard binding.heldModifier != nil else { throw .shortcutUnavailable }
        watchedFlags.withLock { $0 = Self.flags(for: binding) }

        // The global half needs the same Accessibility grant the typing does.
        guard AXIsProcessTrusted() else { throw .observationNotPermitted }

        stop()

        // A session tap as well, because the global monitor is never told about Fn.
        try? tap.start { [weak self] flags in
            // Straight through: the edge is behind a lock, and it absorbs a duplicate reading.
            self?.update(with: NSEvent.ModifierFlags(rawValue: UInt(flags)))
        }
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

    /// The flags a binding is a hold of, answering Fn first because it names none of the four.
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

    /// Every flag this monitor considers, so an unnamed flag is not counted as a difference.
    private static let consideredFlags: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift, .function,
    ]

    private func handle(_ event: NSEvent) {
        update(with: event.modifierFlags)
    }

    /// Feeds one reading of the flags to the edge, matching by equality so ⌃⌥ is not ⌃⌥⌘.
    private func update(with flags: NSEvent.ModifierFlags) {
        let wanted = watchedFlags.withLock { $0 }
        let present = flags.intersection(Self.consideredFlags)
        let isDownNow = !wanted.isEmpty && present == wanted
        let happened = state.withLock { $0.edge.flagsChanged(isDownNow: isDownNow) }
        guard let happened else { return }
        // Only while a key is down, so an idle app never wakes and no timer outlives one.
        switch happened {
        case .pressed: startReconciling()
        case .released: stopReconciling()
        }
        continuation.yield(happened)
    }

    /// How often the real key state is checked, in milliseconds: below noticing, above nothing.
    private static let reconciliationMilliseconds = 250

    /// The modifiers held right now, read from the session rather than from the event stream.
    static func polledFlags() -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
            .union(NSEvent.modifierFlags)
    }

    /// Whether a held key of these flags shows up in the polled state at all; Fn does not.
    static func polledStateCanSee(_ wanted: NSEvent.ModifierFlags) -> Bool {
        !wanted.contains(.function)
    }

    /// Reads the flags directly, so a release that is never delivered is still noticed. See `Docs/stuck-recording.md`.
    private func startReconciling() {
        // Only against a source that can see this key, or Fn reads "up" mid-hold and cancels itself.
        guard Self.polledStateCanSee(watchedFlags.withLock { $0 }) else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.reconciliationMilliseconds),
            repeating: .milliseconds(Self.reconciliationMilliseconds))
        timer.setEventHandler { [weak self] in
            // A monitor released mid-hold cancels its own timer rather than firing for ever.
            guard let self else { timer.cancel(); return }
            update(with: Self.polledFlags())
        }
        timer.resume()
        reconciliation.withLock { existing in
            existing?.cancel()
            existing = timer
        }
    }

    private func stopReconciling() {
        reconciliation.withLock { timer in
            timer?.cancel()
            timer = nil
        }
    }

    public func stop() {
        tap.stop()
        stopReconciling()
        // A hold interrupted by stopping is a release, or the microphone stays open.
        let owed = state.withLock { watch -> HotkeyEvent? in
            watch.removeMonitors()
            return watch.edge.stopped()
        }
        if let owed { continuation.yield(owed) }
    }
}

/// What one watch owns: the two monitor tokens, and the edge it is tracking.
private struct Watch: @unchecked Sendable {
    /// `Any?` is what `NSEvent` hands back, and removing one is safe from any thread.
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
