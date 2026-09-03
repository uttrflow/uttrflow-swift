import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Ranking and what it measures")
struct RankingTests {
    @Test("Candidates come back best first.")
    func ordered() {
        let ranking = Ranking([remembered("a", count: 1), remembered("b", count: 40)], now: now)
        #expect(ranking.candidates.map(\.text) == ["b", "a"])
    }

    @Test("Two candidates with identical evidence are ordered by text, so a run never varies.")
    func tiesAreBrokenStably() {
        let first = Ranking([remembered("b"), remembered("a")], now: now)
        let second = Ranking([remembered("a"), remembered("b")], now: now)
        #expect(first.candidates.map(\.text) == second.candidates.map(\.text))
    }

    @Test("Shares add up to the whole.")
    func sharesSumToOne() {
        let ranking = Ranking([remembered("a", count: 3), remembered("b", count: 7)], now: now)
        #expect(abs(ranking.candidates.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    @Test("A single candidate is completely separated, having nothing to be confused with.")
    func aloneIsSeparated() {
        #expect(Ranking([remembered()], now: now).separation == 1)
    }

    @Test("Two equal candidates are not separated at all, however strong they both are.")
    func equalsAreNotSeparated() {
        let ranking = Ranking([remembered("a", count: 500), remembered("b", count: 500)], now: now)
        #expect(ranking.separation == 0)
        #expect(ranking.support > 0)
    }

    @Test("Separation is the gap, not the size — 99 against 98 is contested.")
    func separationIsTheGap() {
        let contested = Ranking([remembered("a", count: 99), remembered("b", count: 98)], now: now)
        let clear = Ranking([remembered("a", count: 99), remembered("b", count: 1)], now: now)
        #expect(contested.separation < clear.separation)
        #expect(contested.separation < PredictionEngine.separationThreshold)
    }

    @Test("Candidates with no evidence at all are dropped rather than ranked at zero.")
    func unevidencedAreDropped() {
        let ranking = Ranking([remembered("a"), remembered("b", count: 0)], now: now)
        #expect(ranking.candidates.map(\.text) == ["a"])
    }

    @Test("Nothing in, nothing measured.")
    func empty() {
        let ranking = Ranking([], now: now)
        #expect(ranking.isEmpty)
        #expect(ranking.support == 0)
        #expect(ranking.separation == 0)
    }
}

@Suite("Deciding what to draw")
struct PredictionEngineTests {
    private func suggestion(
        _ candidates: [Candidate], _ context: PredictionContext = PredictionContext(typed: "git c")
    ) -> Suggestion {
        PredictionEngine.suggestion(from: candidates, in: context, now: now)
    }

    @Test("A clear leader is shown alone.")
    func certain() {
        let result = suggestion([
            remembered("git commit -m", count: 40), remembered("git checkout", count: 1),
        ])
        #expect(result == .certain("git commit -m"))
    }

    @Test("Two close candidates become a choice, with the leader still in front.")
    func choice() {
        let result = suggestion([
            remembered("git commit -m", count: 10), remembered("git checkout", count: 9),
        ])
        #expect(result == .choice(leader: "git commit -m", others: ["git checkout"]))
    }

    @Test("Nothing to say means nothing is drawn.")
    func noCandidates() {
        #expect(suggestion([]) == .silent)
    }

    @Test("A leader with too little behind it stays quiet, however far ahead it is.")
    func thinEvidenceIsSilent() {
        let faint = remembered("git commit -m", count: 1, lastUsed: daysAgo(400))
        #expect(Frecency.score(faint, now: now) < PredictionEngine.supportFloor)
        #expect(suggestion([faint]) == .silent)
    }

    @Test("A list is capped, because past four options it is a search and not a choice.")
    func listIsCapped() {
        let crowd = (0..<9).map { remembered("candidate \($0)", count: 10) }
        guard case .choice(_, let others) = suggestion(crowd) else {
            Issue.record("expected a choice")
            return
        }
        #expect(others.count == PredictionEngine.maximumChoices - 1)
    }

