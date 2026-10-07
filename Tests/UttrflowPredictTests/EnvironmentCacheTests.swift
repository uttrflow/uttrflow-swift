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

@Suite("How much the index holds (#1493)")
struct EnvironmentCapacityTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("recording past the capacity keeps the count within it and the directory still being asked about")
    func capacityHoldsAndTheCurrentDirectorySurvives() async {
        let index = EnvironmentIndex(reader: StubEnvironment([.file: ["README.md"]]))
        _ = await index.values(of: .file, in: "/here", now: Self.now)
        await index.settle()
        for step in 0..<(EnvironmentIndex.capacity + 50) {
            let at = Self.now.addingTimeInterval(Double(step) / 100)
            _ = await index.values(of: .file, in: "/here", now: at)
            _ = await index.values(of: .file, in: "/visited/\(step)", now: at)
            await index.settle()
        }
        #expect(await index.count <= EnvironmentIndex.capacity)
        #expect(await index.values(of: .file, in: "/here", now: Self.now) == ["README.md"])
    }

    @Test("an answer several lifetimes past its expiry is dropped on the next record")
    func longExpiredAnswersAreDropped() async {
        let index = EnvironmentIndex(reader: StubEnvironment([.file: ["a"]]))
        _ = await index.values(of: .file, in: "/old", now: Self.now)
        await index.settle()
        let later = Self.now.addingTimeInterval(EnvironmentIndex.lifetimeInSeconds * 10)
        _ = await index.values(of: .file, in: "/new", now: later)
        await index.settle()
        #expect(await index.count == 1)
    }
}

/// A monotonic clock that jumps a fixed step on every read.
private final class SteppingSeconds: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private let step: Double

    init(step: Double) { self.step = step }

    func next() -> Double {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += step
        return current
    }
}

@Suite("When a slow read's answer starts being believed")
struct EnvironmentSlowReadTests {
    @Test("an answer that took longer than its lifetime to read is still believed for that lifetime (#1677)")
    func aSlowReadIsNotExpiredOnArrival() async {
        let reader = StubEnvironment([.directory: ["src"]])
        let slowness = EnvironmentIndex.lifetimeInSeconds + 1
        let clock = SteppingSeconds(step: slowness)
        let index = EnvironmentIndex(reader: reader, seconds: { clock.next() })
        let asked = EnvironmentCacheTests.now

        _ = await index.values(of: .directory, in: "/slow", now: asked)
        await index.settle()
        let landed = asked.addingTimeInterval(slowness)
        let justBeforeExpiry = landed.addingTimeInterval(EnvironmentIndex.lifetimeInSeconds - 0.1)
        let justAfterLanding = landed.addingTimeInterval(0.1)
        #expect(await index.values(of: .directory, in: "/slow", now: justAfterLanding) == ["src"])
        #expect(await index.values(of: .directory, in: "/slow", now: justBeforeExpiry) == ["src"])
        await index.settle()

        #expect(await reader.reads == 1, "the answer is believed for its full lifetime from when it landed")
    }
}

/// A machine that answers each read with the next of a script, repeating the last once it runs out.
private actor ScriptedEnvironment: EnvironmentReading {
    private var answers: [[String]?]
    private(set) var reads = 0

    init(_ answers: [[String]?]) { self.answers = answers }

    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        reads += 1
        return answers.count > 1 ? answers.removeFirst() : answers.first ?? nil
    }
}

@Suite("What a failed or slow read does to the answer before it")
struct EnvironmentFailedReadTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("one failed read keeps the last good listing, and only puts off the next read")
    func aFailedReadKeepsTheLastAnswer() async {
        let reader = ScriptedEnvironment([["git", "ls"], nil])
        let index = EnvironmentIndex(reader: reader)
        let lifetime = EnvironmentIndex.programLifetimeInSeconds

        _ = await index.values(of: .executable, in: "/one", now: Self.now)
        await index.settle()
        let stale = Self.now.addingTimeInterval(lifetime + 0.5)
        #expect(await index.values(of: .executable, in: "/one", now: stale) == ["git", "ls"])
        await index.settle()
        #expect(await reader.reads == 2, "the stale answer asked the machine again, and that read failed")

        let afterFailure = stale.addingTimeInterval(0.5)
        #expect(await index.values(of: .executable, in: "/one", now: afterFailure) == ["git", "ls"])
        await index.settle()
        #expect(await reader.reads == 2, "the failure backs off the retry, not the answer")
    }

    @Test(
        "an answer long past its lifetime is not served, so a deleted branch is not offered on the first keystroke back"
    )
    func aLongExpiredAnswerIsNotServed() async {
        let reader = ScriptedEnvironment([["feature-x", "main"], ["main"]])
        let index = EnvironmentIndex(reader: reader)

        _ = await index.values(of: .branch, in: "/repo", now: Self.now)
        await index.settle()
        #expect(await index.values(of: .branch, in: "/repo", now: Self.now) == ["feature-x", "main"])

        let back = Self.now.addingTimeInterval(EnvironmentIndex.lifetimeInSeconds + 60)
        #expect(await index.values(of: .branch, in: "/repo", now: back) == nil)
        await index.settle()
        #expect(await index.values(of: .branch, in: "/repo", now: back) == ["main"])
    }

    @Test("an answer just past its lifetime is still served while the read replacing it is in flight")
    func aJustExpiredAnswerIsServedDuringItsRefresh() async {
        let reader = ScriptedEnvironment([["main"], ["main", "next"]])
        // Each read takes a set half second, so when the answer lands does not depend on how busy the machine is.
        let readTime = 0.5
        let clock = SteppingSeconds(step: readTime)
        let index = EnvironmentIndex(reader: reader, seconds: { clock.next() })

        _ = await index.values(of: .branch, in: "/repo", now: Self.now)
        await index.settle()
        let justExpired = Self.now.addingTimeInterval(readTime + EnvironmentIndex.lifetimeInSeconds + 1)
        #expect(await index.values(of: .branch, in: "/repo", now: justExpired) == ["main"])
        await index.settle()
        #expect(await reader.reads == 2)
    }
}
