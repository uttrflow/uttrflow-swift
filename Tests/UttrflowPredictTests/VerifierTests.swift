import Foundation
import Testing

@testable import UttrflowPredict

/// A model that says what a test tells it to, and counts how often it is asked.
actor ScriptedScoring: CandidateScoring {
    private let score: Double?
    private let loaded: Bool
    private let delay: Duration?
    private(set) var asked = 0

    init(_ score: Double?, loaded: Bool = true, delay: Duration? = nil) {
        self.score = score
        self.loaded = loaded
        self.delay = delay
    }

    var isReady: Bool { loaded }

    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        asked += 1
        if let delay { try? await Task.sleep(for: delay) }
        return score
    }
}

/// A store that only remembers being told a candidate was wrong.
actor RecordingSupersession: SupersessionRecording {
    private(set) var recorded: [String] = []
    private(set) var rejected: [String] = []

    func recordSupersession(of text: String, by replacement: String, in surface: Surface) {
        recorded.append("\(text) → \(replacement)")
    }

    func recordRejection(of text: String, in surface: Surface) {
        rejected.append(text)
    }
}

/// A score the model is certain about, which is well above the floor.
let liked = Verification.plausibilityFloor + 1

/// A score the model dislikes, which is well below the floor.
let disliked = Verification.plausibilityFloor - 1

/// A verifier over a machine that has already answered, since the first ask only starts the read.
func warmed(
    _ machine: [EnvironmentKind: [String]], on text: String, in surface: Surface = terminal,
    scoring: (any CandidateScoring)? = nil, supersession: (any SupersessionRecording)? = nil
) async -> Verifier {
    let index = EnvironmentIndex(reader: StubEnvironment(machine))
    if let token = CompletionToken(text), let directory = EnvironmentSource.workingDirectory(of: surface) {
        for kind in Verification.attestingKinds(for: token) {
            _ = await index.values(of: kind, in: directory, now: moment)
        }
        await index.settle()
    }
    return Verifier(index: index, scoring: scoring, supersession: supersession)
}

/// What the gates decide about one candidate on a machine that has already answered.
func decided(
    _ text: String, typed: String = "", machine: [EnvironmentKind: [String]] = [:],
    scoring: (any CandidateScoring)? = nil, supersession: (any SupersessionRecording)? = nil,
    in surface: Surface = terminal
) async -> Verdict {
    let verifier = await warmed(
        machine, on: text, in: surface, scoring: scoring, supersession: supersession)
    return await verifier.verdict(
        for: Candidate(text: text, source: .personal), in: surface, typed: typed, now: moment)
}

@Suite("The gates, in order")
struct VerifierTests {
    @Test("A git alias the user defined is attested, however unlikely the model finds it.")
    func aliasesOutrankTheModel() async {
        let verdict = await decided(
            "git cm", typed: "git c", machine: [.gitAlias: ["cm"], .gitSubcommand: ["commit"]],
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
            "git comit", typed: "git com", machine: [.gitSubcommand: ["commit", "checkout"]])
        #expect(verdict == .corrected("git commit"))
    }

    @Test("A corrected candidate is superseded, so it stops accruing weight where it is stored.")
    func supersedesWhatItCorrects() async {
        let store = RecordingSupersession()
        _ = await decided(
            "git comit", typed: "git com", machine: [.gitSubcommand: ["commit"]], supersession: store)
        #expect(await store.recorded == ["git comit → git commit"])
    }

    @Test("A candidate the machine has never heard of stands, because silence is not a denial.")
    func silenceLeavesACandidateAlone() async {
        #expect(await decided("git comit", typed: "git com") == .plausible)
    }

    @Test("A candidate the model dislikes and the machine cannot place is not offered.")
    func rejectsWhatNothingSupports() async {
        let verdict = await decided(
            "git zqxjw", typed: "git z", machine: [.gitSubcommand: ["commit"]],
            scoring: ScriptedScoring(disliked))
        #expect(verdict == .rejected)
    }

