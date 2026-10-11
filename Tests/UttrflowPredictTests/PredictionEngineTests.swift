import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Deciding what to draw")
struct PredictionEngineTests {
    /// What the engine draws for these candidates, at the one instant every suite measures from.
    private func suggestion(
        _ candidates: [Candidate], _ context: PredictionContext = PredictionContext(typed: "git c")
    ) -> Suggestion {
        PredictionEngine.suggestion(from: candidates, in: context, now: moment)
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

    @Test("Case variants do not appear together in a choice.")
    func caseVariantsDoNotShareAChoice() {
        let result = suggestion([
            remembered("Hello", count: 10), remembered("hello", count: 9),
        ])
        #expect(result != .choice(leader: "Hello", others: ["hello"]))
    }

    @Test("Case-only evidence combines before separation, keeping a clear leader certain.")
    func caseOnlyEvidenceCombinesBeforeSeparation() {
        let result = suggestion(
            [
                remembered("Git status", count: 9), remembered("git status", count: 8),
                remembered("git stash", count: 1),
            ], PredictionContext(typed: "git s"))
        #expect(result == .certain("Git status"))
    }

    @Test("An irreversible case twin cannot be offered through its safer spelling.")
    func caseTwinCannotBypassIrreversibleGuard() {
        let result = suggestion([
            remembered("git push --force", count: 9),
            remembered("Git push --force", count: 8, irreversible: true),
            remembered("git push", count: 1),
        ])
        #expect(result == .silent)
    }

    @Test("Nothing to say means nothing is drawn.")
    func noCandidates() {
        #expect(suggestion([]) == .silent)
    }

    @Test("A leader with too little behind it stays quiet, however far ahead it is.")
    func thinEvidenceIsSilent() {
        let faint = remembered("git commit -m", count: 1, lastUsed: daysAgo(400))
        #expect(Frecency.score(faint, now: moment) < PredictionEngine.supportFloor)
        #expect(suggestion([faint]) == .silent)
    }

    @Test("A line entered once is offered from the moment it is learned.")
    func aSingleFreshExactEntryDraws() {
        #expect(suggestion([remembered("git commit -m", count: 1)]) == .certain("git commit -m"))
    }

    @Test("A single near-typed match is offered when it is the only candidate.")
    func aSingleFuzzyMatchDraws() {
        let fuzzy = remembered("git commit -m", count: 1, editDistance: 1)
        #expect(Frecency.score(fuzzy, now: moment) >= PredictionEngine.supportFloor)
        #expect(suggestion([fuzzy]) == .certain("git commit -m"))
    }

    @Test("A two-edit guess on a single use is too uncertain to draw, so the floor is not zero.")
    func aDistantSingleFuzzyMatchStaysQuiet() {
        let distant = remembered("git commit -m", count: 1, editDistance: 2)
        #expect(suggestion([distant]) == .silent)
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

    @Test("An irreversible command clearly ahead is withheld, and its rival is not promoted to certain.")
    func irreversibleLeaderIsSilent() {
        let clear = suggestion([
            remembered("git push --force", count: 90, irreversible: true),
            remembered("git push", count: 1),
        ])
        #expect(clear == .silent)
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

    @Test("A leader in a close race whose only rivals were barred is withheld, never shown as certain.")
    func unseparatedLeaderWithBarredRivalIsSilent() {
        let candidates = [
            remembered("git push", count: 10),
            remembered("git push --force", count: 9, irreversible: true),
        ]
        #expect(Ranking(candidates, now: moment).separation < PredictionEngine.separationThreshold)
        let context = PredictionContext(typed: "git p")
        let decided = PredictionEngine.decision(from: candidates, in: context, now: moment)
        #expect(decided.suggestion == .silent)
        #expect(decided.silence == .irreversibleNotCertain)
    }

    @Test("A leader clearly ahead of a barred rival is still shown alone.")
    func separatedLeaderWithBarredRivalIsCertain() {
        let result = suggestion([
            remembered("git push", count: 90),
            remembered("git push --force", count: 1, irreversible: true),
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

    @Test(
        "Every silence names its reason, and a drawing names none.",
        arguments: [
            ([Candidate](), PredictionContext(typed: "git c"), Quieting.Reason?.some(.nothingOffered)),
            (
                [remembered("git commit -m", count: 1, lastUsed: daysAgo(400))],
                PredictionContext(typed: "git c"), .evidenceTooThin
            ),
            (
                [remembered("git push --force", count: 90, irreversible: true)],
                PredictionContext(typed: "git p"), .irreversibleNotCertain
            ),
            ([remembered(count: 50)], PredictionContext(typed: "git c", isMinimised: true), .minimised),
            (
                [remembered(count: 50)],
                PredictionContext(typed: "hunter2", isSecure: true, isMinimised: true), .secureField
            ),
            ([remembered(count: 50)], PredictionContext(typed: "git c"), nil),
        ])
    func silenceNamesItsReason(
        candidates: [Candidate], context: PredictionContext, expected: Quieting.Reason?
    ) {
        let decided = PredictionEngine.decision(from: candidates, in: context, now: moment)
        #expect(decided.silence == expected)
        #expect(decided.suggestion == suggestion(candidates, context))
        #expect((decided.silence == nil) == (decided.suggestion.accepting != nil))
        let ranked = PredictionEngine.ranked(from: candidates, in: context, now: moment)
        #expect(ranked.suggestion == decided.suggestion && ranked.silence == decided.silence)
        if decided.suggestion.accepting != nil {
            #expect(ranked.ranking == Ranking(candidates, now: moment))
        }
    }

    @Test("What Tab would insert is what is on screen.")
    func acceptingMatchesTheDisplay() {
        #expect(Suggestion.certain("a").accepting == "a")
        #expect(Suggestion.choice(leader: "a", others: ["b"]).accepting == "a")
        #expect(Suggestion.silent.accepting == nil)
        #expect(Suggestion.minimised.accepting == nil)
    }
}
