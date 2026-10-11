// Tests that the machine's alias bodies reach the gates through the same reader as their names.
import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

private struct AliasLauncher: ProgramLaunching {
    func output(of launch: ProgramLaunch) async -> String? { nil }
}

struct AliasVerificationTests {
    @Test func aliasOffersTheSameBranchesAsItsCommand() async {
        let files = FakeDisk(
            home: "/fixture",
            texts: [
                "/fixture/.aliases": "alias gco='git checkout'\n",
                "/repo/.git/HEAD": "ref: refs/heads/main\n",
                "/repo/.git/refs/heads/main": "0123456789abcdef\n",
            ])
        let reader = SystemEnvironmentReader(launcher: AliasLauncher(), programDirectories: [], files: files)
        let index = EnvironmentIndex(reader: reader, aliasReader: reader)
        _ = await index.values(of: .branch, in: "/repo", now: instant)
        _ = await index.values(of: .alias, in: "/repo", now: instant)
        await index.settle()
        let verifier = Verifier(index: index, clock: ManualClock(), files: files)
        _ = await verifier.options(for: "gco ma", in: terminal, now: instant)
        await index.settle()
        #expect(
            await verifier.options(for: "git checkout ma", in: terminal, now: instant) == .among(["main"]))
        #expect(await verifier.options(for: "gco ma", in: terminal, now: instant) == .among(["main"]))
    }
}

private actor ChangingAliases: EnvironmentReading, AliasExpansionReading {
    var words: [String: [String]]?
    private(set) var reads = 0
    init(_ words: [String: [String]]?) { self.words = words }
    func replace(_ words: [String: [String]]?) { self.words = words }
    func aliasExpansions() async -> [String: [String]]? { reads += 1; return words }
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        switch kind {
        case .alias: return ["g", "gco", "gs"]
        case .branch: return ["main"]
        case .subcommand(of: "git"): return ["checkout", "status"]
        case .subcommand(of: "npm run"): return ["build"]
        case .gitAlias: return []
        default: return []
        }
    }
}

private actor WaitingAliasScore: CandidateScoring {
    var isReady: Bool { true }
    private var gate: CheckedContinuation<Double?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        await withCheckedContinuation {
            gate = $0; started?.resume(); started = nil
        }
    }
    func confidence(ofGenerated line: String) async -> Double? { nil }
    func wait() async { if gate == nil { await withCheckedContinuation { started = $0 } } }
    func release() { gate?.resume(returning: liked); gate = nil }
}

