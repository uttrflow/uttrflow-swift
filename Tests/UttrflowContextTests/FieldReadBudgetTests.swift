// Tests that a field read stops at its budget and that a field that ran over is left alone for a while.

import Testing
import UttrflowTestSupport

@testable import UttrflowContext

private let field = SlowFields.Key(process: 42, element: 7)
private let other = SlowFields.Key(process: 42, element: 8)
private let tick = Duration.nanoseconds(1)

@Suite("One field read's budget")
struct FieldReadBudgetTests {
    @Test("A read is spent once its allowance has passed on the clock, and not a nanosecond before")
    func spentAtTheAllowance() {
        let clock = ManualClock()
        let budget = FieldReadBudget.start(on: clock)
        #expect(!budget.isSpent)
        clock.advance(by: FieldReadBudget.allowance - tick)
        #expect(!budget.isSpent)
        clock.advance(by: tick)
        #expect(budget.isSpent)
    }

    @Test("The allowance is shorter than one message's own timeout, so one stalled message is enough to stop")
    func shorterThanOneTimeout() {
        let timeout = Duration.seconds(Double(FocusedFieldReader.elementTimeoutInSeconds))
        #expect(FieldReadBudget.allowance < timeout)
    }
}

@Suite("Fields left alone after a slow read")
struct SlowFieldsTests {
    @Test("A field's first run over is forgiven, since the first read of a process is a cold start")
    func firstRunOverIsForgiven() {
        let slow = SlowFields(clock: ManualClock())
        slow.ranOver(field)
        #expect(!slow.isResting(field))
    }

    @Test("A field that ran over twice rests for the first rest, and only that field")
    func restsAfterRunningOver() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        #expect(!slow.isResting(field))
        slow.ranOver(field)
        slow.ranOver(field)
        #expect(!slow.isResting(other))
        clock.advance(by: SlowFields.firstRest - tick)
        #expect(slow.isResting(field))
        clock.advance(by: tick)
        #expect(!slow.isResting(field))
    }

    @Test("Each further run over doubles the rest, up to the longest")
    func doublesUpToTheLongest() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        slow.ranOver(field)
        slow.ranOver(field)
        clock.advance(by: SlowFields.firstRest)
        slow.ranOver(field)
        clock.advance(by: SlowFields.firstRest * 2 - tick)
        #expect(slow.isResting(field))
        clock.advance(by: tick)
        #expect(!slow.isResting(field))
        for _ in 0..<20 { slow.ranOver(field) }
        clock.advance(by: SlowFields.longestRest - tick)
        #expect(slow.isResting(field))
        clock.advance(by: tick)
        #expect(!slow.isResting(field))
    }

    @Test("A read that keeps to its budget ends the rest")
    func aFastReadEndsTheRest() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        slow.ranOver(field)
        slow.ranOver(field)
        slow.answered(field)
        #expect(!slow.isResting(field))
        slow.ranOver(field)
        #expect(!slow.isResting(field))
        slow.ranOver(field)
        clock.advance(by: SlowFields.firstRest - tick)
        #expect(slow.isResting(field))
    }

    @Test("Past its capacity the field whose rest ends first is forgotten")
    func forgetsTheOldestPastCapacity() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        for element in 0...UInt(SlowFields.capacity) {
            slow.ranOver(SlowFields.Key(process: 1, element: element))
            slow.ranOver(SlowFields.Key(process: 1, element: element))
            clock.advance(by: tick)
        }
        #expect(!slow.isResting(SlowFields.Key(process: 1, element: 0)))
        #expect(slow.isResting(SlowFields.Key(process: 1, element: 1)))
        #expect(slow.isResting(SlowFields.Key(process: 1, element: UInt(SlowFields.capacity))))
    }

    @Test(
        "A resting field quiets its whole application, so not even its focus is asked for until the rest ends"
    )
    func aRestingFieldQuietsItsApplication() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        slow.ranOver(field)
        #expect(!slow.isQuiet(field.process))
        slow.ranOver(field)
        #expect(!slow.isQuiet(43))
        clock.advance(by: SlowFields.firstRest - tick)
        #expect(slow.isQuiet(field.process))
        clock.advance(by: tick)
        #expect(!slow.isQuiet(field.process))
    }

    @Test("A possible focus move ends the quiet, and finding the same field still resting quiets it again")
    func focusMoveEndsTheQuiet() {
        let clock = ManualClock()
        let slow = SlowFields(clock: clock)
        slow.ranOver(field)
        slow.ranOver(field)
        slow.focusMayHaveMoved()
        #expect(!slow.isQuiet(field.process))
        #expect(!slow.isResting(other))
        #expect(!slow.isQuiet(field.process))
        #expect(slow.isResting(field))
        clock.advance(by: SlowFields.firstRest - tick)
        #expect(slow.isQuiet(field.process))
    }

    @Test("A field of the application that answers in time ends its quiet")
    func anAnswerEndsTheQuiet() {
        let slow = SlowFields(clock: ManualClock())
        slow.ranOver(field)
        slow.ranOver(field)
        slow.answered(other)
        #expect(!slow.isQuiet(field.process))
    }
}
