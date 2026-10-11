import Testing

@testable import UttrflowContext

@Suite("The budget one surroundings read spends")
struct WalkBudgetTests {
    private let unhurried = ContinuousClock.now + .seconds(60)

    @Test("The element allowance runs out at its maximum")
    func elementsRunOut() {
        var budget = WalkBudget(deadline: unhurried, maximumElements: 2, maximumCharacters: 100)
        budget.spendVisit()
        #expect(!budget.isExhausted && budget.remainingVisits == 1)
        budget.spendVisit()
        #expect(budget.isExhausted && budget.remainingVisits == 0)
    }

    @Test("Characters are charged with one separator between pieces, and cut on the dropped side")
    func charactersAreCharged() {
        var budget = WalkBudget(deadline: unhurried, maximumElements: 10, maximumCharacters: 8)
        #expect(budget.take("abcd", .keepStart) == "abcd")
        #expect(budget.room == 3)
        #expect(budget.take("wxyz", .keepEnd) == "xyz")
        #expect(budget.isExhausted)
    }

    @Test("A passed deadline exhausts the read")
    func theDeadlineExhausts() {
        let budget = WalkBudget(deadline: .now - .milliseconds(1))
        #expect(budget.isExhausted)
    }

    @Test("One Accessibility message is capped by the time left in the whole walk")
    func messageTimeoutShrinksWithTheWalk() {
        let started = ContinuousClock.now
        let budget = WalkBudget(deadline: started + .milliseconds(60))
        #expect(budget.messageTimeoutInSeconds(now: started) == FocusedFieldReader.elementTimeoutInSeconds)
        #expect(budget.messageTimeoutInSeconds(now: started + .milliseconds(40)) == 0.02)
        #expect(budget.messageTimeoutInSeconds(now: started + .milliseconds(60)) == nil)
    }

    @Test("A sub-millisecond remainder is left unspent rather than rounded up")
    func messageTimeoutSkipsSubMillisecondRemainder() {
        let started = ContinuousClock.now
        let budget = WalkBudget(deadline: started + .milliseconds(1))
        #expect(budget.messageTimeoutInSeconds(now: started + .microseconds(500)) == nil)
    }

    @Test("No Accessibility timeout is installed after the surroundings deadline")
    func expiredMessageIsNotPrepared() {
        var applied: [Float] = []
        let wasPrepared = FocusedFieldReader.prepareMessage(
            deadline: .now - .milliseconds(1), maximum: FocusedFieldReader.elementTimeoutInSeconds,
            applyTimeout: {
                applied.append($0)
                return true
            })
        #expect(!wasPrepared)
        #expect(applied.isEmpty)
    }
}