extension AliasVerificationTests {
    @Test func allConsumersKeepTheLiteralAliasHead() async {
        let terminal = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/repo")
        let reader = ChangingAliases(["g": ["git"], "gco": ["git", "checkout"], "gs": ["git", "status"]])
        let index = aliasIndex(reader)
        await warmAliases(index, kinds: [.branch, .alias, .subcommand(of: "git"), .gitAlias])
        let disk = FakeDisk(directories: ["/repo"], executables: ["/usr/bin/git"])
        let verifier = Verifier(index: index, clock: ManualClock(), files: disk)
        #expect(await verifier.options(for: "g che", in: terminal, now: instant) == .among(["checkout"]))
        #expect(await verifier.options(for: "gs arbit", in: terminal, now: instant) == .open)
        #expect(
            await EnvironmentSource(index: index).candidates(for: terminal, matching: "gco ma", now: instant)
                .map(\.text) == ["gco main"])
        #expect(
            await verifier.verdict(
                for: Candidate(text: "gco main", source: .personal), in: terminal, typed: "gco ma",
                now: instant) == .attested)
        #expect(
            await verifier.verdict(
                for: Candidate(text: "gco mian", source: .personal), in: terminal, typed: "gco mi",
                now: instant) == .corrected("gco main"))
        #expect(
            await verifier.standing(
                ["gco main", "gco imaginary"], after: "gco ma", in: terminal, now: instant) == ["gco main"])
    }

    @Test func opaqueMetadataDoesNotFallThroughToFileChoices() async {
        let reader = SystemEnvironmentReader(
            launcher: AliasLauncher(), programDirectories: [],
            files: FakeDisk(home: "/fixture", texts: ["/fixture/.aliases": "alias git='$(opaque)'\n"]))
        let index = aliasIndex(reader)
        await warmAliases(index)
        let verifier = Verifier(index: index, clock: ManualClock())
        for typed in ["git checkout .imaginary", "git checkout ./"] {
            #expect(await verifier.options(for: typed, in: terminal, now: instant) == .open)
            #expect(
                await EnvironmentSource(index: index).candidates(
                    for: Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/repo"),
                    matching: typed, now: instant
                ).map(\.text) == [])
        }
    }

    @Test(arguments: ["alias g='opaque'\nalias opaque='$(unsettled)'", "alias g='loop'\nalias loop='g'"])
    func unresolvedCustomChainsCannotConstrainArguments(configuration: String) async {
        let reader = SystemEnvironmentReader(
            launcher: AliasLauncher(), programDirectories: [],
            files: FakeDisk(home: "/fixture", texts: ["/fixture/.aliases": configuration]))
        let index = aliasIndex(reader)
        await warmAliases(index)
        let verifier = Verifier(index: index, clock: ManualClock())
        for typed in ["g i", "g .imaginary", "g ./", "opaque i"] {
            #expect(await verifier.options(for: typed, in: terminal, now: instant) == .open)
        }
    }

    @Test func refreshAndForgetInvalidateOldVerdictsAndInFlightScores() async {
        let reader = ChangingAliases(["gco": ["git", "checkout"]])
        let clock = ManualClock()
        let aliases = AliasExpansionCache(reader: reader, clock: clock)
        let index = aliasIndex(reader, aliases: aliases)
        await warmAliases(index, kinds: [.branch])
        let scoring = WaitingAliasScore()
        let verifier = Verifier(index: index, scoring: scoring, clock: ManualClock())
        let known = Candidate(text: "gco main", source: .personal)
        #expect(await verifier.verdict(for: known, in: terminal, typed: "gco ma", now: instant) == .attested)
        let late = Task {
            await verifier.verdict(
                for: Candidate(text: "gco imaginary", source: .personal), in: terminal, typed: "gco i",
                now: instant)
        }
        await scoring.wait()
        await reader.replace(["gco": ["git", "status"]])
        clock.advance(by: .seconds(60))
        _ = await index.aliasSnapshot()
        await index.settle()
        #expect(await verifier.options(for: "gco ma", in: terminal, now: instant) == .open)
        #expect(await verifier.rememberedCount == 0)
        await scoring.release()
        #expect(await late.value == .rejected)
        #expect(await verifier.rememberedCount == 0)
        await verifier.forgetEverything()
        #expect(await index.aliasSnapshot().words == nil)
        await index.settle()
        #expect(await index.aliasSnapshot().words == ["gco": ["git", "status"]])
    }
    @Test func aChangedAliasWithdrawsAnAlreadyAcceptedBatchMember() async {
        let reader = ChangingAliases(["gco": ["git", "checkout"]])
        let clock = ManualClock()
        let index = aliasIndex(reader, aliases: AliasExpansionCache(reader: reader, clock: clock))
        await warmAliases(index, kinds: [.branch, .alias])
        let scoring = WaitingAliasScore()
        let verifier = Verifier(index: index, scoring: scoring, clock: ManualClock())
        let batch = Task {
            await verifier.verified(
                [
                    Candidate(text: "gco main", source: .personal),
                    Candidate(text: "gco imaginary", source: .personal),
                ],
                in: terminal, typed: "gco ma", now: instant)
        }
        await scoring.wait()
        await reader.replace(["gco": ["git", "status"]])
        clock.advance(by: .seconds(60))
        _ = await index.aliasSnapshot()
        await index.settle()
        #expect(await verifier.options(for: "gco ma", in: terminal, now: instant) == .open)
        await scoring.release()
        #expect(await batch.value == [])
    }

    @Test(arguments: ["g", "sudo", "time"])
    func aliasRefusalsNeverPersistAcrossGrammarChanges(alias: String) async {
        let prefix = alias == "time" ? "sudo time" : alias
        let reader = ChangingAliases([alias: alias == "time" ? ["npm", "run"] : ["git"]])
        let clock = ManualClock()
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        let index = aliasIndex(reader, aliases: cache)
        await warmAliases(index, kinds: [.subcommand(of: "git"), .gitAlias, .subcommand(of: "npm run")])
        let store = RecordingSupersession()
        let verifier = Verifier(
            index: index, scoring: ScriptedScoring(disliked), supersession: store, clock: ManualClock())
        #expect(
            await verifier.verdict(
                for: Candidate(text: "\(prefix) imaginary", source: .personal), in: terminal, typed: "g i",
                now: instant) == .rejected)
        #expect(await store.rejected == [])
        #expect(
            await verifier.verdict(
                for: Candidate(text: "git imaginary", source: .personal), in: terminal, typed: "git i",
                now: instant) == .rejected)
        #expect(await store.rejected == ["git imaginary"])
        await reader.replace([alias: ["echo"]])
        clock.advance(by: .seconds(60))
        _ = await index.aliasSnapshot()
        await index.settle()
        #expect(await verifier.options(for: "\(prefix) i", in: terminal, now: instant) == .open)
        #expect(await store.rejected == ["git imaginary"])
    }

    @Test func missingMetadataCannotMakeARefusalDurable() async {
        let reader = ChangingAliases(nil)
        let index = aliasIndex(reader)
        await warmAliases(index, kinds: [.branch, .subcommand(of: "git"), .gitAlias])
        let store = RecordingSupersession()
        let verifier = Verifier(
            index: index, scoring: ScriptedScoring(disliked), supersession: store, clock: ManualClock())
        #expect(
            await verifier.options(for: "git checkout ma", in: terminal, now: instant) == .among(["main"]))
        #expect(
            await verifier.verdict(
                for: Candidate(text: "git imaginary", source: .personal), in: terminal, typed: "git i",
                now: instant) == .rejected)
        #expect(
            await EnvironmentSource(index: index).candidates(
                for: Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/repo"),
                matching: "git checkout ma", now: instant
            ).map(\.text) == ["git checkout main"])
        #expect(await store.rejected == [])
        #expect(await verifier.rememberedCount == 0)
    }

    @Test func aChangedSnapshotCannotPublishOldCandidatesOrCachedVerdicts() async {
        let reader = ChangingAliases(["gco": ["git", "checkout"]])
        let aliases = SequencedAliases()
        let index = aliasIndex(reader, aliases: aliases)
        _ = await index.values(of: .branch, in: "/repo", now: instant)
        await index.settle()
        let surface = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/repo")
        #expect(
            await EnvironmentSource(index: index).candidates(for: surface, matching: "gco ma", now: instant)
                .map(\.text) == [])
        await aliases.stabilize()
        let verifier = Verifier(index: index, clock: ManualClock())
        let candidate = Candidate(text: "gco main", source: .personal)
        #expect(
            await verifier.verdict(for: candidate, in: surface, typed: "gco ma", now: instant) == .attested)
        #expect(await verifier.rememberedCount == 1)
        await aliases.changeOnRead()
        #expect(
            await verifier.verdict(for: candidate, in: surface, typed: "gco ma", now: instant) == .rejected)
    }

    @Test(arguments: [String?.none, "https://fixture.invalid"])
    func nonFilesystemFieldsNeverReadAliasBodies(scope: String?) async {
        let reader = ChangingAliases(["gco": ["git", "checkout"]])
        let index = aliasIndex(reader)
        let verifier = Verifier(index: index, clock: ManualClock())
        let surface = Surface(
            bundleIdentifier: "com.example.prose", role: "AXTextArea",
            scope: scope)
        #expect(
            await verifier.verdict(
                for: Candidate(text: "ordinary prose", source: .personal), in: surface, typed: "ordinary ",
                now: instant) == .plausible)
        #expect(
            await verifier.standing(["ordinary prose"], after: "ordinary ", in: surface, now: instant) == [
                "ordinary prose"
            ])
        #expect(await reader.reads == 0)
        #expect(await verifier.rememberedCount == 1)
    }

}

private actor SequencedAliases: AliasSnapshotProviding {
    private var revision: UInt64 = 0
    private var changes = true
    func stabilize() { changes = false }
    func changeOnRead() { changes = true }
    func snapshot() -> AliasExpansionSnapshot {
        defer { if changes { revision += 1 } }
        return AliasExpansionSnapshot(words: ["gco": ["git", "checkout"]], revision: revision)
    }
    func settle() {}
    func forgetEverything() {}
}

private func aliasIndex<R: EnvironmentReading & AliasExpansionReading>(
    _ reader: R, aliases: (any AliasSnapshotProviding)? = nil
) -> EnvironmentIndex {
    EnvironmentIndex(
        reader: reader, seconds: { 0 },
        aliases: aliases ?? AliasExpansionCache(reader: reader, clock: ContinuousClock()))
}

private func warmAliases(_ index: EnvironmentIndex, kinds: [EnvironmentKind] = []) async {
    _ = await index.aliasSnapshot()
    for kind in kinds {
        _ = await index.values(of: kind, in: "/repo", now: instant)
    }
    await index.settle()
}
