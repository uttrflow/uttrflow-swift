import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

/// A score the model is certain about, which is well above the floor.
let liked = Verification.plausibilityFloor + 1

/// A score the model dislikes, which is well below the floor.
let disliked = Verification.plausibilityFloor - 1

private enum SupersessionWriteError: Error {
    case unavailable
}

private actor ThrowingSupersession: SupersessionRecording {
    private(set) var rejections = 0
    private(set) var supersessions = 0
    private(set) var successfulWrites = 0
    private(set) var corpusClears = 0
    private var failuresRemaining: Int
    private let blocksSecondAttempt: Bool
    private var waitingForSecondAttempt: CheckedContinuation<Void, Never>?
    private var releaseSecondAttempt: CheckedContinuation<Void, Never>?

    init(failuresBeforeSuccess: Int = .max, blocksSecondAttempt: Bool = false) {
        failuresRemaining = failuresBeforeSuccess
        self.blocksSecondAttempt = blocksSecondAttempt
    }

    func recordSupersession(of text: String, by replacement: String, in surface: Surface) async throws {
        supersessions += 1
        try await write()
    }

    func recordRejection(of text: String, in surface: Surface) async throws {
        rejections += 1
        try await write()
    }

    func waitForSecondAttempt() async {
        guard rejections + supersessions < 2 else { return }
        await withCheckedContinuation { waitingForSecondAttempt = $0 }
    }

    func releaseSecondAttemptWrite() {
        releaseSecondAttempt?.resume()
        releaseSecondAttempt = nil
    }

    func clearCorpus() {
        corpusClears += 1
    }

    private func write() async throws {
        let attempts = rejections + supersessions
        if attempts == 2 {
            waitingForSecondAttempt?.resume()
            waitingForSecondAttempt = nil
            if blocksSecondAttempt {
                await withCheckedContinuation { releaseSecondAttempt = $0 }
            }
        }
        guard failuresRemaining > 0 else {
            successfulWrites += 1
            return
        }
        failuresRemaining -= 1
        throw SupersessionWriteError.unavailable
    }
}

/// A verifier over a machine that has already answered, since the first ask only starts the read.
func warmed(
    _ machine: [EnvironmentKind: [String]], on text: String, in surface: Surface = terminal,
    scoring: (any CandidateScoring)? = nil, supersession: (any SupersessionRecording)? = nil,
    clock: ManualClock = ManualClock()
) async -> Verifier {
    // Missing kinds mean an explicit empty answer here; unanswered-read tests construct the index directly.
    var answers = machine
    if let token = CompletionToken(text) {
        for kind in Verification.attestation(for: token)?.lookups.flatMap(\.kinds) ?? []
        where answers[kind] == nil {
            answers[kind] = []
        }
    }
    let index = EnvironmentIndex(reader: StubEnvironment(answers))
    if let token = CompletionToken(text), let directory = EnvironmentSource.workingDirectory(of: surface) {
        for kind in Verification.attestation(for: token)?.lookups.flatMap(\.kinds) ?? [] {
            _ = await index.values(of: kind, in: directory, now: instant)
        }
        await index.settle()
    }
    // On a clock only a slow scorer moves, so a prompt one is never over budget however loaded the machine.
    return Verifier(
        index: index, scoring: scoring, supersession: supersession, budgetInMilliseconds: 200,
        clock: clock)
}

/// What the gates decide about one candidate on a machine that has already answered.
func decided(
    _ text: String, typed: String = "", machine: [EnvironmentKind: [String]] = [:],
    scoring: (any CandidateScoring)? = nil, supersession: (any SupersessionRecording)? = nil,
    in surface: Surface = terminal, clock: ManualClock = ManualClock()
) async -> Verdict {
    let verifier = await warmed(
        machine, on: text, in: surface, scoring: scoring, supersession: supersession, clock: clock)
    return await verifier.verdict(
        for: Candidate(text: text, source: .personal), in: surface, typed: typed, now: instant)
}

@Suite("The gates, in order")
struct VerifierTests {
    @Test("A git alias the user defined is attested, however unlikely the model finds it.")
    func aliasesOutrankTheModel() async {
        let verdict = await decided(
            "git cm", typed: "git c", machine: [.gitAlias: ["cm"], .subcommand(of: "git"): ["commit"]],
            scoring: ScriptedScoring(disliked))
        #expect(verdict == .attested)
    }

    @Test("A program on the machine is attested at the start of a line.")
    func programsAreAttested() async {
        #expect(await decided("kubectl", machine: [.executable: ["kubectl"]]) == .attested)
    }

    @Test("A typo is corrected silently to the name the machine knows.")
    func correctsSilently() async {
        let verdict = await decided(
            "git comit", typed: "git com", machine: [.subcommand(of: "git"): ["commit", "checkout"]])
        #expect(verdict == .corrected("git commit"))
    }

