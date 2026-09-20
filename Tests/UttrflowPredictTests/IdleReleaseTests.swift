import Foundation
import Testing

@testable import UttrflowPredict

/// A model that records every load and release, and can be told to fail its next load.
private actor RecordingModel: ReleasableModel {
    private(set) var steps: [String] = []
    private var isLoaded = false
    private var failNext = false

    func failNextLoad() { failNext = true }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        steps.append("load")
        if failNext {
            failNext = false
            throw CancellationError()
        }
        onProgress(1)
        isLoaded = true
    }

    /// A load from disk alone, which is all a query may start.
    func reload() async throws {
        steps.append("reload")
        if failNext {
            failNext = false
            throw CancellationError()
        }
        isLoaded = true
    }

    func release() async {
        steps.append("release")
        isLoaded = false
    }

    var isReady: Bool { isLoaded }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        [typed + " done"]
    }

    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        [typed + " other"]
    }

    func logLikelihood(of candidate: String, following context: String) async -> Double? { -1 }
}

/// Counts the app being told a reload failed, and lets a test wait for the first telling.
private actor Told {
    private var count = 0
    private var waiting: CheckedContinuation<Void, Never>?

    func note() {
        count += 1
        waiting?.resume()
        waiting = nil
    }

    func waitForOne() async {
        guard count == 0 else { return }
        await withCheckedContinuation { waiting = $0 }
    }
}

@Suite("Letting an idle model go")
struct IdleReleaseTests {
    private let situation = GenerationSituation(application: "Mail", surroundings: "the draft")

    @Test("a Mac under 16 GB gets the short window")
    func windowByMemory() {
        #expect(IdleRelease.window(physicalMemory: 8 * 1_073_741_824) == .seconds(180))
        #expect(IdleRelease.window(physicalMemory: 16 * 1_073_741_824) == .seconds(600))
        #expect(IdleRelease.window(physicalMemory: 48 * 1_073_741_824) == .seconds(600))
    }

    @Test("a model asked for within the window is kept, and one left alone past it is let go")
    func idleReleases() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        try await model.prepare(onProgress: { _ in })
        let asked = ContinuousClock.now
        #expect(await model.isReady)
        #expect(await model.releaseIfIdle(at: asked + .seconds(599)))
        #expect(await model.releaseIfIdle(at: asked + .seconds(601)) == false)
        #expect(await inner.steps == ["load", "release"])
        #expect(await model.holdsTheModel == false)
    }

    @Test("every way into the model counts as asking")
    func usingCounts() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        try await model.prepare(onProgress: { _ in })
        let start = ContinuousClock.now
        _ = try await model.completions(for: "Thanks", in: situation)
        _ = try await model.alternatives(for: "Thanks", in: situation, excluding: "Thanks done")
        #expect(await model.logLikelihood(of: "Thanks a lot", following: "Thanks") == -1)
        #expect(await model.releaseIfIdle(at: start + .seconds(599)))
    }

    @Test("a query after an idle release loads it again in the background")
    func queryReloads() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        try await model.prepare(onProgress: { _ in })
        await model.releaseIfIdle(at: .now + .seconds(700))
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(await model.isReady)
        #expect(await inner.steps == ["load", "release", "reload"])
    }

    @Test("a query's reload never fetches: it reads from disk, and a failure is told to the app instead")
    func queryNeverDownloads() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        let told = Told()
        await model.whenReloadFails { Task { await told.note() } }
        try await model.prepare(onProgress: { _ in })
        await model.releaseIfIdle(at: .now + .seconds(700))
        await inner.failNextLoad()
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(await inner.steps == ["load", "release", "reload"])
        #expect(await model.holdsTheModel == false)
        await told.waitForOne()
        try await model.reload()
        #expect(await inner.steps == ["load", "release", "reload", "reload"])
    }

    @Test("the discretionary wrapper passes the reload report through to the model inside it")
    func theWrapperPassesTheReportOn() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        let told = Told()
        await DiscretionaryModel(model, mayRun: { true }).whenReloadFails { Task { await told.note() } }
        try await model.prepare(onProgress: { _ in })
        await model.releaseIfIdle(at: .now + .seconds(700))
        await inner.failNextLoad()
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        await told.waitForOne()
    }

    @Test("a release the caller asked for is never undone by a query")
    func explicitReleaseStays() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        try await model.prepare(onProgress: { _ in })
        await model.release()
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(await inner.steps == ["load", "release"])
        #expect(await model.releaseIfIdle(at: .now + .seconds(700)) == false)
    }

    @Test("a model never loaded is not released for idling")
    func nothingHeld() async {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        #expect(await model.releaseIfIdle(at: .now + .seconds(700)) == false)
        #expect(await model.isReady == false)
        #expect(await inner.steps.isEmpty)
    }

    @Test("a failed load lets a later query try again")
    func failedLoads() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        await inner.failNextLoad()
        await #expect(throws: CancellationError.self) { try await model.prepare(onProgress: { _ in }) }
        #expect(await model.holdsTheModel == false)
        await inner.failNextLoad()
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(await model.holdsTheModel == false)
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(await model.isReady)
        #expect(await inner.steps == ["load", "reload", "reload"])
    }

    @Test("the watch lets the model go by itself once the window passes")
    func watchReleases() async throws {
        let inner = RecordingModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .milliseconds(40))
        try await model.prepare(onProgress: { _ in })
        await model.watching?.value
        #expect(await inner.steps == ["load", "release"])
    }
}
