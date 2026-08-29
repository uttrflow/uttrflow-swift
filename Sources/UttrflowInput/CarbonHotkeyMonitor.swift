private import Carbon
private import Foundation
public import UttrflowCore
private import Synchronization

/// The shortcut, watched through Carbon's hot key API.
///
/// Why Carbon rather than a `CGEventTap`: a tap sees nothing until the user has granted
/// Accessibility, so the app would have to ask for permission to read every keystroke
/// in every app merely to learn when to start listening — before it has ever done
/// anything useful. `RegisterEventHotKey` needs no permission at all, delivers the
/// release as well as the press (which hold-to-talk is built on), and was measured here
/// at well under a tenth of a millisecond. The price is that Carbon swallows the
/// keystroke — there is no pass-through option — which for a shortcut reserved for
/// dictation is what we want anyway.
///
/// Excluded from the coverage gate: what is left once the shortcut has been translated
/// is a registration with the window server, and there is nothing to assert about it
/// beyond "macOS did what we asked". Everything decidable lives in ``CarbonHotkey``.
public final class CarbonHotkeyMonitor: HotkeyMonitoring {
    /// Identifies our hot keys in the shared Carbon event stream: 'KHTP'.
    fileprivate static let signature = OSType(0x4B48_5450)

    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let registration = Mutex<CarbonRegistration?>(nil)

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    /// The one Carbon event handler this process installs, whatever the shortcut.
    ///
    /// `InstallEventHandler` refuses the same handler function on the same target twice
    /// — `eventHandlerAlreadyInstalledErr`, −9866 — so a second `CarbonHotkeyMonitor`
    /// used to fail outright. That is not hypothetical: the clipboard panel has a
    /// shortcut of its own, and whichever monitor registered second silently got
    /// nothing. Dictation lost, which is how ⌥Space stopped working.
    ///
    /// One install for the process is not a workaround, it is what the design already
    /// assumed: the handler dispatches on `EventHotKeyID.id` through ``hotkeySinks``, so
    /// it has always been able to serve any number of shortcuts. Only the *installing*
    /// was wrongly per-instance.
    ///
    /// Never removed. It costs nothing to leave in place, and removing it while another
    /// monitor still holds a hot key is the same bug from the other end.
    private static let sharedHandler = Mutex<EventHandlerRef?>(nil)

    @MainActor
    private static func installSharedHandler(_ specs: inout [EventTypeSpec]) -> Bool {
        sharedHandler.withLock { installed in
            if installed != nil { return true }
            var handler: EventHandlerRef?
            // MEASURED FOOTGUN: the handler must be installed on the *same* event target
            // the hot key is registered against. Pairing `GetApplicationEventTarget()`
            // here with `GetEventDispatcherTarget()` below returns noErr from both calls
            // and then never fires. Both say `GetEventDispatcherTarget()` for that
            // reason, and must keep saying the same thing.
            let status = InstallEventHandler(
                GetEventDispatcherTarget(), carbonHotkeyHandler, specs.count, &specs, nil,
                &handler)
            guard status == noErr, handler != nil else { return false }
            installed = handler
            return true
        }
    }

    /// Registers the shortcut and reports the outcome before returning.
    ///
    /// ``HotkeyError/observationNotPermitted`` is never thrown from here: needing no
    /// permission is the reason Carbon was chosen. The other case is thrown for both
    /// ways this can fail, because to the user they are one thing — the shortcut they
    /// asked for is not going to work — and only one of them can be told apart anyway.
    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        // Translation rejects the shortcuts Carbon accepts and then never delivers on.
        // A user with a hand-edited preferences file can reach this, so it is reported
        // rather than asserted.
        guard let hotkey = try? CarbonHotkey(binding: binding) else {
            throw .shortcutUnavailable
        }
        try register(hotkey)
    }

    /// Not main-actor isolated, unlike ``start(binding:)``, because undoing has no
    /// outcome to report and Carbon takes the two refs back from any thread. Keeping it
    /// callable from anywhere is what lets a controller shut down without a hop.
    public func stop() {
        onMainThread { self.unregister() }
    }

    // MARK: Carbon

    /// Main-actor isolated for the reason ``HotkeyMonitoring/start(binding:)`` gives:
    /// Carbon delivers a hot key on the run loop of the thread that registered it, and
    /// the main thread is the only one running one.
    @MainActor
    private func register(_ hotkey: CarbonHotkey) throws(HotkeyError) {
        // A second start rebinds rather than leaking the first registration.
        unregister()

        let identifier = nextHotkeyIdentifier()
        let continuation = continuation
        hotkeySinks.withLock { $0[identifier] = { continuation.yield($0) } }

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
            // Fails when another app already owns the combination. The shared handler
            // stays: it belongs to the process, not to this registration.
            hotkeySinks.withLock { $0[identifier] = nil }
            throw .shortcutUnavailable
        }

        registration.withLock {
            $0 = CarbonRegistration(identifier: identifier, hotKey: hotKey)
        }
    }

    private func unregister() {
        guard
            let live = registration.withLock({ registration -> CarbonRegistration? in
                defer { registration = nil }
                return registration
            })
        else { return }

        hotkeySinks.withLock { $0[live.identifier] = nil }
        _ = UnregisterEventHotKey(live.hotKey)
        // The stream is deliberately not finished: stopping is not the end of the app,
        // and a finished stream could never be started again.
    }
}

/// What has to be handed back to Carbon to undo a registration.
///
/// The two refs are opaque handles to window-server objects, which Carbon is happy to
/// take from any thread; they carry no Swift state to race over. In practice they are
/// only ever made and used on the main thread, under the mutex that holds this value.
/// One registered shortcut. No handler: that is the process's, not this shortcut's.
private struct CarbonRegistration: @unchecked Sendable {
    let identifier: UInt32
    let hotKey: EventHotKeyRef
}

/// Where a fired hot key goes, keyed by the id Carbon carries in the event.
///
/// The handler is a C function pointer and so can capture nothing. The alternative —
/// passing the monitor to Carbon as a `userData` pointer — would mean promising, with
/// an unchecked-Sendable box, that an object stays alive for a registration whose
/// lifetime Carbon does not track. Keying a registry on the `EventHotKeyID` that Carbon
/// already puts in the event means only a `UInt32` crosses the C boundary, and the
/// mutex is the whole of the concurrency story.
private let hotkeySinks = Mutex<[UInt32: @Sendable (HotkeyEvent) -> Void]>([:])

private let lastHotkeyIdentifier = Mutex<UInt32>(0)

/// Never reused, so a callback still in flight for a stopped monitor cannot land on the
/// next one.
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

/// Carbon wants the main thread, and ``CarbonHotkeyMonitor/stop()`` can be called from
/// anywhere. Registration does not come through here: it has an outcome to return, so
/// its caller hops first and the isolation is stated in the signature instead.
private func onMainThread(_ work: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