    @Test("A corrected candidate is superseded, so it stops accruing weight where it is stored.")
    func supersedesWhatItCorrects() async {
        let store = RecordingSupersession()
        _ = await decided(
            "git comit", typed: "git com", machine: [.subcommand(of: "git"): ["commit"]], supersession: store)
        #expect(await store.recorded == ["git comit → git commit"])
    }

    @Test("A failed rejection write is retried and the refused line stays suppressed for the session.")
    func failedRejectionIsRetriedAndSuppressed() async {
        let store = ThrowingSupersession()
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit"]], on: "git zqxjw", scoring: ScriptedScoring(disliked),
            supersession: store)
        let candidate = Candidate(text: "git zqxjw", source: .personal)

        #expect(await verifier.verified([candidate], in: terminal, typed: "git z", now: instant).isEmpty)
        #expect(await store.rejections == 1)
        #expect(await verifier.verified([candidate], in: terminal, typed: "git z", now: instant).isEmpty)
        #expect(await store.rejections == 2)
    }

    @Test("A failed supersede write is retried and the retired line stays suppressed for the session.")
    func failedSupersessionIsRetriedAndSuppressed() async {
        let store = ThrowingSupersession()
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit"]], on: "git comit", supersession: store)
        let candidate = Candidate(text: "git comit", source: .personal)

        #expect(
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant).map(\.text) == [
                "git commit"
            ])
        #expect(await store.supersessions == 1)
        #expect(
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant).map(\.text)
                .isEmpty)
        #expect(await store.supersessions == 2)
    }

    @Test("A rejection write that fails once is retried successfully.")
    func rejectionRetryRecovers() async {
        let store = ThrowingSupersession(failuresBeforeSuccess: 1)
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit"]], on: "git zqxjw", scoring: ScriptedScoring(disliked),
            supersession: store)
        let candidate = Candidate(text: "git zqxjw", source: .personal)

        #expect(await verifier.verified([candidate], in: terminal, typed: "git z", now: instant).isEmpty)
        #expect(await verifier.verified([candidate], in: terminal, typed: "git z", now: instant).isEmpty)
        #expect(await store.rejections == 2)
        #expect(await store.successfulWrites == 1)
    }

    @Test("A supersede write that fails once is retried successfully.")
    func supersessionRetryRecovers() async {
        let store = ThrowingSupersession(failuresBeforeSuccess: 1)
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit"]], on: "git comit", supersession: store)
        let candidate = Candidate(text: "git comit", source: .personal)

        #expect(
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant).map(\.text) == [
                "git commit"
            ])
        #expect(
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant).map(\.text)
                == ["git commit"])
        #expect(await store.supersessions == 2)
        #expect(await store.successfulWrites == 1)
    }

    @Test("Forgetting waits for an in-flight retry, then clears its pending suppression.")
    func forgetDrainsInFlightRetry() async {
        let store = ThrowingSupersession(failuresBeforeSuccess: 2, blocksSecondAttempt: true)
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit"]], on: "git comit", supersession: store)
        let candidate = Candidate(text: "git comit", source: .personal)
        _ = await verifier.verified([candidate], in: terminal, typed: "git com", now: instant)

        let retry = Task {
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant)
        }
        await store.waitForSecondAttempt()
        let forgetting = Task {
            try? await verifier.forgetEverything(then: { await store.clearCorpus() })
        }
        while !(await verifier.isWaitingToForgetSupersessionWrites) { await Task.yield() }
        #expect(await store.corpusClears == 0)

        await store.releaseSecondAttemptWrite()
        #expect(await retry.value.isEmpty)
        await forgetting.value
        #expect(await store.corpusClears == 1)

        #expect(
            await verifier.verified([candidate], in: terminal, typed: "git com", now: instant).map(\.text) == [
                "git commit"
            ])
        #expect(await store.supersessions == 3)
    }

    @Test("A candidate the machine has never heard of stands, because silence is not a denial.")
    func silenceLeavesACandidateAlone() async {
        #expect(await decided("git comit", typed: "git com") == .plausible)
    }

    @Test("A candidate the model dislikes and the machine cannot place is not offered.")
    func rejectsWhatNothingSupports() async {
        let verdict = await decided(
            "git zqxjw", typed: "git z", machine: [.subcommand(of: "git"): ["commit"]],
            scoring: ScriptedScoring(disliked))
        #expect(verdict == .rejected)
    }

    @Test("A rejected branch is not condemned for good, since it may be fetched tomorrow.")
    func openVocabularyRejectionIsNotRecorded() async {
        let store = RecordingSupersession()
        let verdict = await decided(
            "git checkout zqxjw", typed: "git checkout z", machine: [.branch: ["main"]],
            scoring: ScriptedScoring(disliked), supersession: store)
        #expect(verdict == .rejected)
        #expect(await store.rejected.isEmpty)
    }

    @Test("A rejected subcommand is condemned for good, since its vocabulary is closed.")
    func closedVocabularyRejectionIsRecorded() async {
        let store = RecordingSupersession()
        _ = await decided(
            "git zqxjw", typed: "git z", machine: [.subcommand(of: "git"): ["commit"]],
            scoring: ScriptedScoring(disliked), supersession: store)
        #expect(await store.rejected == ["git zqxjw"])
    }

    @Test(
        "A model objection to a free last word refuses the line this time only.",
        arguments: [
            "ls -la", "echo \"done\"", "echo done",
        ])
    func freeWordRejectionIsNotRecorded(line: String) async {
        let store = RecordingSupersession()
        let verdict = await decided(
            line, typed: String(line.prefix(4)), scoring: ScriptedScoring(disliked), supersession: store)
        #expect(verdict == .rejected)
        #expect(await store.rejected.isEmpty)
    }

    @Test("A subcommand the machine never answered for is refused this time only.")
    func unansweredClosedVocabularyIsNotRecorded() async {
        let store = RecordingSupersession()
        let verifier = Verifier(
            index: EnvironmentIndex(reader: StubEnvironment([:])), scoring: ScriptedScoring(disliked),
            supersession: store, budgetInMilliseconds: 200, clock: ManualClock())
        let verdict = await verifier.verdict(
            for: Candidate(text: "git zqxjw", source: .personal), in: terminal, typed: "git z", now: instant)
        #expect(verdict == .rejected)
        #expect(await store.rejected.isEmpty)
    }

    @Test("A git alias is not judged or cached while the alias listing is unanswered.")
    func unansweredGitAliasIsNotJudgedOrCached() async {
        let reader = StubEnvironment([.subcommand(of: "git"): ["checkout"], .gitAlias: ["co"]])
        let index = EnvironmentIndex(reader: reader)
        let store = RecordingSupersession()
        let verifier = Verifier(
            index: index, scoring: ScriptedScoring(disliked), supersession: store,
            budgetInMilliseconds: 200, clock: ManualClock())
        let candidate = Candidate(text: "git co", source: .personal)

        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git c", now: instant)
        #expect(await store.recorded.isEmpty)
        #expect(await store.rejected.isEmpty)

        await index.settle()
        #expect(
            await verifier.verdict(for: candidate, in: terminal, typed: "git c", now: instant)
                == .attested)
    }

    @Test("A candidate the model likes stands even where the machine cannot place it.")
    func keepsWhatTheModelLikes() async {
        let verdict = await decided(
            "git zqxjw", typed: "git z", machine: [.subcommand(of: "git"): ["commit"]],
            scoring: ScriptedScoring(liked))
        #expect(verdict == .plausible)
    }

    @Test("A model with no opinion leaves the statistical tiers to answer alone.")
    func noOpinionIsNoObjection() async {
        #expect(await decided("git zqxjw", typed: "git z", scoring: ScriptedScoring(nil)) == .plausible)
    }

    @Test("A model still loading is never asked, so the feature is less clever and never slower.")
    func aLoadingModelIsNotAsked() async {
        let scoring = ScriptedScoring(disliked, loaded: false)
        #expect(await decided("git zqxjw", typed: "git z", scoring: scoring) == .plausible)
        #expect(await scoring.asked == 0)
    }

    @Test("A verification past its budget shows nothing the machine had not already attested.")
    func pastTheBudgetOnlyAttestationCounts() async {
        let clock = ManualClock()
        let slow = ScriptedScoring(liked, overrunning: clock)
        #expect(await decided("git zqxjw", typed: "git z", scoring: slow, clock: clock) == .rejected)
    }

    @Test("A scorer that ignores cancellation does not hold the verdict past its deadline.")
    func aNoncooperativeScorerDoesNotHoldUpTheVerdict() async {
        // On a clock the scorer itself pushes past the budget, so the deadline needs no real time to win the race.
        let budgetClock = ManualClock()
        let index = EnvironmentIndex(reader: StubEnvironment([:]))
        let holding = ThreadHold()
        let scoring = NoncooperativeScoring(liked, holding: holding, advancing: budgetClock)
        let verifier = Verifier(index: index, scoring: scoring, budgetInMilliseconds: 200, clock: budgetClock)
        let verdict = await verifier.verdict(
            for: Candidate(text: "git zqxjw", source: .personal), in: terminal, typed: "git z", now: instant)
        let scorerStillHeld = !holding.hasEnded
        holding.release()
        #expect(verdict == .rejected)
        #expect(scorerStillHeld, "the verdict must return while the scorer still holds its thread")
    }

    @Test("A cancelled turn stops `verified` between candidates, not just after the whole loop.")
    func stopsBetweenCandidatesOnCancellation() async {
        let box = TaskBox<[Candidate]>()
        let scoring = CancellingScoring<[Candidate]>(disliked, cancelling: box)
        let verifier = await warmed([:], on: "candidate0", scoring: scoring)
        let candidates = (0..<4).map { Candidate(text: "candidate\($0)", source: .personal) }
        let task = Task {
            await verifier.verified(candidates, in: terminal, typed: "", now: instant)
        }
        box.task = task
        _ = await task.value
        #expect(
            await scoring.asked == 1,
            "the second candidate must never be scored once the first one's scoring cancelled the turn")
    }

    @Test("A candidate the machine attested is answered before the model is asked at all.")
    func attestationRunsBeforeTheModel() async {
        let clock = ManualClock()
        let slow = ScriptedScoring(disliked, overrunning: clock)
        let verdict = await decided(
            "git cm", typed: "git c", machine: [.gitAlias: ["cm"]], scoring: slow, clock: clock)
        #expect(verdict == .attested)
        #expect(await slow.asked == 0)
    }

    @Test("A verdict past its budget is not remembered, so the next keystroke may ask again.")
    func aMissedBudgetIsNotRemembered() async {
        let clock = ManualClock()
        let slow = ScriptedScoring(liked, overrunning: clock)
        let verifier = await warmed([:], on: "git zqxjw", scoring: slow, clock: clock)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: instant)
        #expect(await verifier.rememberedCount == 0)
    }

    @Test("The same candidate in the same context is judged once and remembered after that.")
    func mostKeystrokesSkipTheGates() async {
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        for _ in 0..<5 {
            _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: instant)
        }
        #expect(await scoring.asked == 1)
        #expect(await verifier.rememberedCount == 1)
    }

    @Test("Forgetting every verdict makes the next keystroke ask again.")
    func forgettingSendsItBackThroughTheGates() async {
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: instant)
        await verifier.forgetEverything()
        #expect(await verifier.rememberedCount == 0)
        #expect(await scoring.forgotten == 1)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: instant)
        #expect(await scoring.asked == 2)
    }

    @Test("The same candidate typed into another field is judged again.")
    func anotherFieldIsAnotherQuestion() async {
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/repo")
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: instant)
        _ = await verifier.verdict(for: candidate, in: editor, typed: "git z", now: instant)
        #expect(await scoring.asked == 2)
    }

    @Test("A candidate ending on a space has no word to judge, so nothing judges it.")
    func nothingToJudge() async {
        #expect(await decided("git ", typed: "git ") == .plausible)
    }

    @Test("A field with no working directory has no machine to consult, so the model answers alone.")
    func withoutADirectoryOnlyTheModelSpeaks() async {
        let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        let verdict = await decided(
            "comit", machine: [.subcommand(of: "git"): ["commit"]], in: notes)
        #expect(verdict == .plausible)
    }

    @Test("A field is remembered separately from every other, so one verdict cannot leak into another.")
    func contextNamesTheField() {
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/repo")
        #expect(
            Verifier.context(of: terminal, typed: "git c") != Verifier.context(of: editor, typed: "git c"))
        #expect(
            Verifier.context(of: terminal, typed: "git c") != Verifier.context(of: terminal, typed: "git d"))
    }
}

