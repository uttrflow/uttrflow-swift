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
}
