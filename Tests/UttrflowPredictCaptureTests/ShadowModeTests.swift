import Testing
import UttrflowPredict

@testable import UttrflowPredictCapture

@Suite("Measuring what would have been drawn")
struct ShadowModeTests {
    @Test("Staying quiet is an observation with nothing offered.")
    func silenceOffersNothing() {
        let observation = ShadowObservation(Suggestion.silent)
        #expect(observation.offered == nil)
        #expect(!observation.wasCertain)
    }

    @Test("One candidate clearly ahead is the confident case.")
    func certaintyIsRecorded() {
        let observation = ShadowObservation(Suggestion.certain("git status"))
        #expect(observation.offered == "git status")
        #expect(observation.wasCertain)
    }

    @Test("A list of near-equal candidates is shown, but never confidently.")
    func choiceIsShownWithoutCertainty() {
        let observation = ShadowObservation(Suggestion.choice(leader: "git push", others: ["git pull"]))
        #expect(observation.offered == "git push")
        #expect(!observation.wasCertain)
    }

    @Test("The dot left after escape offers nothing.")
    func minimisedOffersNothing() {
        #expect(ShadowObservation(Suggestion.minimised).offered == nil)
    }

    @Test("A run that offered nothing counts its keystrokes and shows nothing.")
    func quietRun() {
        var run = ShadowRun()
        #expect(run.isEmpty)
        for _ in 0..<5 { run.observe(.silent) }
        #expect(!run.isEmpty)
        let tally = run.resolve(against: "git status")
        #expect(tally == ShadowTally(keystrokes: 5))
        #expect(tally.shownRate == 0)
        #expect(tally.precisionAtOne == 0)
        #expect(tally.confidentlyWrongRate == 0)
    }

    @Test("A suggestion that matched what was entered is counted right.")
    func matchesArePrecise() {
        var run = ShadowRun()
        run.observe(.silent)
        run.observe(.certain("git status"))
        run.observe(.certain("git status"))
        let tally = run.resolve(against: "git status")
        #expect(tally == ShadowTally(keystrokes: 3, shown: 2, matched: 2, confidentlyWrong: 0))
        #expect(abs(tally.shownRate - 2.0 / 3) < 1e-9)
        #expect(tally.precisionAtOne == 1)
    }

    @Test("A confident suggestion that did not match is the failure the phase exists to count.")
    func certainMissesAreConfidentlyWrong() {
        var run = ShadowRun()
        run.observe(.certain("git push"))
        let tally = run.resolve(against: "git pull")
        #expect(tally == ShadowTally(keystrokes: 1, shown: 1, matched: 0, confidentlyWrong: 1))
        #expect(tally.confidentlyWrongRate == 1)
    }

    @Test("A list that did not match is wrong but not confidently, because it never claimed to be sure.")
    func choiceMissesAreNotConfident() {
        var run = ShadowRun()
        run.observe(.choice(leader: "git push", others: ["git pull"]))
        let tally = run.resolve(against: "git rebase")
        #expect(tally == ShadowTally(keystrokes: 1, shown: 1, matched: 0, confidentlyWrong: 0))
        #expect(tally.precisionAtOne == 0)
    }

    @Test("Resolving a run empties it, so the next field starts from nothing.")
    func resolvingEmptiesTheRun() {
        var run = ShadowRun()
        run.observe(.certain("a"))
        _ = run.resolve(against: "a")
        #expect(run.isEmpty)
        #expect(run.resolve(against: "a") == ShadowTally())
    }

    @Test("A field left without finishing anything is thrown away unscored.")
    func discardingScoresNothing() {
        var run = ShadowRun()
        run.observe(.certain("a"))
        run.discard()
        #expect(run.isEmpty)
    }

    @Test("Tallies add up, which is how one field's numbers reach the application's.")
    func talliesAdd() {
        let sum =
            ShadowTally(keystrokes: 3, shown: 2, matched: 1, confidentlyWrong: 1)
            + ShadowTally(keystrokes: 1, shown: 1, matched: 1)
        #expect(sum == ShadowTally(keystrokes: 4, shown: 3, matched: 2, confidentlyWrong: 1))
    }

    @Test("Nothing measured is nothing claimed, rather than a division by zero.")
    func emptyTallyRatesAreZero() {
        let tally = ShadowTally()
        #expect(tally.shownRate == 0)
        #expect(tally.precisionAtOne == 0)
        #expect(tally.confidentlyWrongRate == 0)
    }
}