@Suite("What the gates leave behind")
struct VerifiedCandidateTests {
    @Test("Learned, environment and generated lines reject unresolved destructive syntax alike.")
    func allSourcesRefuseUnresolvedDestructiveSyntax() async {
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let line = "echo $(rm -rf x)"
        let verifier = await warmed([:], on: line, in: editor)
        let remembered = await verifier.verified(
            [
                Candidate(text: line, source: .personal),
                Candidate(text: line, source: .environment),
            ], in: editor, typed: "echo ", now: instant)
        let generated = await verifier.standing([line], after: "echo ", in: editor, now: instant)

        #expect(remembered.isEmpty)
        #expect(generated.isEmpty)
    }

    @Test("What the gates refuse is dropped and what they correct comes back corrected.")
    func keepsWhatItAllows() async {
        let verifier = await warmed(
            [.subcommand(of: "git"): ["commit", "checkout"]], on: "git comit",
            scoring: ScriptedScoring(disliked))
        let offered = await verifier.verified(
            [
                Candidate(text: "git comit", source: .personal),
                Candidate(text: "git checkout", source: .personal),
                Candidate(text: "git zqxjw", source: .personal),
            ], in: terminal, typed: "git c", now: instant)
        #expect(offered.map(\.text) == ["git commit", "git checkout"])
    }