    @Test("An irreversible command is never offered on thin separation.")
    func irreversibleNeedsCertainty() {
        let contested = suggestion([
            remembered("git push --force", count: 10, irreversible: true),
            remembered("git push", count: 9),
        ])
        #expect(contested == .silent)
    }

    @Test("An irreversible command clearly ahead may still be offered.")
    func irreversibleMayLeadWhenCertain() {
        let clear = suggestion([
            remembered("git push --force", count: 90, irreversible: true),
            remembered("git push", count: 1),
        ])
        #expect(clear == .certain("git push --force"))
    }

    @Test("An irreversible command never appears among the alternatives either.")
    func irreversibleIsNotListed() {
        let result = suggestion([
            remembered("git push", count: 10),
            remembered("git push --force", count: 9, irreversible: true),
            remembered("git pull", count: 9),
        ])
        #expect(result == .choice(leader: "git push", others: ["git pull"]))
    }

    @Test("A single irreversible command alone is never auto-offered, so one Tab cannot run it.")
    func loneIrreversibleIsSilent() {
        let alone = suggestion([remembered("git push --force", count: 90, irreversible: true)])
        #expect(alone == .silent)
    }

    @Test("A single reversible command alone is still offered when it is strong.")
    func loneReversibleIsCertain() {
        #expect(suggestion([remembered("git status", count: 90)]) == .certain("git status"))
    }

    @Test("A leader whose only rivals were barred is shown alone rather than as a choice of one.")
    func lonelyLeaderIsCertain() {
        let result = suggestion([
            remembered("git push", count: 10),
            remembered("git push --force", count: 9, irreversible: true),
        ])
        #expect(result == .certain("git push"))
    }

    @Test("Escape leaves the dot, even with a strong candidate waiting.")
    func minimised() {
        let context = PredictionContext(typed: "git c", isMinimised: true)
        #expect(suggestion([remembered(count: 50)], context) == .minimised)
    }

    @Test("A refusal beats the dot, so a secure field shows nothing at all.")
    func refusalBeatsMinimised() {
        let context = PredictionContext(typed: "hunter2", isSecure: true, isMinimised: true)
        #expect(suggestion([remembered(count: 50)], context) == .silent)
    }

    @Test("What Tab would insert is what is on screen.")
    func acceptingMatchesTheDisplay() {
        #expect(Suggestion.certain("a").accepting == "a")
        #expect(Suggestion.choice(leader: "a", others: ["b"]).accepting == "a")
        #expect(Suggestion.silent.accepting == nil)
        #expect(Suggestion.minimised.accepting == nil)
    }
}

@Suite("Evidence never loses to less of itself")
struct RankingPropertyTests {
    /// A generator with a fixed seed, so a failure can be reproduced exactly.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    @Test("Across a thousand random pairs, more recent and more frequent always ranks higher.")
    func betterEvidenceAlwaysWins() {
        var random = Seeded(state: 0x5EED)
        for _ in 0..<1_000 {
            let count = Int.random(in: 1...50, using: &random)
            let age = Double.random(in: 0...120, using: &random)
            let weaker = remembered("weaker", count: count, lastUsed: daysAgo(age))
            let stronger = remembered(
                "stronger", count: count + Int.random(in: 1...20, using: &random),
                lastUsed: daysAgo(age * Double.random(in: 0...0.9, using: &random)))
            let ranking = Ranking([weaker, stronger], now: now)
            #expect(ranking.candidates.first?.text == "stronger")
        }
    }

    @Test("Adding a candidate never raises the leader's share.")
    func addingCandidatesCannotRaiseTheLeader() {
        var random = Seeded(state: 0xC0FFEE)
        for _ in 0..<500 {
            let leader = remembered("leader", count: Int.random(in: 5...50, using: &random))
            let alone = Ranking([leader], now: now)
            let crowded = Ranking(
                [leader, remembered("other", count: Int.random(in: 1...50, using: &random))],
                now: now)
            #expect(crowded.candidates.first!.share <= alone.candidates.first!.share + 1e-9)
        }
    }
}
