import Dispatch
import UttrflowCore
import Testing

@testable import UttrflowInput

/// A shortcut is re-registered through the real monitor without ever colliding with itself. See `Docs/shortcuts.md`.
@MainActor
@Suite("Re-registering a shortcut", .serialized)
struct CarbonHotkeyLifecycleTests {
    /// F13 and F15 with three modifiers: nothing on a stock Mac claims either.
    private let bound = HotkeyBinding(keyCode: 105, modifiers: [.control, .option, .shift])
    private let away = HotkeyBinding(keyCode: 113, modifiers: [.control, .option, .shift])

    @Test("bind, change away, change back and activate leaves exactly one registration")
    func changeAwayAndBack() throws {
        var current = CarbonHotkeyMonitor()
        try current.start(binding: bound)
        for binding in [away, bound, bound] {
            current.stop()
            current = CarbonHotkeyMonitor()
            try current.start(binding: binding)
        }
        defer { current.stop() }
        try expectHeld(bound)
    }

    @Test("releasing a key deallocates its reconciliation timer")
    func releaseDeallocatesReconciliationTimer() async throws {
        let monitor = CarbonHotkeyMonitor()
        monitor.deliver(.pressed, keyCode: UInt32(bound.keyCode))

        weak var weakTimer: AnyObject?
        weakTimer = monitor.reconciliationTimerForTesting
        #expect(weakTimer != nil)

        monitor.deliver(.released, keyCode: UInt32(bound.keyCode))
        for _ in 0..<100 where weakTimer != nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(weakTimer == nil)
    }

    @Test("a monitor stopped off the main thread does not refuse the next registration")
    func stopOffMainThenRebind() async throws {
        let previous = CarbonHotkeyMonitor()
        let next = CarbonHotkeyMonitor()
        defer { next.stop() }
        try previous.start(binding: bound)

        try stopOffMainThenStart(previous, next)
        await mainQueueDrained()

        try expectHeld(bound)
    }

    /// The AppDelegate stops every claimed monitor and registers a fresh set; a missing unregister would leave the key held by nobody. #142.
    @Test("the stop-all-then-start-all cycle leaves every claimed binding held by exactly one registration")
    func stopAllThenStartAllLeavesEveryClaimedBindingHeld() throws {
        let quiet: Set<HotkeyModifier> = [.control, .option, .shift]
        let first = HotkeyBinding(keyCode: 105, modifiers: quiet)
        let second = HotkeyBinding(keyCode: 107, modifiers: quiet)
        let third = HotkeyBinding(keyCode: 109, modifiers: quiet)

        let current: [CarbonHotkeyMonitor] = [
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
        ]
        defer { for monitor in current { monitor.stop() } }
        try current[0].start(binding: first)
        try current[1].start(binding: second)
        try current[2].start(binding: third)

        for monitor in current { monitor.stop() }

        let next: [CarbonHotkeyMonitor] = [
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
        ]
        defer { for monitor in next { monitor.stop() } }
        try next[0].start(binding: first)
        try next[1].start(binding: second)
        try next[2].start(binding: third)

        try expectHeld(first)
        try expectHeld(second)
        try expectHeld(third)
    }

    /// A settings change reassigns a binding; the cycle must end with the new binding held and the old one free.
    @Test("a binding changed during the stop-all-then-start-all cycle ends with the new binding held")
    func stopAllThenStartAllWithAChangedBinding() throws {
        let quiet: Set<HotkeyModifier> = [.control, .option, .shift]
        let original = HotkeyBinding(keyCode: 105, modifiers: quiet)
        let other = HotkeyBinding(keyCode: 107, modifiers: quiet)
        let changed = HotkeyBinding(keyCode: 113, modifiers: quiet)
        let changedOther = HotkeyBinding(keyCode: 111, modifiers: quiet)

        let current: [CarbonHotkeyMonitor] = [
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
        ]
        defer { for monitor in current { monitor.stop() } }
        try current[0].start(binding: original)
        try current[1].start(binding: other)

        for monitor in current { monitor.stop() }

        let next: [CarbonHotkeyMonitor] = [
            CarbonHotkeyMonitor(),
            CarbonHotkeyMonitor(),
        ]
        defer { for monitor in next { monitor.stop() } }
        try next[0].start(binding: changed)
        try next[1].start(binding: changedOther)

        // The original binding must be free; an intruder takes it without refusal.
        let released = CarbonHotkeyMonitor()
        defer { released.stop() }
        try released.start(binding: original)

        // The new binding must be held.
        try expectHeld(changed)
    }

    /// Stops on another thread while the main thread waits, so a deferred unregister has not run yet.
    private func stopOffMainThenStart(
        _ previous: CarbonHotkeyMonitor, _ next: CarbonHotkeyMonitor
    ) throws {
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            previous.stop()
            stopped.signal()
        }
        stopped.wait()
        try next.start(binding: bound)
    }

    /// Returns once every block queued on the main queue before it has run.
    private func mainQueueDrained() async {
        await withCheckedContinuation { (resumed: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { resumed.resume() }
        }
    }

    /// Carbon refuses a second registration in this process only while the first still holds the key.
    private func expectHeld(_ binding: HotkeyBinding) throws {
        let intruder = CarbonHotkeyMonitor()
        defer { intruder.stop() }
        #expect(throws: HotkeyError.shortcutUnavailable) {
            try intruder.start(binding: binding)
        }
    }
}