    @Test("A correction pays the distance penalty of the edit it made.")
    func aCorrectionCostsAnEdit() async {
        let verifier = await warmed([.subcommand(of: "git"): ["commit"]], on: "git comit")
        let offered = await verifier.verified(
            [Candidate(text: "git comit", source: .personal)], in: terminal, typed: "git c", now: instant)
        #expect(offered.first?.editDistance == 1)
    }

    @Test("One keystroke's budget is shared across every candidate rather than spent once each.")
    func theBudgetIsSharedAcrossTheSet() async {
        let clock = ManualClock()
        let slow = ScriptedScoring(liked, overrunning: clock)
        let verifier = await warmed([:], on: "git zqxjw", scoring: slow, clock: clock)
        let offered = await verifier.verified(
            [
                Candidate(text: "git zqxjw", source: .personal),
                Candidate(text: "git qqxjw", source: .personal),
                Candidate(text: "git wqxjw", source: .personal),
            ], in: terminal, typed: "git z", now: instant)
        #expect(offered.isEmpty)
        #expect(await slow.asked == 1)
    }

    @Test("A correction onto a candidate already offered is not offered twice.")
    func correctionsDoNotDuplicate() async {
        let verifier = await warmed([.subcommand(of: "git"): ["commit"]], on: "git comit")
        let offered = await verifier.verified(
            [
                Candidate(text: "git comit", source: .personal),
                Candidate(text: "git commit", source: .personal),
            ], in: terminal, typed: "git c", now: instant)
        #expect(offered.map(\.text) == ["git commit"])
    }

