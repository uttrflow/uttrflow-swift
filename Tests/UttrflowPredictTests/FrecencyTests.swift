import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Scoring by evidence")
struct FrecencyTests {
    @Test("More uses score higher.")
    func moreUsesWin() {
        #expect(
            Frecency.score(remembered(count: 9), now: moment)
                > Frecency.score(remembered(count: 2), now: moment))
    }

    @Test("A use loses exactly half its weight over the half-life.")
    func decayHalves() {
        let fresh = Frecency.decay(moment, now: moment)
        let aged = Frecency.decay(daysAgo(Frecency.halfLifeInDays), now: moment)
        #expect(fresh == 1)
        #expect(abs(aged - 0.5) < 1e-9)
    }

    @Test("A reading from the future does not score above one.")
    func futureIsNotRewarded() {
        #expect(Frecency.decay(moment.addingTimeInterval(86_400), now: moment) == 1)
    }

    @Test("The same evidence scores lower the older it is.")
    func recencyBeats() {
        let old = Frecency.score(remembered(lastUsed: daysAgo(60)), now: moment)
        let recent = Frecency.score(remembered(lastUsed: daysAgo(1)), now: moment)
        #expect(recent > old)
    }

    @Test("An entry we suggested ourselves counts for a fraction, so acceptance cannot feed itself.")
    func selfSourcedIsDiscounted() {
        let typed = Frecency.effectiveCount(
            Entry(text: "x", count: 4, selfSourced: 0, lastUsed: moment))
        let taken = Frecency.effectiveCount(
            Entry(text: "x", count: 4, selfSourced: 4, lastUsed: moment))
        #expect(typed == 4)
        #expect(taken == 4 * Frecency.selfSourcedWeight)
    }

    @Test("More self-sourced uses than total uses cannot push the count below zero.")
    func selfSourcedCannotExceedCount() {
        let count = Frecency.effectiveCount(
            Entry(text: "x", count: 2, selfSourced: 9, lastUsed: moment))
        #expect(count >= 0)
        #expect(count == 2 * Frecency.selfSourcedWeight)
    }

    @Test("A candidate that has always been taken outscores one that has always been refused.")
    func acceptanceLifts() {
        let taken = Frecency.score(remembered(accepted: 8, rejected: 0), now: moment)
        let refused = Frecency.score(remembered(accepted: 0, rejected: 8), now: moment)
        #expect(taken > refused)
    }

    @Test("A candidate never offered is neither lifted nor punished.")
    func neverOfferedIsNeutral() {
        #expect(Frecency.acceptance(Entry(text: "x", count: 3, lastUsed: moment)) == 1)
    }

    @Test(
        "Always taken lifts by the whole lift, always refused lowers by the same amount, and never below the floor."
    )
    func acceptanceSpansItsRange() {
        let taken = Frecency.acceptance(Entry(text: "x", count: 3, accepted: 5, lastUsed: moment))
        let refused = Frecency.acceptance(Entry(text: "x", count: 3, rejected: 5, lastUsed: moment))
        let mixed = Frecency.acceptance(
            Entry(text: "x", count: 3, accepted: 5, rejected: 5, lastUsed: moment))
        #expect(abs(taken - (1 + Frecency.acceptanceLift)) < 1e-9)
        #expect(abs(refused - (1 - Frecency.acceptanceLift)) < 1e-9)
        #expect(mixed == 1)
        #expect(refused >= Frecency.acceptanceFloor)
        #expect(Frecency.acceptanceFloor > 0)
    }

    @Test(
        "A line typed past every time it was offered ranks below one with the same use that was never offered."
    )
    func heavyRejectionRanksBelowFresh() {
        let refused = Frecency.score(remembered(count: 4, rejected: 12), now: moment)
        let fresh = Frecency.score(remembered(count: 4), now: moment)
        #expect(refused < fresh)
        #expect(refused > 0)
    }

    @Test("A fuzzy match is worth less than an exact one on the same evidence.")
    func fuzzyIsWorthLess() {
        let exact = Frecency.score(remembered(editDistance: 0), now: moment)
        let oneEdit = Frecency.score(remembered(editDistance: 1), now: moment)
        let twoEdits = Frecency.score(remembered(editDistance: 2), now: moment)
        #expect(exact > oneEdit)
        #expect(oneEdit > twoEdits)
    }

    @Test("An entry never used scores nothing, so it can never be shown.")
    func noUsesScoresNothing() {
        #expect(Frecency.score(remembered(count: 0), now: moment) == 0)
    }

    @Test("The environment scores on its own, having no history to draw on.")
    func environmentStandsAlone() {
        let branch = Candidate(text: "feat/predict", source: .environment)
        #expect(Frecency.score(branch, now: moment) == Frecency.environmentWeight)
    }
}
