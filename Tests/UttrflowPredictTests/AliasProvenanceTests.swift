// Exercises bounded alias provenance without reading or running a person's shell.
import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

private struct ProvenanceLauncher: ProgramLaunching {
    func output(of launch: ProgramLaunch) async -> String? { nil }
}

private actor ProvenanceReader: AliasExpansionReading, EnvironmentReading {
    private var answer: AliasExpansionSnapshot
    var reads = 0
    init(_ answer: AliasExpansionSnapshot) { self.answer = answer }
    func aliasExpansions() async -> [String: [String]]? { answer.words }
    func aliasMetadata() async -> AliasExpansionSnapshot? {
        reads += 1
        return answer
    }
    func replace(_ answer: AliasExpansionSnapshot) { self.answer = answer }
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        nil
    }
}

struct AliasProvenanceTests {
    @Test func defaultIndexDoesNotOptIntoAliasReads() async {
        let reader = ProvenanceReader(AliasExpansionSnapshot(words: ["g": ["git"]], revision: 0))
        let index = EnvironmentIndex(reader: reader)
        #expect(await index.aliasSnapshot().words == [:])
        #expect(await reader.reads == 0)
    }

    @Test func indexOwnsAndForgetsOneMetadataCache() async {
        let reader = ProvenanceReader(AliasExpansionSnapshot(words: ["g": ["git"]], revision: 0))
        let cache = AliasExpansionCache(reader: reader, clock: ManualClock())
        let index = EnvironmentIndex(reader: reader, seconds: { 0 }, aliases: cache)
        #expect(await index.aliasSnapshot().words == nil)
        await index.settle()
        let first = await index.aliasSnapshot()
        #expect(first.words == ["g": ["git"]])
        await index.forgetAliases()
        #expect(await index.aliasSnapshot().words == nil)
        await index.settle()
        let renewed = await index.aliasSnapshot()
        #expect(renewed.words == first.words && renewed.revision > first.revision)
    }

    private func read(_ text: String) async -> AliasExpansionSnapshot {
        let reader = SystemEnvironmentReader(
            launcher: ProvenanceLauncher(), programDirectories: [],
            files: FakeDisk(home: "/fixture", texts: ["/fixture/.aliases": text]))
        return await reader.aliasMetadata() ?? AliasExpansionSnapshot(words: nil, revision: 0)
    }

    private func shape(_ text: String, _ metadata: AliasExpansionSnapshot) -> LineShape? {
        CompletionToken(text).map { LineShape.of($0, metadata: metadata) }
    }

    @Test func unrelatedOpaqueAliasPreservesKnownSlots() async {
        let metadata = await read("alias opaque='echo fixture | cat'\nalias gco='git checkout'")
        #expect(metadata.blockedCommands.isEmpty)
        #expect(shape("git checkout ma", metadata)?.kind == .branch)
        #expect(shape("npm run bu", metadata)?.kind == .subcommand(of: "npm run"))
        #expect(shape("cd no", metadata)?.kind == .directory)
        #expect(shape("gco ma", metadata)?.kind == .branch)
        #expect(shape("git commit -m .note", metadata)?.isUncertain == false)
    }

    @Test(arguments: ["git", "npm", "cd", "sudo"])
    func opaqueKnownShadowAndDependentChainAreUncertain(command: String) async {
        let metadata = await read("alias \(command)='echo fixture | cat'\nalias chain='\(command)'")
        #expect(metadata.blockedCommands == CommandGrammar.shadowed([command]))
        #expect(shape("\(command) .note", metadata)?.isUncertain == true)
        #expect(shape("chain notes/", metadata)?.isUncertain == true)
        #expect(shape("echo .note", metadata)?.isUncertain == false)
    }

    @Test func opaqueCustomDependencyAndCycleStayUncertain() async {
        let metadata = await read(
            "alias opaque='echo fixture | cat'\nalias chain='opaque'\nalias a='b'\nalias b='a'\nalias loop='loop --flag'"
        )
        #expect(metadata.uncertainAliases.count == 4)
        #expect(shape("chain .note", metadata)?.isUncertain == true)
        #expect(shape("a notes/", metadata)?.isUncertain == true)
        #expect(shape("loop .note", metadata)?.isUncertain == true)
        #expect(shape("echo notes/", metadata)?.isUncertain == false)
    }

    @Test(arguments: ["sudo opaque", "env MODE=fixture opaque"])
    func wrappersCannotHideOpaqueDependencies(body: String) async {
        let metadata = await read("alias opaque='echo fixture | cat'\nalias chain='\(body)'")
        #expect(shape("chain .note", metadata)?.isUncertain == true)
        #expect(shape("chain notes/", metadata)?.isUncertain == true)
    }

