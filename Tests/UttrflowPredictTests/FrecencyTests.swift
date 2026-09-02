import Foundation
import Testing

@testable import UttrflowPredict

/// A fixed moment, so every decay in this suite is exact rather than nearly right.
let now = Date(timeIntervalSince1970: 1_800_000_000)

/// A moment this many days before ``now``.
func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

/// A candidate the corpus has seen, so each test names only what it is about.
func remembered(
    _ text: String = "git commit -m",
    count: Int = 4,
    accepted: Int = 0,
    rejected: Int = 0,
    selfSourced: Int = 0,
    lastUsed: Date = now,
    editDistance: Int = 0,
    irreversible: Bool = false
) -> Candidate {
    Candidate(
        text: text,
        source: .personal,
        evidence: Entry(
            text: text, count: count, accepted: accepted, rejected: rejected,
            selfSourced: selfSourced, lastUsed: lastUsed),
        editDistance: editDistance,
        isIrreversible: irreversible)
}

@Suite("Scoring by evidence")
struct FrecencyTests {
    @Test("More uses score higher.")
    func moreUsesWin() {
        #expect(
            Frecency.score(remembered(count: 9), now: now) > Frecency.score(remembered(count: 2), now: now))
    }

    @Test("A use loses exactly half its weight over the half-life.")
    func decayHalves() {
        let fresh = Frecency.decay(now, now: now)
        let aged = Frecency.decay(daysAgo(Frecency.halfLifeInDays), now: now)
        #expect(fresh == 1)
        #expect(abs(aged - 0.5) < 1e-9)
    }

    @Test("A reading from the future does not score above one.")
    func futureIsNotRewarded() {
        #expect(Frecency.decay(now.addingTimeInterval(86_400), now: now) == 1)
    }

    @Test("The same evidence scores lower the older it is.")
    func recencyBeats() {
        let old = Frecency.score(remembered(lastUsed: daysAgo(60)), now: now)
        let recent = Frecency.score(remembered(lastUsed: daysAgo(1)), now: now)
        #expect(recent > old)
    }

    @Test("An entry we suggested ourselves counts for a fraction, so acceptance cannot feed itself.")
    func selfSourcedIsDiscounted() {
        let typed = Frecency.effectiveCount(
            Entry(text: "x", count: 4, selfSourced: 0, lastUsed: now))
        let taken = Frecency.effectiveCount(
            Entry(text: "x", count: 4, selfSourced: 4, lastUsed: now))
        #expect(typed == 4)
        #expect(taken == 4 * Frecency.selfSourcedWeight)
    }

    @Test("More self-sourced uses than total uses cannot push the count below zero.")
    func selfSourcedCannotExceedCount() {
        let count = Frecency.effectiveCount(
            Entry(text: "x", count: 2, selfSourced: 9, lastUsed: now))
        #expect(count >= 0)
        #expect(count == 2 * Frecency.selfSourcedWeight)
    }

    @Test("A candidate that has always been taken outscores one that has always been refused.")
    func acceptanceLifts() {
        let taken = Frecency.score(remembered(accepted: 8, rejected: 0), now: now)
        let refused = Frecency.score(remembered(accepted: 0, rejected: 8), now: now)
        #expect(taken > refused)
    }

    @Test("A candidate never offered is neither lifted nor punished.")
    func neverOfferedIsNeutral() {
        #expect(Frecency.acceptance(Entry(text: "x", count: 3, lastUsed: now)) == 1)
    }

    @Test("A fuzzy match is worth less than an exact one on the same evidence.")
    func fuzzyIsWorthLess() {
        let exact = Frecency.score(remembered(editDistance: 0), now: now)
        let oneEdit = Frecency.score(remembered(editDistance: 1), now: now)
        let twoEdits = Frecency.score(remembered(editDistance: 2), now: now)
        #expect(exact > oneEdit)
        #expect(oneEdit > twoEdits)
    }

    @Test("An entry never used scores nothing, so it can never be shown.")
    func noUsesScoresNothing() {
        #expect(Frecency.score(remembered(count: 0), now: now) == 0)
    }

    @Test("The environment scores on its own, having no history to draw on.")
    func environmentStandsAlone() {
        let branch = Candidate(text: "feat/predict", source: .environment)
        #expect(Frecency.score(branch, now: now) == Frecency.environmentWeight)
    }
}
