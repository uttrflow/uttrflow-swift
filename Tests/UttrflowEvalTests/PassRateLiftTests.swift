import Testing
@testable import UttrflowEval

struct PassRateLiftTests {
    @Test("a candidate that passes every case the base failed lifts by that share")
    func liftIsTheDifference() throws {
        let lift = PassRateLift(
            base: [true, false, false, true], candidate: [true, true, true, true])
        #expect(lift.cases == 4)
        #expect(lift.basePassRate == 0.5)
        #expect(lift.candidatePassRate == 1)
        #expect(lift.lift == 0.5)
        let interval = try #require(lift.interval)
        #expect(interval.lowerBound >= 0)
        #expect(interval.upperBound <= 1)
        #expect(interval.contains(0.5))
    }

    @Test("identical results lift by zero with a zero-width interval")
    func identicalIsZero() {
        let lift = PassRateLift(base: [true, false, true], candidate: [true, false, true])
        #expect(lift.lift == 0)
        #expect(lift.interval == 0...0)
    }

    @Test("fewer than two pairs give no interval, and nothing paired gives zero rates")
    func tooFewPairs() {
        #expect(PassRateLift(base: [true], candidate: [false]).interval == nil)
        let empty = PassRateLift(base: [], candidate: [true])
        #expect(empty.cases == 0)
        #expect(empty.basePassRate == 0)
        #expect(empty.interval == nil)
    }
}