    @Test func supportedWrappersAndSelfAliasesKeepTheirGrammar() async {
        let metadata = await read(
            "alias time='git checkout'\nalias gco='sudo git checkout'\n"
                + "alias git='git --no-pager'\nalias sudo='sudo -n'")
        for line in ["time ma", "gco ma", "git checkout ma", "sudo git checkout ma"] {
            #expect(shape(line, metadata)?.kind == .branch)
            #expect(shape(line, metadata)?.isUncertain == false)
        }
        let noAnswer = AliasExpansionSnapshot(words: nil, revision: 0)
        #expect(shape("gi", noAnswer)?.kind == .program)
        #expect(shape("git .note", noAnswer)?.isUncertain == true)
    }

    @Test(arguments: [false, true])
    func omittedBodiesKeepFixedAndDependentUncertainty(large: Bool) async {
        let declarations =
            large
            ? "alias git='\(String(repeating: "x", count: 65_536))'"
            : (0..<200).map { "alias a\($0)='echo'" }.joined(separator: "\n") + "\nalias git='echo'"
        let metadata = await read(declarations + "\nalias Achain='git'")
        #expect(metadata.words?["git"] == nil)
        #expect(metadata.blockedCommands == CommandGrammar.shadowed(["git"]))
        #expect(shape("git checkout .note", metadata)?.isUncertain == true)
        #expect(shape("Achain notes/", metadata)?.isUncertain == true)
        #expect((metadata.words?.count ?? 0) <= 200)
    }

    @Test func dependencyFollowsExpandedWrappersRatherThanArgumentNames() async {
        let metadata = await read("alias time='npm run'\nalias fixture='git checkout'")
        #expect(shape("sudo time bu", metadata)?.isAliasDependent == true)
        #expect(shape("sudo npm run fixture", metadata)?.isAliasDependent == false)
        #expect(shape("echo fixture", metadata)?.isAliasDependent == false)
        let legacy = CompletionToken("time bu").map { LineShape.of($0, aliases: metadata.words ?? [:]) }
        #expect(legacy?.isAliasDependent == false)
    }

    @Test func admissionPreservesReindexedFlagsAndIncompleteAnswers() async {
        let reader = ProvenanceReader(
            AliasExpansionSnapshot(
                words: [
                    "a": [String(repeating: "x", count: 65_536)], "b": ["git"],
                    "git": [String(repeating: "x", count: 65_536)],
                ], revision: 0,
                uncertainAliases: [1]))
        let clock = ManualClock()
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        let admitted = await cache.snapshot()
        #expect(admitted.words == ["b": ["git"]])
        #expect(admitted.uncertainAliases == [0])
        #expect(admitted.blockedCommands == CommandGrammar.shadowed(["git"]))
        await reader.replace(AliasExpansionSnapshot(words: nil, revision: 0))
        clock.advance(by: .seconds(60))
        _ = await cache.snapshot()
        await cache.settle()
        #expect(await cache.snapshot().revision == admitted.revision)
        clock.advance(by: .seconds(2))
        #expect(await cache.snapshot().words == nil)
    }

    @Test func flagsRefreshAndRejectInvalidIndices() async {
        let clock = ManualClock()
        let blocked = CommandGrammar.shadowed(["git"])
        let reader = ProvenanceReader(
            AliasExpansionSnapshot(
                words: ["g": ["git"]], revision: 0,
                blockedCommands: blocked.union([-1, Int.max]), uncertainAliases: [-1, 0, Int.max]))
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        let first = await cache.snapshot()
        #expect(first.blockedCommands == blocked)
        #expect(first.uncertainAliases == [0])
        await reader.replace(AliasExpansionSnapshot(words: ["g": ["git"]], revision: 0))
        clock.advance(by: .seconds(60))
        _ = await cache.snapshot()
        await cache.settle()
        let changed = await cache.snapshot()
        #expect(changed.revision > first.revision)
        #expect(changed.blockedCommands.isEmpty && changed.uncertainAliases.isEmpty)
    }

    @Test func flagsExpireAndForgetTogether() async {
        let clock = ManualClock()
        let reader = ProvenanceReader(
            AliasExpansionSnapshot(
                words: ["g": ["git"]], revision: 0,
                blockedCommands: CommandGrammar.shadowed(["git"]), uncertainAliases: [0]))
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        await clock.waitUntilSomethingIsWaiting()
        let expiry = await cache.pendingExpiry
        clock.advance(by: .seconds(62))
        await expiry?.value
        let expired = await cache.snapshot()
        #expect(expired.words == nil)
        #expect(expired.blockedCommands.isEmpty && expired.uncertainAliases.isEmpty)
        await cache.settle()
        #expect(await cache.snapshot().uncertainAliases == [0])
        await cache.forgetEverything()
        let forgotten = await cache.snapshot()
        #expect(forgotten.words == nil)
        #expect(forgotten.blockedCommands.isEmpty && forgotten.uncertainAliases.isEmpty)
    }
}
