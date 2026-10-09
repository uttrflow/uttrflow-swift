import Foundation
import Testing
import UttrflowTestSupport
import os

@testable import UttrflowLocalModel

/// Modules a test can name, so a refill is seen to reach the ones that were built.
private struct FakeModules: Sendable, Equatable {
    let serial: Int
}

/// Counts every build, refill and empty, and can hold a build until the test lets it land.
private final class LoadRecorder: Sendable {
    private let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
    private let failures = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    private let gate: AsyncStream<Void>
    private let opener: AsyncStream<Void>.Continuation
    private let holdsBuilds: Bool
    let buildStarted: AsyncStream<Void>
    private let started: AsyncStream<Void>.Continuation

    init(holdsBuilds: Bool = false) {
        (gate, opener) = AsyncStream.makeStream()
        (buildStarted, started) = AsyncStream.makeStream()
        self.holdsBuilds = holdsBuilds
    }

    var recorded: [String] { calls.withLock { $0 } }

    /// Makes the next call of this kind throw once.
    func failNext(_ kind: String) { _ = failures.withLock { $0.insert(kind) } }

    /// Lets a held build land.
    func openGate() { opener.yield() }

    var loading: WeightLoading<FakeModules> {
        WeightLoading(
            build: { _ in
                self.started.yield()
                if self.holdsBuilds {
                    for await _ in self.gate { break }
                }
                try self.record("build")
                return FakeModules(serial: self.recorded.count)
            },
            refill: { _, _ in try self.record("refill") },
            empty: { _ in try? self.record("empty") })
    }

    private func record(_ kind: String) throws {
        calls.withLock { $0.append(kind) }
        if failures.withLock({ $0.remove(kind) }) != nil { throw CocoaError(.fileReadCorruptFile) }
    }
}

@Suite("Reloading a model's weights", .timeLimit(.minutes(1)))
struct ReloadableWeightsTests {
    private let directory = URL(filePath: "/models/example")

    @Test("Twenty releases and reloads build the modules once and only refill them after")
    func reloadsNeverBuildAgain() async throws {
        let recorder = LoadRecorder()
        let weights = ReloadableWeights(loading: recorder.loading)
        let first = try await weights.load(from: directory)
        for _ in 1...20 {
            await weights.unload()
            #expect(try await weights.load(from: directory) == first)
        }
        #expect(recorder.recorded.filter { $0 == "build" }.count == 1)
        #expect(recorder.recorded.filter { $0 == "refill" }.count == 20)
        #expect(recorder.recorded.filter { $0 == "empty" }.count == 20)
    }

    @Test("A load while the weights are in reads nothing, and an unload with nothing loaded empties nothing")
    func redundantCallsDoNothing() async throws {
        let recorder = LoadRecorder()
        let weights = ReloadableWeights(loading: recorder.loading)
        await weights.unload()
        _ = try await weights.load(from: directory)
        _ = try await weights.load(from: directory)
        await weights.unload()
        await weights.unload()
        #expect(recorder.recorded == ["build", "empty"])
    }

    @Test("A load that an unload follows before it lands hands back nothing and leaves the weights out")
    func unloadAfterPendingLoadWins() async throws {
        let recorder = LoadRecorder(holdsBuilds: true)
        let weights = ReloadableWeights(loading: recorder.loading)
        let directory = directory
        let loading = Task { try await weights.load(from: directory) }
        try await arrival(of: recorder.buildStarted)
        let unloading = Task { await weights.unload() }
        try await eventually { await weights.hasPendingUnload }
        recorder.openGate()
        #expect(try await loading.value == nil)
        await unloading.value
        #expect(recorder.recorded == ["build", "empty"])
        _ = try await weights.load(from: directory)
        #expect(recorder.recorded == ["build", "empty", "refill"])
    }

    @Test("A load whose caller stops while it waits its turn reads no weights, and a later load still loads")
    func aStoppedLoadReadsNothing() async throws {
        let recorder = LoadRecorder(holdsBuilds: true)
        let weights = ReloadableWeights(loading: recorder.loading)
        let directory = directory
        let first = Task { try await weights.load(from: directory) }
        try await arrival(of: recorder.buildStarted)
        let unloading = Task { await weights.unload() }
        try await eventually { await weights.hasPendingUnload }
        let second = Task { try await weights.load(from: directory) }
        second.cancel()
        recorder.openGate()
        _ = try await first.value
        await unloading.value
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(recorder.recorded == ["build", "empty"])
        #expect(try await weights.load(from: directory) != nil)
        #expect(recorder.recorded == ["build", "empty", "refill"])
    }

    @Test("A failed build is tried again from scratch, and a failed refill is read again in full")
    func failuresAreRetried() async throws {
        let recorder = LoadRecorder()
        let weights = ReloadableWeights(loading: recorder.loading)
        recorder.failNext("build")
        await #expect(throws: CocoaError.self) { try await weights.load(from: directory) }
        _ = try await weights.load(from: directory)
        await weights.unload()
        recorder.failNext("refill")
        await #expect(throws: CocoaError.self) { try await weights.load(from: directory) }
        _ = try await weights.load(from: directory)
        #expect(recorder.recorded == ["build", "build", "empty", "refill", "refill"])
    }
}

