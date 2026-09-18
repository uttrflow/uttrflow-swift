import Foundation
import Synchronization
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

/// Every reload event in the order it was told, collected from whichever thread tells it.
private final class Reloads: Sendable {
    private let seen = Mutex<[IdleReload]>([])

    func record(_ event: IdleReload) { seen.withLock { $0.append(event) } }

    var all: [IdleReload] { seen.withLock { $0 } }
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
        #expect(await inner.steps == ["load", "release", "load"])
    }

    @Test("a reload after an idle release says when it starts and when it is done")
    func reloadIsReported() async throws {
        let inner = RecordingModel()
        let reloads = Reloads()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600)) { reloads.record($0) }
        try await model.prepare(onProgress: { _ in })
        #expect(reloads.all.isEmpty)
        await model.releaseIfIdle(at: .now + .seconds(700))
        #expect(await model.isReady == false)
        #expect(reloads.all == [.started])
        await model.pendingWork?.value
        #expect(reloads.all == [.started, .finished])
    }

    @Test("a reload that fails says so")
    func failedReloadIsReported() async throws {
        let inner = RecordingModel()
        let reloads = Reloads()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600)) { reloads.record($0) }
        try await model.prepare(onProgress: { _ in })
        await model.releaseIfIdle(at: .now + .seconds(700))
        await inner.failNextLoad()
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        #expect(reloads.all == [.started, .failed])
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
        #expect(await inner.steps == ["load", "load", "load"])
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
