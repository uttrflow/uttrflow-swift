import Foundation
import Testing
import UttrflowContext

@testable import Uttrflow

@MainActor
private final class SelectionChecks {
    var intervals: [TimeInterval] = []
    var callbacks: [@MainActor () -> Void] = []
    var cancelled: [Int] = []

    func schedule(_ interval: TimeInterval, _ check: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    {
        let index = callbacks.count
        intervals.append(interval)
        callbacks.append(check)
        return { [weak self] in self?.cancelled.append(index) }
    }
}

@MainActor
@Suite
struct SuggestionSelectionPollingTests {
    @Test func startReplacesTheTimerWithoutInvalidatingItsReadGeneration() {
        let checks = SelectionChecks()
        let owner = SuggestionSelectionPolling()
        var generations: [Int] = []
        owner.start(every: 0.2, schedule: checks.schedule) { generations.append($0) }
        #expect(owner.isScheduled)
        checks.callbacks[0]()
        owner.start(every: 5, schedule: checks.schedule) { generations.append($0) }
        checks.callbacks[1]()
        #expect(checks.intervals == [0.2, 5])
        #expect(checks.cancelled == [0])
        #expect(generations == [0, 0])
        #expect(owner.generation == 0)
    }

    @Test func cadenceOnlyReplacesAnActiveDifferentInterval() {
        let checks = SelectionChecks()
        let owner = SuggestionSelectionPolling()
        owner.follow(every: 0.2, schedule: checks.schedule) { _ in }
        #expect(checks.intervals.isEmpty)
        owner.start(every: 0.2, schedule: checks.schedule) { _ in }
        owner.follow(every: 0.2, schedule: checks.schedule) { _ in }
        #expect(checks.intervals == [0.2])
        owner.follow(every: 5, schedule: checks.schedule) { _ in }
        #expect(checks.intervals == [0.2, 5])
        #expect(checks.cancelled == [0])
        owner.stop(cancelRead: {})
        owner.follow(every: 5, schedule: checks.schedule) { _ in }
        #expect(checks.intervals == [0.2, 5])
    }

    @Test func stoppingInvalidatesBeforeCancellationAndClearsBeforeCancellingTheRead() {
        let owner = SuggestionSelectionPolling()
        var events: [String] = []
        owner.start(
            every: 0.2,
            schedule: { _, _ in
                {
                    #expect(owner.generation == 1)
                    #expect(owner.isScheduled)
                    #expect(owner.guardrail != nil)
                    #expect(owner.isReadInFlight)
                    events.append("timer")
                }
            }
        ) { _ in }
        owner.guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        owner.isReadInFlight = true
        owner.stop {
            #expect(owner.generation == 1)
            #expect(!owner.isScheduled)
            #expect(owner.guardrail == nil)
            #expect(!owner.isReadInFlight)
            events.append("read")
        }
        owner.stop { events.append("read") }
        #expect(owner.generation == 2)
        #expect(events == ["timer", "read", "read"])
    }

    @Test func staleCallbacksAndReadCompletionsRetainTheirOriginalGeneration() {
        let checks = SelectionChecks()
        let owner = SuggestionSelectionPolling()
        var accepted: [Int] = []
        let check: @MainActor (Int) -> Void = { generation in
            guard generation == owner.generation else { return }
            accepted.append(generation)
        }
        owner.start(every: 0.2, schedule: checks.schedule, check: check)
        let oldGeneration = owner.generation
        owner.isReadInFlight = true
        owner.stop(cancelRead: {})
        owner.start(every: 0.2, schedule: checks.schedule, check: check)
        owner.isReadInFlight = true
        checks.callbacks[0]()
        checks.callbacks[1]()
        if oldGeneration == owner.generation { owner.isReadInFlight = false }
        #expect(accepted == [1])
        #expect(owner.isReadInFlight)
        #expect(checks.cancelled == [0])
    }

    @Test func guardForwardingKeepsTypedThroughAndFocusedIdentity() {
        let owner = SuggestionSelectionPolling()
        owner.guardrail = ArmedSelectionGuard(
            expectedRange: NSRange(location: 12, length: 0),
            identity: FocusedFieldIdentity(processIdentifier: 41, elementHash: 900))
        owner.guardrail?.typedThrough("é🐕", at: 100)
        let same = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 15, length: 0))
        let changed = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 901, range: NSRange(location: 15, length: 0))
        #expect(owner.guardrail?.observe(same, at: 101) == false)
        #expect(owner.guardrail?.observe(changed, at: 101) == true)
    }

    @Test func aWeakCallbackDoesNotRetainItsRecipientOrTheOwner() {
        let checks = SelectionChecks()
        var owner: SuggestionSelectionPolling? = SuggestionSelectionPolling()
        weak let releasedOwner = owner
        var recipient: SelectionChecks? = SelectionChecks()
        weak let releasedRecipient = recipient
        owner?.start(every: 0.2, schedule: checks.schedule) { [weak recipient] _ in
            recipient?.cancelled.append(99)
        }
        recipient = nil
        owner = nil
        #expect(releasedOwner == nil)
        #expect(releasedRecipient == nil)
        checks.callbacks[0]()
        #expect(checks.cancelled.isEmpty)
    }
}
