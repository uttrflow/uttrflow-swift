// Tests the burst probe's rate-limit figures.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Tallying a burst probe of the clean-up model")
struct ModelBurstTallyTests {
    private static func request(
        _ burst: Int, _ piece: Int, _ failure: ModelFailureClass?
    ) -> ModelBurstTally.Request {
        ModelBurstTally.Request(burst: burst, piece: piece, duration: .milliseconds(400), failure: failure)
    }

    @Test("nothing sent gives no rate, not a rate of zero")
    func emptyHasNoRate() {
        let tally = ModelBurstTally()
        #expect(tally.rateLimitedPerThousand == nil)
        #expect(tally.firstThrottledPiece == nil)
        #expect(tally.failuresByClass.isEmpty)
    }

    @Test("throttled requests are counted per thousand sent, from the lowest throttled piece")
    func countsThrottling() {
        var tally = ModelBurstTally()
        tally.record(Self.request(1, 1, nil))
        tally.record(Self.request(1, 2, .rateLimited))
        tally.record(Self.request(1, 3, .timedOut))
        tally.record(Self.request(2, 4, .rateLimited))
        #expect(tally.rateLimited == 2)
        #expect(tally.rateLimitedPerThousand == 500)
        #expect(tally.firstThrottledPiece == 2)
        #expect(tally.failuresByClass == [.rateLimited: 2, .timedOut: 1])
    }

    @Test("a probe with no throttling reports zero per thousand")
    func cleanRunIsZero() {
        var tally = ModelBurstTally()
        tally.record(Self.request(1, 1, nil))
        #expect(tally.rateLimitedPerThousand == 0)
        #expect(tally.firstThrottledPiece == nil)
    }
}