@Suite("Concurrent model preparation")
struct InFlightModelLoadTests {
    @Test("A prepare joining a reload retries a missing model with its downloader and progress")
    func prepareRetriesDiskOnlyMiss() async throws {
        let load = InFlightModelLoad()
        let (started, signalStarted) = AsyncStream.makeStream(of: Void.self)
        let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
        let progress = ProgressRecorder()
        let missing = WeightsNotOnDisk(identifier: "example/model")
        let reload = Task {
            try await load.run(downloads: false, shouldRetry: { _ in true }) { _ in
                signalStarted.yield()
                for await _ in gate { break }
                throw missing
            }
        }
        try await arrival(of: started)
        let prepare = Task {
            try await load.run(downloads: true, shouldRetry: { $0 is WeightsNotOnDisk }) { _ in
                await progress.report(0.5)
            }
        }
        try await eventually { await load.joinerCount == 1 }
        openGate.yield()

        await #expect(throws: WeightsNotOnDisk.self) { try await reload.value }
        try await prepare.value
        #expect(await progress.values == [0.5])
    }

    /// A load that reports `0.25` and then waits for the gate, alongside one joiner holding its own progress.
    private static func sharedLoad(
        _ load: InFlightModelLoad, starterProgress: ProgressRecorder, joinerProgress: ProgressRecorder
    ) async throws -> (starter: Task<Void, any Error>, joiner: Task<Void, any Error>, open: () -> Void) {
        let (started, signalStarted) = AsyncStream.makeStream(of: Void.self)
        let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
        let starter = Task {
            try await load.run(
                downloads: true, onProgress: { value in Task { await starterProgress.report(value) } },
                shouldRetry: { _ in false }
            ) { report in
                signalStarted.yield()
                for await _ in gate { break }
                report(0.25)
            }
        }
        try await arrival(of: started)
        let joiner = Task {
            try await load.run(
                downloads: true, onProgress: { value in Task { await joinerProgress.report(value) } },
                shouldRetry: { _ in false }
            ) { _ in Issue.record("a joiner never runs its own operation") }
        }
        try await eventually { await load.joinerCount == 1 }
        return (starter, joiner, { openGate.yield() })
    }

    @Test(
        "Cancelling the first caller leaves the load running for a joiner, which also receives its progress"
    )
    func cancellingFirstCallerKeepsJoiner() async throws {
        let load = InFlightModelLoad()
        let starterProgress = ProgressRecorder()
        let joinerProgress = ProgressRecorder()
        let shared = try await Self.sharedLoad(
            load, starterProgress: starterProgress, joinerProgress: joinerProgress)
        shared.starter.cancel()
        shared.open()

        try await shared.joiner.value
        await #expect(throws: CancellationError.self) { try await shared.starter.value }
        try await eventually { await joinerProgress.values == [0.25] }
    }

    @Test("Cancelling a joiner leaves the first caller's load running")
    func cancellingJoinerKeepsFirstCaller() async throws {
        let load = InFlightModelLoad()
        let starterProgress = ProgressRecorder()
        let joinerProgress = ProgressRecorder()
        let shared = try await Self.sharedLoad(
            load, starterProgress: starterProgress, joinerProgress: joinerProgress)
        shared.joiner.cancel()
        shared.open()

        try await shared.starter.value
        await #expect(throws: CancellationError.self) { try await shared.joiner.value }
        try await eventually { await starterProgress.values == [0.25] }
    }

    @Test("Cancelling every caller stops the shared load")
    func cancellingEveryCallerStopsLoad() async throws {
        let load = InFlightModelLoad()
        let (started, signalStarted) = AsyncStream.makeStream(of: Void.self)
        let only = Task {
            try await load.run(downloads: true, shouldRetry: { _ in false }) { _ in
                signalStarted.yield()
                try await Task.sleep(for: .seconds(60))
            }
        }
        try await arrival(of: started)
        only.cancel()
        await #expect(throws: CancellationError.self) { try await only.value }
    }
}

private actor ProgressRecorder {
    private(set) var values: [Double] = []

    func report(_ value: Double) { values.append(value) }
}

/// The scorer needs a GPU and gigabytes of weights, so this reads its source to say every load goes through the reloadable weights.
@Suite("How the suggestion model loads its weights")
struct ScorerLoadWiringTests {
    @Test("Only the first load builds, through QuantizedLoad, and prepare asks the reloadable weights")
    func prepareGoesThroughReloadableWeights() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/UttrflowLocalModel/MLXCandidateScorer.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.components(separatedBy: "QuantizedLoad.container(").count == 2)
        #expect(!text.contains("loadModelContainer("))
        #expect(text.contains("try await weights.load(from: directory)"))
        #expect(text.contains("await weights.unload()"))
    }
}
