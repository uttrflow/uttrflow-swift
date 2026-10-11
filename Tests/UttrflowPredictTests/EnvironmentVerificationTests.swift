import Testing

@testable import UttrflowPredict

@Suite("Machine verification operations")
struct EnvironmentVerificationTests {
    private actor Machine: EnvironmentReading, AliasSnapshotProviding {
        let answers: [EnvironmentKind: [String]]
        var revision: UInt64 = 2
        var reads = 0
        var resets = 0
        init(_ answers: [EnvironmentKind: [String]] = [:]) { self.answers = answers }
        func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) -> [String]? {
            answers[kind]
        }
        func snapshot() -> AliasExpansionSnapshot {
            reads += 1
            return AliasExpansionSnapshot(words: ["g": ["git"]], revision: revision)
        }
        func settle() {}
        func forgetEverything() { resets += 1; revision += 1 }
        func advance() { revision += 1 }
    }

    private let surface = Surface(
        bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/repo")
    private let key = VerdictCache.Key(candidate: "git status", context: "fixture")

    @Test("Known facts preserve unions, partial answers and each kind's case rule.")
    func facts() async {
        let machine = Machine([.branch: ["Main"], .file: ["ReadMe"], .gitAlias: []])
        let index = EnvironmentIndex(reader: machine, seconds: { 0 }, aliases: machine)
        let owner = EnvironmentVerification(index: index, metadata: .disabled)
        let now = ContinuousClock.now
        _ = await owner.known(
            of: [.branch, .file, .gitAlias, .subcommand(of: "npm"), .alias], in: surface, now: now)
        await index.settle()
        let union = await owner.knownAndComplete(of: [.branch, .file], in: surface, now: now)
        #expect(union?.known == ["Main", "ReadMe"] && union?.complete == true)
        let partial = await owner.knownAndComplete(
            of: [.gitAlias, .subcommand(of: "npm")], in: surface, now: now)
        #expect(partial?.known == [] && partial?.complete == false)
        #expect(await owner.known(of: [.alias], in: surface, now: now) == nil)
        #expect(!(await owner.attests(Verification.Lookup("main", [.branch, .file]), in: surface, now: now)))
        #expect(await owner.attests(Verification.Lookup("readme", [.branch, .file]), in: surface, now: now))
        for (kind, sensitive): (EnvironmentKind, Bool) in [
            (.branch, true), (.gitAlias, true), (.subcommand(of: "git"), true),
            (.subcommand(of: "npm"), false), (.file, false), (.directory, false), (.executable, false),
            (.alias, false),
        ] {
            #expect(owner.requiresCaseSensitiveMatch(kind) == sensitive)
        }
    }

    @Test("Disabled metadata and nonfilesystem fields never read or reset alias snapshots.")
    func metadataEligibility() async {
        let machine = Machine()
        let index = EnvironmentIndex(reader: machine, seconds: { 0 }, aliases: machine)
        let disabled = EnvironmentVerification(index: index, metadata: .disabled)
        let snapshot = await disabled.aliases(in: surface)
        #expect(snapshot.words == [:] && snapshot.revision == 0)
        let operation = VerificationOperation(surface: surface, generation: 0, aliases: snapshot)
        #expect(await disabled.currentRevision(for: operation) == nil)
        await disabled.forgetAliases()
        let enabled = EnvironmentVerification(index: index, metadata: .enabled)
        for scope in [String?.none, "example.com"] {
            let prose = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea", scope: scope)
            let empty = await enabled.aliases(in: prose)
            #expect(empty.words == [:] && empty.revision == 0)
            #expect(
                await enabled.currentRevision(
                    for: VerificationOperation(surface: prose, generation: 0, aliases: empty)) == nil)
            #expect(await enabled.known(of: [.file], in: prose, now: .now) == nil)
        }
        #expect(await machine.reads == 0)
        #expect(await machine.resets == 0)
    }

    @Test("Publication compares the probe with live session state before remembering exact outcomes.")
    func publication() async {
        let machine = Machine()
        let index = EnvironmentIndex(reader: machine, seconds: { 0 }, aliases: machine)
        let owner = EnvironmentVerification(index: index, metadata: .enabled)
        var session = VerificationSession()
        let snapshot = await owner.aliases(in: surface)
        let operation = session.begin(in: surface, aliases: snapshot, generation: session.generation)
        let revision = await owner.currentRevision(for: operation)
        #expect(snapshot.words == ["g": ["git"]] && revision == 2)
        #expect(
            session.publish(.corrected("git status"), for: key, in: operation, revision: revision)
                == .corrected("git status"))
        #expect(session.verdict(for: key) == .corrected("git status"))
        await machine.advance()
        let changedRevision = await owner.currentRevision(for: operation)
        #expect(changedRevision == 3)
        #expect(session.publish(.attested, for: key, in: operation, revision: changedRevision) == nil)
        #expect(session.verdict(for: key) == .corrected("git status") && session.count == 1)
        let newer = await owner.aliases(in: surface)
        let current = session.begin(in: surface, aliases: newer, generation: session.generation)
        #expect(session.publish(.attested, for: key, in: operation, revision: revision) == nil)
        #expect(session.count == 0 && session.isCurrent(current))
        #expect(session.held(["fixture"], in: operation, revision: revision) == nil)
        let currentRevision = await owner.currentRevision(for: current)
        session.forgetEverything()
        #expect(session.publish(.plausible, for: key, in: current, revision: currentRevision) == nil)
        #expect(session.count == 0)
        let late = session.begin(in: surface, aliases: newer, generation: current.generation)
        #expect(!session.isCurrent(late))
        await owner.forgetAliases()
        #expect(await machine.resets == 1)
        let reset = await owner.aliases(in: surface)
        #expect(reset.revision == 4)
    }
}
