import Testing

@testable import UttrflowContext

@Suite("Holding a read to a time")
struct DeadlineTests {
    @Test("An answer that arrives in time is the answer.")
    func promptAnswersAreKept() async {
        let answer = await Deadline.first(withinMilliseconds: 500) { "here" }
        #expect(answer == "here")
    }

    @Test("An answer that does not arrive in time is nothing, and the wait is the allowance, not the work.")
    func lateAnswersAreNothing() async {
        let started = ContinuousClock.now
        let answer = await Deadline.first(withinMilliseconds: 50) {
            try? await Task.sleep(for: .seconds(5))
            return "late"
        }
        #expect(answer == nil)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("Work that answers nothing is nothing, promptly.")
    func nothingIsNothing() async {
        let answer: String? = await Deadline.first(withinMilliseconds: 500) { nil }
        #expect(answer == nil)
    }
}