    @Test("Candidates that converge on one text keep the nearest source and sum their evidence.")
    func convergedCandidatesMergeEvidence() async {
        let verifier = await warmed([:], on: "git commit")
        let earlier = moment.addingTimeInterval(-60)
        let offered = await verifier.verified(
            [
                Candidate(
                    text: "git commit", source: .environment, editDistance: 0),
                Candidate(
                    text: "git commit", source: .succession,
                    evidence: Entry(
                        text: "git commit", count: 9, accepted: 7, rejected: 1,
                        selfSourced: 2, lastUsed: moment),
                    editDistance: 1),
                Candidate(
                    text: "git commit", source: .personal,
                    evidence: Entry(
                        text: "git commit", count: 3, accepted: 1, rejected: 2,
                        lastUsed: earlier),
                    editDistance: 2),
            ], in: terminal, typed: "git c", now: instant)

        #expect(offered.count == 1)
        #expect(offered.first?.source == .environment)
        #expect(offered.first?.editDistance == 0)
        #expect(
            offered.first?.evidence
                == Entry(
                    text: "git commit", count: 12, accepted: 8, rejected: 3,
                    selfSourced: 2, lastUsed: moment))
    }

    @Test(
        "A learned line and the machine's spelling of it merge in either order, keeping the confirmation in the score."
    )
    func environmentAndPersonalMergeInEitherOrder() async {
        let verifier = await warmed([:], on: "cat README.md")
        let machine = Candidate(text: "cat README.md", source: .environment)
        let learned = Candidate(
            text: "cat readme.md", source: .personal,
            evidence: Entry(text: "cat readme.md", count: 1, lastUsed: moment))
        let environmentAlone = Frecency.score(machine, now: moment)

        for order in [[machine, learned], [learned, machine]] {
            let offered = await verifier.verified(order, in: terminal, typed: "cat r", now: instant)
            #expect(offered.count == 1)
            #expect(offered.first?.text == "cat README.md")
            #expect(offered.first?.isConfirmedByEnvironment == true)
            #expect(offered.first?.evidence?.count == 1)
            #expect(offered.first.map { Frecency.score($0, now: moment) } ?? 0 > environmentAlone)
        }
    }
}

@Suite("A difference only of case is not a typo")
struct VerifierCaseTests {
    @Test("A git subcommand that differs only in case is corrected to git's spelling.")
    func gitSubcommandsAreCaseSensitive() async {
        let verdict = await decided(
            "git Status", typed: "git S", machine: [.subcommand(of: "git"): ["status"]])
        #expect(verdict == .corrected("git status"))
    }

    @Test("A git alias that differs only in case is corrected to its configured spelling.")
    func gitAliasesAreCaseSensitive() async {
        let verdict = await decided(
            "git CM", typed: "git C", machine: [.gitAlias: ["cm"]])
        #expect(verdict == .corrected("git cm"))
    }

    @Test("A branch that differs only in case is corrected to the branch name.")
    func branchesAreCaseSensitive() async {
        let verdict = await decided(
            "git switch Main", typed: "git switch M",
            machine: [.subcommand(of: "git"): ["switch"], .branch: ["main"]])
        #expect(verdict == .corrected("git switch main"))
    }

    @Test("An exact branch spelling is attested even when a case-folded variant also exists.")
    func exactBranchSpellingWinsOverVariants() async {
        let verdict = await decided(
            "git switch Main", typed: "git switch M",
            machine: [.subcommand(of: "git"): ["switch"], .branch: ["main", "Main"]])
        #expect(verdict == .attested)
    }

    @Test("An ambiguous case-only branch mismatch is rejected instead of choosing arbitrarily.")
    func ambiguousBranchCaseMismatchIsRejected() async {
        let verdict = await decided(
            "git switch MAIN", typed: "git switch M",
            machine: [.subcommand(of: "git"): ["switch"], .branch: ["main", "Main"]])
        #expect(verdict == .rejected)
    }

