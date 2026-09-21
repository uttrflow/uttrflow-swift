// Tests for the supply that keeps one prepared thing ready for whoever asks next.

import Foundation
import Synchronization
import Testing

@testable import UttrflowAI

/// What was made, and how often: the whole point is how often something expensive is built.
private final class Made: Sendable {
    private let keys = Mutex<[String]>([])

    func add(_ key: String) { keys.withLock { $0.append(key) } }

    var all: [String] { keys.withLock { $0 } }
}

@Suite("Keeping one ready")
struct WarmSupplyTests {
    /// A supply that records what it was asked to make, rather than making anything expensive.
    private func supply(counting made: Made) -> WarmSupply<String> {
        WarmSupply { key in
            made.add(key)
            return "session for \(key)"
        }
    }

    @Test("hands out the one it was asked to make ahead of time")
    func handsOutWhatItPrepared() async {
        let made = Made()
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "plain") == "session for plain")
        #expect(made.all == ["plain"])
    }

    @Test("hands the same one out once only")
    func handsItOutOnce() async {
        let supply = supply(counting: Made())
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "plain") != nil)
        #expect(await supply.take(for: "plain") == nil)
    }

    /// The piece after the first is what this exists for: it must not have to make its own.
    @Test("has another ready once the one it had is taken and used")
    func replenishesAfterUse() async {
        let made = Made()
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        _ = await supply.take(for: "plain")
        await supply.replenish(for: "plain")

        #expect(await supply.isReady(for: "plain"))
        #expect(await supply.take(for: "plain") == "session for plain")
        #expect(made.all == ["plain", "plain"])
    }

    /// Warming twice for one dictation should not build twice; the second call has nothing to do.
    @Test("makes nothing when one is already waiting for the same request")
    func doesNotRemakeWhatIsAlreadyThere() async {
        let made = Made()
        let supply = supply(counting: made)

        await supply.replenish(for: "plain")
        await supply.replenish(for: "plain")

        #expect(made.all == ["plain"])
    }

    /// A dictation into somewhere else carries different instructions, and the old one is no use to it.
    @Test("refuses the one it holds to a request that carries something else")
    func refusesAMismatch() async {
        let supply = supply(counting: Made())
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "messaging") == nil)
        #expect(await supply.isReady(for: "plain") == false, "the mismatched one is not kept waiting")
    }

    @Test("replaces what it holds when the next request carries something else")
    func replacesOnANewRequest() async {
        let made = Made()
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        await supply.replenish(for: "messaging")

        #expect(await supply.take(for: "messaging") == "session for messaging")
        #expect(made.all == ["plain", "messaging"])
    }

    @Test("keeps one handed to it, for the caller that made its own")
    func keepsWhatItIsGiven() async {
        let supply = supply(counting: Made())

        await supply.keep("made elsewhere", for: "plain")

        #expect(await supply.take(for: "plain") == "made elsewhere")
    }
}

/// A session kept from a dictation minutes ago is cold, so the supply treats age as it does a wrong key.
@Suite("Keeping one ready only while it is warm")
struct WarmSupplyAgeTests {
    /// A clock a test moves by hand.
    private final class Hand: Sendable {
        private let moment = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { moment.withLock { $0 } }
        func pass(_ seconds: Double) { moment.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private func supply(_ hand: Hand, counting made: Made) -> WarmSupply<String> {
        WarmSupply(now: { hand.now }) { key in
            made.add(key)
            return "session for \(key)"
        }
    }

    @Test("a fresh one is kept rather than made again")
    func freshIsKept() async {
        let hand = Hand()
        let made = Made()
        let supply = supply(hand, counting: made)

        await supply.replenish(for: "tidy")
        hand.pass(5)
        await supply.replenish(for: "tidy")

        #expect(made.all == ["tidy"])
        #expect(await supply.isReady(for: "tidy"))
    }

    @Test("one made before the staleness limit is replaced, and never handed out")
    func staleIsReplaced() async {
        let hand = Hand()
        let made = Made()
        let supply = supply(hand, counting: made)

        await supply.replenish(for: "tidy")
        hand.pass(WarmSupply<String>.staleAfterSeconds + 1)

        #expect(!(await supply.isReady(for: "tidy")), "an old session is not ready")
        await supply.replenish(for: "tidy")
        #expect(made.all == ["tidy", "tidy"], "key-down makes a fresh one")
        #expect(await supply.take(for: "tidy") == "session for tidy")
    }

    @Test("a stale one is not handed out to a dictation")
    func staleIsNotHandedOut() async {
        let hand = Hand()
        let supply = supply(hand, counting: Made())

        await supply.replenish(for: "tidy")
        hand.pass(WarmSupply<String>.staleAfterSeconds + 1)

        #expect(await supply.take(for: "tidy") == nil)
    }
}
