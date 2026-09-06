import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Ranking and what it measures")
struct RankingTests {
    @Test("Candidates come back best first.")
    func ordered() {
        let ranking = Ranking([remembered("a", count: 1), remembered("b", count: 40)], now: moment)
        #expect(ranking.candidates.map(\.text) == ["b", "a"])
    }

    @Test("Two candidates with identical evidence are ordered by text, so a run never varies.")
    func tiesAreBrokenStably() {
        let first = Ranking([remembered("b"), remembered("a")], now: moment)
        let second = Ranking([remembered("a"), remembered("b")], now: moment)
        #expect(first.candidates.map(\.text) == second.candidates.map(\.text))
    }

    @Test("Shares add up to the whole.")
    func sharesSumToOne() {
        let ranking = Ranking([remembered("a", count: 3), remembered("b", count: 7)], now: moment)
        #expect(abs(ranking.candidates.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    @Test("A single candidate is completely separated, having nothing to be confused with.")
    func aloneIsSeparated() {
        #expect(Ranking([remembered()], now: moment).separation == 1)
    }

    @Test("Two equal candidates are not separated at all, however strong they both are.")
    func equalsAreNotSeparated() {
        let ranking = Ranking([remembered("a", count: 500), remembered("b", count: 500)], now: moment)
        #expect(ranking.separation == 0)
        #expect(ranking.support > 0)
    }

    @Test("Separation is the gap, not the size — 99 against 98 is contested.")
    func separationIsTheGap() {
        let contested = Ranking([remembered("a", count: 99), remembered("b", count: 98)], now: moment)
        let clear = Ranking([remembered("a", count: 99), remembered("b", count: 1)], now: moment)
        #expect(contested.separation < clear.separation)
        #expect(contested.separation < PredictionEngine.separationThreshold)
    }

    @Test("Candidates with no evidence at all are dropped rather than ranked at zero.")
    func unevidencedAreDropped() {
        let ranking = Ranking([remembered("a"), remembered("b", count: 0)], now: moment)
        #expect(ranking.candidates.map(\.text) == ["a"])
    }

    @Test("Nothing in, nothing measured.")
    func empty() {
        let ranking = Ranking([], now: moment)
        #expect(ranking.isEmpty)
        #expect(ranking.support == 0)
        #expect(ranking.separation == 0)
    }
}

@Suite("Evidence never loses to less of itself")
struct RankingPropertyTests {
    @Test("Across a thousand random pairs, more recent and more frequent always ranks higher.")
    func betterEvidenceAlwaysWins() {
        var random = Seeded(seed: 0x5EED)
        for _ in 0..<1_000 {
            let count = Int.random(in: 1...50, using: &random)
            let age = Double.random(in: 0...120, using: &random)
            let weaker = remembered("weaker", count: count, lastUsed: daysAgo(age))
            let stronger = remembered(
                "stronger", count: count + Int.random(in: 1...20, using: &random),
                lastUsed: daysAgo(age * Double.random(in: 0...0.9, using: &random)))
            let ranking = Ranking([weaker, stronger], now: moment)
            #expect(ranking.candidates.first?.text == "stronger")
        }
    }

    @Test("Adding a candidate never raises the leader's share.")
    func addingCandidatesCannotRaiseTheLeader() throws {
        var random = Seeded(seed: 0xC0FFEE)
        for _ in 0..<500 {
            let leader = remembered("leader", count: Int.random(in: 5...50, using: &random))
            let alone = try #require(Ranking([leader], now: moment).candidates.first)
            let crowded = try #require(
                Ranking(
                    [leader, remembered("other", count: Int.random(in: 1...50, using: &random))],
                    now: moment
                ).candidates.first)
            #expect(crowded.share <= alone.share + 1e-9)
        }
    }
}