    @Test("A filename that differs from disk only in case is attested, not corrected.")
    func caseOnlyIsAttested() async {
        let verdict = await decided(
            "cat Readme.md", typed: "cat R", machine: [.file: ["README.md"]])
        #expect(verdict == .attested)
    }

    @Test("A filesystem name stays case-insensitive when git also checks for a branch.")
    func filesystemAttestationSurvivesMixedLookup() async {
        let verdict = await decided(
            "git log Readme.md", typed: "git log R",
            machine: [.branch: [], .file: ["README.md"]])
        #expect(verdict == .attested)
    }

    @Test("A case-only difference is never superseded, so the entry is not condemned.")
    func caseOnlyIsNotSuperseded() async {
        let store = RecordingSupersession()
        _ = await decided(
            "cat readme.md", typed: "cat r", machine: [.file: ["README.md"]], supersession: store)
        #expect(await store.recorded.isEmpty)
    }

    @Test("A real typo beside a case difference is still corrected.")
    func aRealTypoIsStillCorrected() async {
        let verdict = await decided(
            "cat readmee.md", typed: "cat r", machine: [.file: ["README.md"]])
        #expect(verdict == .corrected("cat README.md"))
    }
}

/// A verifier over a machine that has already answered about every kind the test gave it.
private func verifier(
    knowing machine: [EnvironmentKind: [String]], in surface: Surface = terminal
) async -> Verifier {
    let index = EnvironmentIndex(reader: StubEnvironment(machine))
    if let directory = EnvironmentSource.workingDirectory(of: surface) {
        for kind in machine.keys { _ = await index.values(of: kind, in: directory, now: instant) }
        await index.settle()
    }
    return Verifier(index: index)
}

/// The model's lines a machine that has already answered lets stand.
private func standing(
    _ completions: [String], after typed: String, machine: [EnvironmentKind: [String]],
    in surface: Surface = terminal
) async -> [String] {
    await verifier(knowing: machine, in: surface).standing(
        completions, after: typed, in: surface, now: instant)
}

/// What the machine says the next word may be, on a machine that has already answered.
private func options(
    for typed: String, machine: [EnvironmentKind: [String]], in surface: Surface = terminal
) async -> ArgumentOptions {
    await verifier(knowing: machine, in: surface).options(for: typed, in: surface, now: instant)
}

@Suite("What the next word may be")
struct ArgumentOptionsTests {
    @Test(
        "A word begun is one of the values that begin as it does, shortest first, and a word not begun is any of them."
    )
    func valuesAreOffered() async {
        let machine: [EnvironmentKind: [String]] = [.directory: ["Sources", "Scripts", "Tests", ".git"]]
        #expect(await options(for: "cd S", machine: machine) == .among(["Scripts", "Sources"]))
        #expect(await options(for: "cd ", machine: machine) == .among(["Tests", "Scripts", "Sources"]))
    }

    @Test("A word of a kind the machine lists that begins as nothing listed does is nothing.")
    func nothingBeginsThatWay() async {
        #expect(await options(for: "cd pro", machine: [.directory: ["Sources"]]) == .none)
        #expect(await options(for: "make ven", machine: [.subcommand(of: "make"): ["verify"]]) == .none)
        #expect(await options(for: "vim .env.v", machine: [.file: [".env", "src"]]) == .none)
    }

    @Test("A command word stays open while executables have answered but aliases have not.")
    func staysOpenWhileAliasesAreUnanswered() async {
        // Only .executable is in the stub's answers, so .alias reads come back nil (unanswered) forever.
        #expect(await options(for: "zz", machine: [.executable: ["git"]]) == .open)
    }

