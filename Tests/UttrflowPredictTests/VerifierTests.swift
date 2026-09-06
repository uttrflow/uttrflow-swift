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
    // A tight budget, so a scorer that sleeps a second is over it without the test waiting one out.
    return Verifier(
        index: index, scoring: scoring, supersession: supersession, budgetInMilliseconds: 200)
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
            ], in: terminal, typed: "git c", now: moment)
        #expect(offered.map(\.text) == ["git commit", "git checkout"])
    }

    @Test("A correction pays the distance penalty of the edit it made.")
    func aCorrectionCostsAnEdit() async {
        let verifier = await warmed([.subcommand(of: "git"): ["commit"]], on: "git comit")
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
        let verifier = await warmed([.subcommand(of: "git"): ["commit"]], on: "git comit")
        let offered = await verifier.verified(
            [
                Candidate(text: "git comit", source: .personal),
                Candidate(text: "git commit", source: .personal),
            ], in: terminal, typed: "git c", now: moment)
        #expect(offered.map(\.text) == ["git commit"])
    }
}

@Suite("A difference only of case is not a typo")
struct VerifierCaseTests {
    @Test("A filename that differs from disk only in case is attested, not corrected.")
    func caseOnlyIsAttested() async {
        let verdict = await decided(
            "cat readme.md", typed: "cat r", machine: [.file: ["README.md"]])
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

/// The model's lines a machine that has already answered lets stand.
private func standing(
    _ completions: [String], after typed: String, machine: [EnvironmentKind: [String]],
    in surface: Surface = terminal
) async -> [String] {
    let index = EnvironmentIndex(reader: StubEnvironment(machine))
    if let directory = EnvironmentSource.workingDirectory(of: surface) {
        for kind in machine.keys { _ = await index.values(of: kind, in: directory, now: moment) }
        await index.settle()
    }
    return await Verifier(index: index).standing(completions, after: typed, in: surface, now: moment)
}

/// What the machine says the next word may be, on a machine that has already answered.
private func options(
    for typed: String, machine: [EnvironmentKind: [String]], in surface: Surface = terminal
) async -> ArgumentOptions {
    let index = EnvironmentIndex(reader: StubEnvironment(machine))
    if let directory = EnvironmentSource.workingDirectory(of: surface) {
        for kind in machine.keys { _ = await index.values(of: kind, in: directory, now: moment) }
        await index.settle()
    }
    return await Verifier(index: index).options(for: typed, in: surface, now: moment)
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
                for: "cd projects/x-growth/", machine: [.directories(under: "projects/x-growth"): []])
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
            ["cd projects/x-growth/backend/"], after: "cd projects/x-growth/",
            machine: [.directories(under: "projects/x-growth"): []])
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
        let kept = await standing(["git status", "github"], after: "gi", machine: [.executable: ["git"]])
        #expect(kept == ["git status"])
    }

    @Test("A git subcommand the model misspelt is dropped where the machine lists them.")
    func gitSubcommandsAreLookedUp() async {
        let kept = await standing(
            ["git checkout main", "git check"], after: "git chec",
            machine: [.subcommand(of: "git"): ["checkout"]])
        #expect(kept == ["git checkout main"])
    }

    @Test("An invented name in the middle of a line drops the whole line, not only its last word.")
    func everyAddedWordIsAsked() async {
        let kept = await standing(
            ["cd projects/x-growth/backend/ && npm run dev"], after: "cd projects/x-growth/",
            machine: [.directories(under: "projects/x-growth"): []])
        #expect(kept.isEmpty)
    }

    @Test("A machine that has not answered denies nothing, so the model's line stands.")
    func silenceLetsTheLineStand() async {
        #expect(await standing(["vim .env.vim"], after: "vim .env", machine: [:]) == ["vim .env.vim"])
    }

    @Test("A field that is not a directory is never asked about, so prose is never denied.")
    func proseIsNeverAsked() async {
        let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        let kept = await standing(
            [".vim"], after: "vim .env", machine: [.file: [".env"]], in: notes)
        #expect(kept == [".vim"])
    }
}
