// Tests that a machine-wide read serves every directory, and a failing listing backs off (#890).
import Foundation
import Testing

@testable import UttrflowPredict

@Suite("What the index asks the machine, and how often")
struct EnvironmentCacheTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(
        "one read serves every directory for what does not depend on one",
        arguments: [EnvironmentKind.executable, .alias, .subcommand(of: "git")])
    func machineWideKindsAreReadOnce(_ kind: EnvironmentKind) async {
        let reader = StubEnvironment([kind: ["ls"]])
        let index = EnvironmentIndex(reader: reader)

        _ = await index.values(of: kind, in: "/one", now: Self.now)
        await index.settle()
        _ = await index.values(of: kind, in: "/two", now: Self.now)
        await index.settle()

        #expect(await reader.reads == 1)
        #expect(await index.values(of: kind, in: "/two", now: Self.now) == ["ls"])
    }

    @Test(
        "what the project answers is still read per directory",
        arguments: [EnvironmentKind.subcommand(of: "make"), .subcommand(of: "npm"), .file, .branch])
    func projectKindsAreReadPerDirectory(_ kind: EnvironmentKind) async {
        let reader = StubEnvironment([kind: ["build"]])
        let index = EnvironmentIndex(reader: reader)

        _ = await index.values(of: kind, in: "/one", now: Self.now)
        await index.settle()
        _ = await index.values(of: kind, in: "/two", now: Self.now)
        await index.settle()

        #expect(await reader.reads == 2)
    }

    @Test("a listing that keeps failing is left alone for longer each time, up to ten minutes")
    func failuresBackOff() {
        let kind = EnvironmentKind.subcommand(of: "git")
        let once = EnvironmentIndex.lifetime(of: kind, failures: 1)
        #expect(EnvironmentIndex.lifetime(of: kind, failures: 0) == EnvironmentIndex.programLifetimeInSeconds)
        #expect(once == EnvironmentIndex.programLifetimeInSeconds * 2)
        #expect(EnvironmentIndex.lifetime(of: kind, failures: 2) == once * 2)
        #expect(EnvironmentIndex.lifetime(of: kind, failures: 20) == EnvironmentIndex.longestBackoffInSeconds)
    }

    @Test("a program that never answers is asked once, then not again for the backoff")
    func aFailingListingIsNotRetriedAtOnce() async {
        let reader = StubEnvironment([:])
        let index = EnvironmentIndex(reader: reader)
        let kind = EnvironmentKind.subcommand(of: "git")

        _ = await index.values(of: kind, in: "/one", now: Self.now)
        await index.settle()
        let later = Self.now.addingTimeInterval(EnvironmentIndex.programLifetimeInSeconds + 1)
        _ = await index.values(of: kind, in: "/one", now: later)
        await index.settle()

        #expect(await reader.reads == 1, "the second ask is inside the doubled lifetime")
    }
}
