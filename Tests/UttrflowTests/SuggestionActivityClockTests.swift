import Foundation
import Testing

@testable import Uttrflow

@MainActor
private final class ActivityTickRecipient {
    var ticks = 0
}

@MainActor
@Suite
struct SuggestionActivityClockTests {
    private func timer(for recipient: ActivityTickRecipient) -> Timer {
        Timer(timeInterval: 1, repeats: true) { [weak recipient] _ in
            MainActor.assumeIsolated { recipient?.ticks += 1 }
        }
    }

    @Test func replacementInvalidatesBeforeCreationAndStoresOnlyTheSuccessor() {
        let clock = SuggestionActivityClock()
        let recipient = ActivityTickRecipient()
        let first = timer(for: recipient)
        let second = timer(for: recipient)
        #expect(!clock.isScheduled)
        clock.schedule { first }
        #expect(clock.isScheduled)
        clock.schedule {
            #expect(!first.isValid)
            #expect(clock.isScheduled)
            return second
        }
        #expect(second.isValid)
        second.fire()
        #expect(recipient.ticks == 1)
        clock.suspend()
        #expect(!clock.isScheduled)
        #expect(!second.isValid)
    }

    @Test func aHandleSuspensionPreservesTheRunningPhase() {
        let clock = SuggestionActivityClock()
        let now = ContinuousClock.now
        let handle = Timer(timeInterval: 1, repeats: true) { _ in }
        #expect(clock.noteActivity(at: now))
        clock.schedule { handle }
        clock.suspend()
        #expect(!handle.isValid)
        #expect(!clock.isScheduled)
        #expect(clock.isRunning)
        #expect(!clock.noteActivity(at: now.advanced(by: .seconds(1))))
        #expect(clock.tick(at: now.advanced(by: .seconds(2)), ghostIsVisible: true) == .wake)
    }

    @Test func idleVerdictsLeaveHandleInvalidationAtTheOriginalCallsite() {
        let clock = SuggestionActivityClock()
        let now = ContinuousClock.now
        let handle = Timer(timeInterval: 1, repeats: true) { _ in }
        #expect(!clock.isRunning)
        #expect(clock.selectionInterval == SuggestionTicking.activeSelectionInterval)
        #expect(clock.tick(at: now, ghostIsVisible: false) == .stop)
        #expect(clock.noteActivity(at: now))
        clock.schedule { handle }
        let idle = now.advanced(by: .seconds(SuggestionTicking.window + 1))
        #expect(clock.tick(at: idle, ghostIsVisible: false) == .stop)
        #expect(!clock.isRunning)
        #expect(handle.isValid)
        #expect(clock.isScheduled)
        clock.suspend()
        #expect(!clock.isScheduled)
        #expect(!handle.isValid)
        #expect(clock.noteActivity(at: idle))
        #expect(clock.isRunning)
    }

    @Test func aWatchingGhostSlowsThenNewActivityRestartsTheActivePhase() {
        let clock = SuggestionActivityClock()
        let now = ContinuousClock.now
        #expect(clock.noteActivity(at: now))
        let idle = now.advanced(by: .seconds(SuggestionTicking.window + 1))
        #expect(clock.tick(at: idle, ghostIsVisible: true) == .wakeAndSlow)
        #expect(clock.selectionInterval == SuggestionTicking.ghostInterval)
        #expect(clock.tick(at: idle.advanced(by: .seconds(1)), ghostIsVisible: true) == .wake)
        #expect(clock.noteActivity(at: idle.advanced(by: .seconds(2))))
        #expect(clock.selectionInterval == SuggestionTicking.activeSelectionInterval)
        #expect(clock.tick(at: idle.advanced(by: .seconds(3)), ghostIsVisible: false) == .wake)
    }

    @Test func resetClearsTheHandleAndPhaseAndAllowsFreshActivity() {
        let clock = SuggestionActivityClock()
        let now = ContinuousClock.now
        #expect(clock.noteActivity(at: now))
        let handle = Timer(timeInterval: 1, repeats: true) { _ in }
        clock.schedule { handle }
        #expect(
            clock.tick(at: now.advanced(by: .seconds(SuggestionTicking.window + 1)), ghostIsVisible: true)
                == .wakeAndSlow)
        clock.reset()
        #expect(!handle.isValid)
        #expect(!clock.isScheduled)
        #expect(!clock.isRunning)
        #expect(clock.selectionInterval == SuggestionTicking.activeSelectionInterval)
        #expect(clock.tick(at: now, ghostIsVisible: true) == .stop)
        clock.reset()
        #expect(clock.noteActivity(at: now))
    }

    @Test func anUnscheduledHandleRetainsNeitherItsWeakRecipientNorItsOwner() {
        var clock: SuggestionActivityClock? = SuggestionActivityClock()
        weak let weakClock = clock
        var recipient: ActivityTickRecipient? = ActivityTickRecipient()
        weak let weakRecipient = recipient
        var handle: Timer? = recipient.map { timer(for: $0) }
        weak let weakHandle = handle
        if let handle { clock?.schedule { handle } }
        handle?.fire()
        #expect(recipient?.ticks == 1)
        recipient = nil
        #expect(weakRecipient == nil)
        handle?.fire()
        handle = nil
        #expect(weakHandle != nil)
        clock = nil
        #expect(weakClock == nil)
        #expect(weakHandle == nil)
    }
}