    @Test("An alias genuinely absent, as opposed to unanswered, still lets executables decide the word.")
    func emptyAliasAnswerDiffersFromUnanswered() async {
        #expect(
            await options(for: "gi", machine: [.executable: ["git"], .alias: []]) == .among(["git"]))
    }

    @Test("A path is finished from the directory it points into, as whole words the line can take.")
    func pathsAreFinishedWhereTheyPoint() async {
        let machine: [EnvironmentKind: [String]] = [
            .directories(under: "Sources"): ["Login", "Billing"], .directories(under: "projects"): [],
        ]
        #expect(
            await options(for: "cd Sources/", machine: machine)
                == .among(["Sources/Login", "Sources/Billing"]))
        #expect(await options(for: "cd Sources/L", machine: machine) == .among(["Sources/Login"]))
        #expect(await options(for: "cd projects/", machine: machine) == .none)
        #expect(
            await options(
                for: "cd projects/beacon/", machine: [.directories(under: "projects/beacon"): []])
                == .none)
        #expect(
            await options(for: "ls ~/", machine: [.entries(under: "~"): ["work", ".zshrc"]])
                == .among(["~/work"]))
    }

    @Test(
        "A runner's `run` is offered with each script the project declares, so the choice covers both words.")
    func runIsOfferedWithItsScripts() async {
        let machine: [EnvironmentKind: [String]] = [
            .subcommand(of: "npm"): ["run", "install", "test"], .subcommand(of: "npm run"): ["build", "dev"],
        ]
        #expect(await options(for: "npm r", machine: machine) == .among(["run dev", "run build"]))
        #expect(
            await options(for: "npm ", machine: machine)
                == .among(["test", "install", "run dev", "run build"]))
        let bare: [EnvironmentKind: [String]] = [.subcommand(of: "npm"): ["run", "install"]]
        #expect(await options(for: "npm r", machine: bare) == .among(["run"]))
    }

    @Test("A branch prefix ending in a slash offers the branches under it as well as a path git would take.")
    func branchPrefixesOfferBranches() async {
        let machine: [EnvironmentKind: [String]] = [
            .branch: ["feat/login", "feat/billing", "main"], .entries(under: "feat"): [],
        ]
        #expect(
            await options(for: "git checkout feat/", machine: machine)
                == .among(["feat/login", "feat/billing"]))
        #expect(
            await options(for: "git checkout fix/", machine: [.branch: ["main"], .entries(under: "fix"): []])
                == .none)
    }

    @Test("A lone dot begins a hidden file, but for a directory may be the parent, so it is left open there.")
    func aDotBeginsAHiddenName() async {
        #expect(
            await options(for: "vim .", machine: [.file: [".env", ".gitignore", "src"]])
                == .among([".env", ".gitignore"]))
        #expect(await options(for: "cd .", machine: [.directory: [".git", "src"]]) == .open)
        #expect(await options(for: "cd ~", machine: [.directory: ["src"]]) == .open)
    }

    @Test("A word already whole and known is open, since the line may go on after it.")
    func aWholeKnownWordIsOpen() async {
        #expect(
            await options(for: "make verify", machine: [.subcommand(of: "make"): ["verify", "lint"]]) == .open
        )
    }

    @Test(
        "A word the command reads as text, a machine that has not answered, and a field that is not a directory are all open."
    )
    func openWhereNothingIsListed() async {
        #expect(await options(for: "echo hel", machine: [.file: ["hello.txt"]]) == .open)
        #expect(await options(for: "cd pro", machine: [:]) == .open)
        let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        #expect(await options(for: "cd pro", machine: [.directory: ["Sources"]], in: notes) == .open)
    }

    @Test(
        "No more than the cap reaches the model, and the typed line finished by each value is an alternative."
    )
    func choicesAreCappedAndCompleted() async {
        let many = (0..<60).map { "dir\($0)" }
        guard case .among(let offered) = await options(for: "cd ", machine: [.directory: many]) else {
            Issue.record("a listed directory should offer choices")
            return
        }
        #expect(offered.count == Verification.mostChoices)
        #expect(
            Verification.completed("cd S", with: ["Sources", "Scripts"]) == ["cd Sources", "cd Scripts"])
        #expect(Verification.completed("cd ", with: ["Sources"]) == ["cd Sources"])
    }
}

@Suite("The machine's word on what the model wrote")
struct GeneratedLineTests {
    @Test("A file the model invented in a directory the machine has listed is not drawn.")
    func inventedFilesAreDropped() async {
        let kept = await standing(["vim .env.vim"], after: "vim .env", machine: [.file: [".env", "src"]])
        #expect(kept.isEmpty)
    }

    @Test("A path into a directory that is not there is not drawn, wherever the model read it.")
    func pathsNotFromHereAreDropped() async {
        let kept = await standing(
            ["cd projects/beacon/backend/"], after: "cd projects/beacon/",
            machine: [.directories(under: "projects/beacon"): []])
        #expect(kept.isEmpty)
    }

    @Test("A path to a directory that is there stands, resolved where it points.")
    func pathsFromHereStand() async {
        let kept = await standing(
            ["cd Sources/UttrflowPredict", "cd Sources/Nowhere"], after: "cd Sour",
            machine: [.directories(under: "Sources"): ["UttrflowPredict"]])
        #expect(kept == ["cd Sources/UttrflowPredict"])
    }

