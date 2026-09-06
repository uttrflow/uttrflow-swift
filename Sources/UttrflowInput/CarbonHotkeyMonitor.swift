private import Carbon
private import CoreGraphics
private import Dispatch
private import Foundation
public import UttrflowCore
private import Synchronization

/// The shortcut, registered with Carbon, which needs no permission. See `Docs/shortcuts.md`.
public final class CarbonHotkeyMonitor: HotkeyMonitoring {
    /// Identifies our hot keys in the shared Carbon event stream: 'KHTP'.
    fileprivate static let signature = OSType(0x4B48_5450)

    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let registration = Mutex<CarbonRegistration?>(nil)

    /// Whether a press has been reported with no release yet.
    private let held = Mutex<HeldModifierEdge>(HeldModifierEdge())

    /// The timer comparing the real key state against what Carbon has reported.
    private let reconciliation = Mutex<(any DispatchSourceTimer)?>(nil)

    /// How often that comparison runs, in milliseconds.
    private static let reconciliationMilliseconds = 250

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `stop()`, which hops to a main thread this may never come back from.
        reconciliation.withLock { $0?.cancel() }
        if let live = registration.withLock({ $0 }) {
            hotkeySinks.withLock { $0[live.identifier] = nil }
            _ = UnregisterEventHotKey(live.hotKey)
        }
    }

    /// The one handler this process installs, never removed, dispatching every shortcut by id.
    private static let sharedHandler = Mutex<EventHandlerRef?>(nil)

    @MainActor
    private static func installSharedHandler(_ specs: inout [EventTypeSpec]) -> Bool {
        sharedHandler.withLock { installed in
            if installed != nil { return true }
            var handler: EventHandlerRef?
            // Must be the same target the hot key registers against, or nothing ever fires.
            let status = InstallEventHandler(
                GetEventDispatcherTarget(), carbonHotkeyHandler, specs.count, &specs, nil,
                &handler)
            guard status == noErr, handler != nil else { return false }
            installed = handler
            return true
        }
    }

    /// Registers the shortcut and reports the outcome before returning.
    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        // Rejects what Carbon accepts and never delivers, which a hand-edited file can ask for.
        guard let hotkey = try? CarbonHotkey(binding: binding) else {
            throw .shortcutUnavailable
        }
        try register(hotkey)
    }

    /// Callable from anywhere, unlike ``start(binding:)``, so a controller can shut down without a hop.
    public func stop() {
        onMainThread { self.unregister() }
    }

    // MARK: Carbon

    /// Main-actor isolated: Carbon delivers on the run loop of the registering thread.
    @MainActor
    private func register(_ hotkey: CarbonHotkey) throws(HotkeyError) {
        // A second start rebinds rather than leaking the first registration.
        unregister()

        let identifier = nextHotkeyIdentifier()
        hotkeySinks.withLock { sinks in
            sinks[identifier] = { [weak self] in self?.deliver($0, keyCode: hotkey.keyCode) }
        }

        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        guard Self.installSharedHandler(&specs) else {
            hotkeySinks.withLock { $0[identifier] = nil }
            throw .shortcutUnavailable
        }

        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifierMask,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr, let hotKey else {
            // Fails when another app owns the combination; the shared handler stays.
            hotkeySinks.withLock { $0[identifier] = nil }
            throw .shortcutUnavailable
        }

        registration.withLock {
            $0 = CarbonRegistration(identifier: identifier, hotKey: hotKey)
        }
    }

    /// Reports one event, and only when it changes whether the key is down.
    private func deliver(_ event: HotkeyEvent, keyCode: UInt32) {
        let happened = held.withLock { $0.flagsChanged(isDownNow: event == .pressed) }
        guard let happened else { return }
        // Only while a key is down, so an idle app never wakes and no timer outlives one.
        switch happened {
        case .pressed: startReconciling(keyCode)
        case .released: stopReconciling()
        }
        continuation.yield(happened)
    }

    /// Reads the real key state, so a release Carbon never delivers is still noticed. See `Docs/stuck-recording.md`.
    private func startReconciling(_ keyCode: UInt32) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.reconciliationMilliseconds),
            repeating: .milliseconds(Self.reconciliationMilliseconds))
        timer.setEventHandler { [weak self] in
            // A monitor released mid-hold cancels its own timer rather than firing for ever.
            guard let self else { timer.cancel(); return }
            guard held.withLock({ $0.isDown }) else { return }
            guard !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
            else { return }
            deliver(.released, keyCode: keyCode)
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

    private func unregister() {
        stopReconciling()
        // A hold interrupted by unregistering is a release, or the microphone stays open.
        let owed = held.withLock { $0.stopped() }
        if let owed { continuation.yield(owed) }
        guard
            let live = registration.withLock({ registration -> CarbonRegistration? in
                defer { registration = nil }
                return registration
            })
        else { return }

        hotkeySinks.withLock { $0[live.identifier] = nil }
        _ = UnregisterEventHotKey(live.hotKey)
        // Not finished: a finished stream could never be started again.
    }
}

/// One registered shortcut, as opaque handles Carbon takes back from any thread.
private struct CarbonRegistration: @unchecked Sendable {
    let identifier: UInt32
    let hotKey: EventHotKeyRef
}

/// Where a fired hot key goes, so only a `UInt32` crosses the C boundary.
private let hotkeySinks = Mutex<[UInt32: @Sendable (HotkeyEvent) -> Void]>([:])

private let lastHotkeyIdentifier = Mutex<UInt32>(0)

/// Never reused, so a callback in flight for a stopped monitor cannot land on the next.
private func nextHotkeyIdentifier() -> UInt32 {
    lastHotkeyIdentifier.withLock { identifier in
        identifier += 1
        return identifier
    }
}

private let carbonHotkeyHandler: EventHandlerUPP = { _, event, _ -> OSStatus in
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
    guard status == noErr, hotkeyID.signature == CarbonHotkeyMonitor.signature,
        let sink = hotkeySinks.withLock({ $0[hotkeyID.id] })
    else { return OSStatus(eventNotHandledErr) }

    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed): sink(.pressed)
    case UInt32(kEventHotKeyReleased): sink(.released)
    default: return OSStatus(eventNotHandledErr)
    }
    return OSStatus(noErr)
}

/// Hops to the main thread, which Carbon wants and ``CarbonHotkeyMonitor/stop()`` cannot promise.
private func onMainThread(_ work: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