    @Test("A candidate the model likes stands even where the machine cannot place it.")
    func keepsWhatTheModelLikes() async {
        let verdict = await decided(
            "git zqxjw", typed: "git z", machine: [.gitSubcommand: ["commit"]],
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
        let slow = ScriptedScoring(liked, delay: .seconds(1))
        #expect(await decided("git zqxjw", typed: "git z", scoring: slow) == .rejected)
    }

    @Test("A candidate the machine attested is answered before the model is asked at all.")
    func attestationRunsBeforeTheModel() async {
        let slow = ScriptedScoring(disliked, delay: .seconds(1))
        let verdict = await decided(
            "git cm", typed: "git c", machine: [.gitAlias: ["cm"]], scoring: slow)
        #expect(verdict == .attested)
        #expect(await slow.asked == 0)
    }

    @Test("A verdict past its budget is not remembered, so the next keystroke may ask again.")
    func aMissedBudgetIsNotRemembered() async {
        let slow = ScriptedScoring(liked, delay: .seconds(1))
        let verifier = await warmed([:], on: "git zqxjw", scoring: slow)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: moment)
        #expect(await verifier.rememberedCount == 0)
    }

    @Test("The same candidate in the same context is judged once and remembered after that.")
    func mostKeystrokesSkipTheGates() async {
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        for _ in 0..<5 {
            _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: moment)
        }
        #expect(await scoring.asked == 1)
        #expect(await verifier.rememberedCount == 1)
    }

    @Test("Forgetting every verdict makes the next keystroke ask again.")
    func forgettingSendsItBackThroughTheGates() async {
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: moment)
        await verifier.forgetEverything()
        #expect(await verifier.rememberedCount == 0)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: moment)
        #expect(await scoring.asked == 2)
    }

    @Test("The same candidate typed into another field is judged again.")
    func anotherFieldIsAnotherQuestion() async {
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/repo")
        let scoring = ScriptedScoring(liked)
        let verifier = await warmed([:], on: "git zqxjw", scoring: scoring)
        let candidate = Candidate(text: "git zqxjw", source: .personal)
        _ = await verifier.verdict(for: candidate, in: terminal, typed: "git z", now: moment)
        _ = await verifier.verdict(for: candidate, in: editor, typed: "git z", now: moment)
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
            "comit", machine: [.gitSubcommand: ["commit"]], in: notes)
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
    @Test("What the gates refuse is dropped and what they correct comes back corrected.")
    func keepsWhatItAllows() async {
        let verifier = await warmed(
            [.gitSubcommand: ["commit", "checkout"]], on: "git comit",
            scoring: ScriptedScoring(disliked))
        let offered = await verifier.verified(
            [
                Candidate(text: "git comit", source: .personal),
                Candidate(text: "git checkout", source: .personal),
                Candidate(text: "git zqxjw", source: .personal),
            ], in: terminal, typed: "git c", now: moment)
        #expect(offered.map(\.text) == ["git commit", "git checkout"])
    }

    @Test("A correction pays the distance penalty of the edit it made.")
    func aCorrectionCostsAnEdit() async {
        let verifier = await warmed([.gitSubcommand: ["commit"]], on: "git comit")
        let offered = await verifier.verified(
            [Candidate(text: "git comit", source: .personal)], in: terminal, typed: "git c", now: moment)
        #expect(offered.first?.editDistance == 1)
    }

    @Test("One keystroke's budget is shared across every candidate rather than spent once each.")
    func theBudgetIsSharedAcrossTheSet() async {
        let slow = ScriptedScoring(liked, delay: .seconds(1))
        let verifier = await warmed([:], on: "git zqxjw", scoring: slow)
        let offered = await verifier.verified(
            [
                Candidate(text: "git zqxjw", source: .personal),
                Candidate(text: "git qqxjw", source: .personal),
                Candidate(text: "git wqxjw", source: .personal),
            ], in: terminal, typed: "git z", now: moment)
        #expect(offered.isEmpty)
        #expect(await slow.asked == 1)
    }

    @Test("A correction onto a candidate already offered is not offered twice.")
    func correctionsDoNotDuplicate() async {
        let verifier = await warmed([.gitSubcommand: ["commit"]], on: "git comit")
        let offered = await verifier.verified(
            [
                Candidate(text: "git comit", source: .personal),
                Candidate(text: "git commit", source: .personal),
            ], in: terminal, typed: "git c", now: moment)
        #expect(offered.map(\.text) == ["git commit"])
    }
}