    @Test("A branch with a slash stands as a branch, and where it is not one as a path git also takes.")
    func branchesWithSlashesStand() async {
        let machine: [EnvironmentKind: [String]] = [
            .branch: ["feat/login"], .entries(under: "docs"): ["guide.md"],
        ]
        #expect(
            await standing(["git checkout feat/login"], after: "git checkout feat", machine: machine) == [
                "git checkout feat/login"
            ])
        #expect(
            await standing(["git checkout docs/guide.md"], after: "git checkout docs", machine: machine) == [
                "git checkout docs/guide.md"
            ])
        #expect(
            await standing(["git checkout docs/nowhere"], after: "git checkout docs", machine: machine)
                .isEmpty)
    }

    @Test("A make target the model invented is not drawn where the Makefile lists the real ones.")
    func targetsAreLookedUp() async {
        let kept = await standing(
            ["make verify", "make venv"], after: "make v",
            machine: [.subcommand(of: "make"): ["verify", "lint"]])
        #expect(kept == ["make verify"])
    }

    @Test("A program the machine has is drawn and one it has not is dropped, in the model's order.")
    func programsAreLookedUp() async {
        let kept = await standing(
            ["git status", "github"], after: "gi",
            machine: [.executable: ["git"], .subcommand(of: "git"): ["status"]])
        #expect(kept == ["git status"])
    }

    @Test("A git subcommand the model misspelt is dropped where the machine lists them.")
    func gitSubcommandsAreLookedUp() async {
        let kept = await standing(
            ["git checkout main", "git check"], after: "git chec",
            machine: [.subcommand(of: "git"): ["checkout"], .branch: ["main"]])
        #expect(kept == ["git checkout main"])
    }

    @Test("An invented name in the middle of a line drops the whole line, not only its last word.")
    func everyAddedWordIsAsked() async {
        let kept = await standing(
            ["cd projects/beacon/backend/ && npm run dev"], after: "cd projects/beacon/",
            machine: [.directories(under: "projects/beacon"): []])
        #expect(kept.isEmpty)
    }

    @Test("A machine that has not answered vouches for nothing, so the model's line waits for the listing.")
    func silenceHoldsTheLineBack() async {
        #expect(await standing(["vim .env.vim"], after: "vim .env", machine: [:]).isEmpty)
    }

    @Test(
        "A branch the model invented is held back while the branch listing is cold, and a real one stands once it answers."
    )
    func coldBranchListingVouchesForNothing() async {
        let cold = await standing(["git checkout no-such-branch"], after: "git checkout ", machine: [:])
        #expect(cold.isEmpty)
        let warm: [EnvironmentKind: [String]] = [.branch: ["main"]]
        #expect(
            await standing(["git checkout no-such-branch"], after: "git checkout ", machine: warm).isEmpty)
        #expect(
            await standing(["git checkout main"], after: "git checkout ", machine: warm) == [
                "git checkout main"
            ])
    }

    @Test(
        "An unanswered listing does not end the search early, so an answered one that denies the word decides."
    )
    func anUnansweredLookupDoesNotOutvoteAnAnsweredOne() async {
        let machine: [EnvironmentKind: [String]] = [.entries(under: "docs"): ["guide.md"]]
        #expect(
            await standing(["git checkout docs/nowhere"], after: "git checkout d", machine: machine).isEmpty)
        #expect(
            await standing(["git checkout docs/guide.md"], after: "git checkout d", machine: machine) == [
                "git checkout docs/guide.md"
            ])
    }

    /// The listing names `guide.md`, and the candidate is the path that ends in it.
    @Test("A path is attested by the name it ends in, which is what the listing under it holds.")
    func aPathIsAttestedByItsOwnName() async {
        let verdict = await decided(
            "cat docs/guide.md", typed: "cat docs/",
            machine: [.entries(under: "docs"): ["guide.md"]])
        #expect(verdict == .attested)
    }

    /// The correction is on the name, and the path in front of it is put back before it is offered.
    @Test("A mistyped path is corrected at its last name, keeping the directory in front of it.")
    func aPathIsCorrectedAtItsName() async {
        let verdict = await decided(
            "cat docs/gude.md", typed: "cat docs/",
            machine: [.entries(under: "docs"): ["guide.md"]])
        #expect(verdict == .corrected("cat docs/guide.md"))
    }

    @Test("A field that is not a directory is never asked about, so prose is never denied.")
    func proseIsNeverAsked() async {
        let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        let kept = await standing(
            [".vim"], after: "vim .env", machine: [.file: [".env"]], in: notes)
        #expect(kept == [".vim"])
    }
    @Test("A dominant irreversible leader leaves the turn silent, never its rival shown as certain.")
    func dominantIrreversibleLeaderIsNotReplacedByItsRival() async {
        let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        let context = PredictionContext(typed: "git p")
        let candidates = [
            remembered("git push --force", count: 90, irreversible: true),
            remembered("git push", count: 1),
        ]
        let first = PredictionEngine.decision(from: candidates, in: context, now: moment)
        var shown = first.suggestion
        if first.suggestion.accepting != nil {
            let verifier = Verifier(index: EnvironmentIndex(reader: StubEnvironment([:])))
            let kept = await verifier.verified(candidates, in: notes, typed: context.typed, now: instant)
            shown = PredictionEngine.decision(from: kept, in: context, now: moment).suggestion
        }
        #expect(shown == .silent)
        #expect(first.silence == .irreversibleNotCertain)
    }
}
