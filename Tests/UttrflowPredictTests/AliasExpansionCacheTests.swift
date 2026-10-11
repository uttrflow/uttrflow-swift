// Tests bounded shell metadata, expiry and forgetting without reading a person's configuration.
import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

private actor AliasReader: AliasExpansionReading {
    var answer: [String: [String]]?
    var calls = 0
    var blocked = false
    private var gate: CheckedContinuation<[String: [String]]?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(_ answer: [String: [String]]?, blocked: Bool = false) {
        self.answer = answer
        self.blocked = blocked
    }

    func aliasExpansions() async -> [String: [String]]? {
        calls += 1
        started?.resume()
        started = nil
        if blocked { return await withCheckedContinuation { gate = $0 } }
        return answer
    }

    func waitForRead() async {
        if calls == 0 { await withCheckedContinuation { started = $0 } }
    }

    func release(_ answer: [String: [String]]?) {
        blocked = false
        self.answer = answer
        gate?.resume(returning: answer)
        gate = nil
    }

    func fail() { answer = nil }
}

private actor AliasLaunches: ProgramLaunching {
    var launches: [ProgramLaunch] = []
    func output(of launch: ProgramLaunch) async -> String? {
        launches.append(launch)
        return "status\n"
    }
}

struct AliasExpansionCacheTests {
    @Test func completeBodiesRespectBothBounds() {
        let many = Dictionary(uniqueKeysWithValues: (0..<250).map { ("a\($0)", ["git", "status"]) })
        #expect(AliasExpansionCache<ContinuousClock>.bounded(many).count == 200)
        let large = ["a": [String(repeating: "x", count: 65_534)], "b": ["git"]]
        let bounded = AliasExpansionCache<ContinuousClock>.bounded(large)
        #expect(bounded == ["b": ["git"]])
        let exact = ["a": [String(repeating: "x", count: 65_532)]]
        #expect(AliasExpansionCache<ContinuousClock>.bounded(exact) == exact)
        #expect(
            AliasExpansionCache<ContinuousClock>.bounded(["a": [String(repeating: "🙂", count: 16_384)]])
                .isEmpty)
        #expect(AliasExpansionCache<ContinuousClock>.bounded(["a": []]).isEmpty)
    }

    @Test func refreshesCoalesceAndForgetRejectsDelayedCompletion() async {
        let reader = AliasReader(["g": ["git"]], blocked: true)
        let cache = AliasExpansionCache(reader: reader, clock: ManualClock())
        #expect(await cache.snapshot().words == nil)
        await reader.waitForRead()
        let pending = await cache.pendingRead
        _ = await cache.snapshot()
        #expect(await reader.calls == 1)
        await cache.forgetEverything()
        await reader.release(["g": ["git"]])
        await pending?.value
        #expect(await cache.snapshot().words == nil)
        await cache.settle()
        #expect(await cache.snapshot().words == ["g": ["git"]])
        #expect(await reader.calls == 2)
        let before = await cache.snapshot().revision
        await cache.forgetEverything()
        #expect(await cache.snapshot().revision > before)
    }

    @Test func failedRefreshDoesNotExtendTheOldAnswer() async {
        let clock = ManualClock()
        let reader = AliasReader(["g": ["git"]])
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        let initial = await cache.snapshot()
        await reader.fail()
        clock.advance(by: .seconds(60))
        #expect(await cache.snapshot().words == initial.words)
        await cache.settle()
        clock.advance(by: .seconds(2))
        #expect(await cache.snapshot().words == nil)
        #expect(await cache.snapshot().revision > initial.revision)
        #expect(await reader.calls == 2)
    }

    @Test func expiryPurgesWithoutAnotherRequest() async {
        let clock = ManualClock()
        let cache = AliasExpansionCache(reader: AliasReader(["g": ["git"]]), clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        let revision = await cache.snapshot().revision
        await clock.waitUntilSomethingIsWaiting()
        clock.advance(by: .seconds(62))
        let expiry = await cache.pendingExpiry
        await expiry?.value
        #expect(await cache.retainedAliasCount == 0)
        #expect(await cache.snapshot().revision > revision)
    }

    @Test func changedAndInitiallyFailedAnswersPublishNewRevisions() async {
        let clock = ManualClock()
        let reader = AliasReader(nil)
        let cache = AliasExpansionCache(reader: reader, clock: clock)
        _ = await cache.snapshot()
        await cache.settle()
        #expect(await cache.snapshot().words == nil)
        #expect(await reader.calls == 1)
        await reader.release(["g": ["git"]])
        clock.advance(by: .seconds(60))
        _ = await cache.snapshot()
        await cache.settle()
        let first = await cache.snapshot()
        await reader.release(["g": ["npm"]])
        clock.advance(by: .seconds(60))
        #expect(await cache.snapshot().words == first.words)
        await cache.settle()
        #expect(await cache.snapshot().words == ["g": ["npm"]])
        #expect(await cache.snapshot().revision > first.revision)
        #expect(await reader.calls == 3)
    }

    @Test func aReaderWithoutBodiesPreservesTheEmptyMapping() async {
        let cache = AliasExpansionCache<ContinuousClock>(reader: nil, clock: ContinuousClock())
        #expect(await cache.snapshot().words == [:])
        #expect(await cache.pendingRead == nil)
    }

    @Test func theExistingParserAndOnlyFiveFilesSupplyBodies() async {
        let files = FakeDisk(
            home: "/fixture",
            texts: [
                "/fixture/.zshrc":
                    "alias g='git'\nalias go='g checkout'\nalias bad='echo hi | cat'\nalias unresolved='git $TARGET'\nalias redirect='cat > file'\n",
                "/fixture/.aliases": "alias g='npm'\nalias cycle='cycle'\n",
            ])
        let launches = AliasLaunches()
        let reader = SystemEnvironmentReader(launcher: launches, programDirectories: [], files: files)
        #expect(
            await reader.aliasExpansions() == [
                "g": ["npm"], "go": ["g", "checkout"], "cycle": ["cycle"],
            ])
        let reads = files.operations.filter { if case .read = $0 { true } else { false } }
        #expect(reads == SystemEnvironmentReader.aliasFiles.map { .read("/fixture/\($0)") })
        #expect(await launches.launches.isEmpty)
    }

    @Test func missingFilesAreEmptyButUnreadableOrOversizedFilesAreIncomplete() async {
        let disks = [
            FakeDisk(home: "/fixture", files: ["/fixture/.zshrc"]),
            FakeDisk(home: "/fixture", unknown: ["/fixture/.zshrc"]),
            FakeDisk(
                home: "/fixture",
                texts: [
                    "/fixture/.zshrc": String(repeating: "x", count: SystemEnvironmentReader.fileLimit + 1)
                ]),
        ]
        for files in disks {
            let reader = SystemEnvironmentReader(
                launcher: AliasLaunches(), programDirectories: [], files: files)
            #expect(await reader.aliasExpansions() == nil)
            #expect(await reader.values(of: .alias, in: "/repo") == [])
        }
        let reader = SystemEnvironmentReader(
            launcher: AliasLaunches(), programDirectories: [], files: FakeDisk(home: "/fixture"))
        #expect(await reader.aliasExpansions() == [:])
    }

    @Test func theConstructorUsesOnlyItsSyntheticHome() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try "alias fixture='git checkout'\n".write(
            to: home.appendingPathComponent(".aliases"), atomically: true, encoding: .utf8)
        let reader = SystemEnvironmentReader(environment: ["UTTRFLOW_TEST_CONTAINER": home.path])
        #expect(await reader.aliasExpansions() == ["fixture": ["git", "checkout"]])
        for invalid in ["", "relative", "/", "/tmp/..", "\0"] {
            let reader = SystemEnvironmentReader(environment: ["UTTRFLOW_TEST_CONTAINER": invalid])
            #expect(await reader.aliasExpansions() == [:])
        }
        #expect(SystemEnvironmentReader.home(in: [:]) == NSHomeDirectory())
    }

    @Test func subprocessHomeFollowsTheFilesystemAndFixtureIgnoresSystemGit() async {
        let files = FakeDisk(home: "/fixture", executables: SystemEnvironmentReader.gitPaths)
        for fixture in [false, true] {
            let launches = AliasLaunches()
            let reader = SystemEnvironmentReader(
                launcher: launches, programDirectories: [], files: files, isFixture: fixture)
            _ = await reader.values(of: .subcommand(of: "git"), in: "/repo")
            let recorded = await launches.launches
            #expect(!recorded.isEmpty)
            #expect(recorded.allSatisfy { $0.environment["HOME"] == "/fixture" })
            #expect(recorded.allSatisfy { $0.environment["GIT_CONFIG_NOSYSTEM"] == (fixture ? "1" : nil) })
        }
    }
}
