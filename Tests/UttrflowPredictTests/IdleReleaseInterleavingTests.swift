// Tests that a load finishing after something newer was asked for never changes what the wrapper believes it holds.

import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

/// A model that can hold one load on a gate, fails loads on a seeded coin, and yields inside every step.
private actor InterleavedModel: ReleasableModel {
    private(set) var isLoaded = false
    private(set) var mostInside = 0
    private(set) var loads = 0
    private var inside = 0
    private var coin: Seeded
    private let failOneIn: Int
    private let yields: Int
    private var gate: CheckedContinuation<Void, Never>?
    private var holdNext = false
    private var failHeld = false

    init(seed: Int = 1, failOneIn: Int = 0, yields: Int = 0) {
        coin = Seeded(seed: seed)
        self.failOneIn = failOneIn
        self.yields = yields
    }

    /// Makes the next load wait for ``openGate()``, and throw once it is let through when `failing`.
    func holdNextLoad(failing: Bool) {
        holdNext = true
        failHeld = failing
    }

    /// Fires when a load starts waiting on the gate.
    let gateHeld = Signal()

    func openGate() {
        gate?.resume()
        gate = nil
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        inside += 1
        mostInside = max(mostInside, inside)
        defer { inside -= 1 }
        loads += 1
        if holdNext {
            holdNext = false
            await withCheckedContinuation {
                gate = $0
                gateHeld.fire()
            }
            if failHeld { throw CancellationError() }
        }
        for _ in 0..<yields { await Task.yield() }
        if failOneIn > 0, Int.random(in: 0..<failOneIn, using: &coin) == 0 { throw CancellationError() }
        isLoaded = true
        onProgress(1)
    }

    /// Races exactly as a load does, since a query's reload is one.
    func reload() async throws {
        try await prepare(onProgress: { _ in })
    }

    func release() async {
        inside += 1
        mostInside = max(mostInside, inside)
        defer { inside -= 1 }
        for _ in 0..<yields { await Task.yield() }
        isLoaded = false
    }

    var isReady: Bool { isLoaded }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        for _ in 0..<yields { await Task.yield() }
        return [typed]
    }

    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] { [] }

    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        isLoaded ? -1 : nil
    }
}

@Suite("A stale load never clobbers newer state", .timeLimit(.minutes(1)))
struct IdleReleaseInterleavingTests {
    private let situation = GenerationSituation(application: "Notes")

    /// Waits until the chain of loads and releases stops growing.
    private func drain(_ model: IdleReleasingModel<InterleavedModel>) async {
        while true {
            let work = await model.pendingWork
            await work?.value
            if await model.pendingWork == work { return }
        }
    }

    @Test("a failed prepare that lands after a release and a new prepare leaves the new load held")
    func staleFailedPrepare() async throws {
        let inner = InterleavedModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        await inner.holdNextLoad(failing: true)
        let first = Task { try await model.prepare(onProgress: { _ in }) }
        try await arrival(of: inner.gateHeld.fired)
        let releasing = Task { await model.release() }
        try await eventually { await !model.holdsTheModel }
        let second = Task { try await model.prepare(onProgress: { _ in }) }
        try await eventually { await model.holdsTheModel }
        await inner.openGate()
        _ = await first.result
        await releasing.value
        try await second.value
        await drain(model)
        #expect(await inner.isLoaded)
        #expect(await model.holdsTheModel)
        #expect(await model.releaseIfIdle(at: .now + .seconds(7_200)) == false)
        #expect(await inner.isLoaded == false)
    }

    @Test("a failed background reload that lands after a release and a new prepare leaves the new load held")
    func staleFailedReload() async throws {
        let inner = InterleavedModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        try await model.prepare(onProgress: { _ in })
        #expect(await model.releaseIfIdle(at: .now + .seconds(7_200)) == false)
        await inner.holdNextLoad(failing: true)
        #expect(await model.isReady == false)
        try await arrival(of: inner.gateHeld.fired)
        let releasing = Task { await model.release() }
        try await eventually { await !model.holdsTheModel }
        let second = Task { try await model.prepare(onProgress: { _ in }) }
        try await eventually { await model.holdsTheModel }
        await inner.openGate()
        await releasing.value
        try await second.value
        await drain(model)
        #expect(await inner.isLoaded)
        #expect(await model.holdsTheModel)
        #expect(await model.releaseIfIdle(at: .now + .seconds(7_200)) == false)
        #expect(await inner.isLoaded == false)
    }

    @Test("a query while a background reload is still loading starts no second load")
    func queryDuringReload() async throws {
        let inner = InterleavedModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        try await model.prepare(onProgress: { _ in })
        #expect(await model.releaseIfIdle(at: .now + .seconds(7_200)) == false)
        await inner.holdNextLoad(failing: false)
        #expect(await model.isReady == false)
        try await arrival(of: inner.gateHeld.fired)
        #expect(await model.isReady == false)
        await inner.openGate()
        await drain(model)
        #expect(await model.isReady)
        #expect(await inner.loads == 2)
    }

    @Test("a load that fails while the weights are still in memory keeps them held, so idleness lets them go")
    func failureOverLoadedWeights() async throws {
        let inner = InterleavedModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        try await model.prepare(onProgress: { _ in })
        await inner.holdNextLoad(failing: true)
        let failing = Task { try await model.prepare(onProgress: { _ in }) }
        try await arrival(of: inner.gateHeld.fired)
        await inner.openGate()
        await #expect(throws: CancellationError.self) { try await failing.value }
        #expect(await model.holdsTheModel)
        #expect(await model.releaseIfIdle(at: .now + .seconds(7_200)) == false)
        #expect(await inner.isLoaded == false)
    }

    @Test("seeded schedules of prepare, release, queries and idle checks never leave the hold out of step")
    func seededSchedules() async {
        var rng = Seeded(seed: 0x442)
        var outOfStep = 0
        var firstOutOfStep = ""
        var overlaps = 0
        var loadedAfterRelease = 0
        for round in 0..<1_500 {
            let failOneIn = rng.pick([0, 0, 2, 4])
            let inner = InterleavedModel(
                seed: Int(truncatingIfNeeded: rng.next()), failOneIn: failOneIn,
                yields: Int.random(in: 0...4, using: &rng))
            let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
            var schedule: [String] = []
            var inFlight: [Task<Void, Never>] = []
            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let (name, task) = operation(Int.random(in: 0...6, using: &rng), on: model)
                schedule.append(name)
                if rng.chance(0.5) { await task.value } else { inFlight.append(task) }
            }
            for task in inFlight { await task.value }
            await drain(model)
            if await inner.isLoaded != model.holdsTheModel {
                outOfStep += 1
                if outOfStep == 1 { firstOutOfStep = "round \(round), one in \(failOneIn): \(schedule)" }
            }
            if await inner.mostInside > 1 { overlaps += 1 }
            await model.release()
            _ = await model.isReady
            await drain(model)
            if await inner.isLoaded { loadedAfterRelease += 1 }
        }
        #expect(outOfStep == 0, "first out of step: \(firstOutOfStep)")
        #expect(overlaps == 0)
        #expect(loadedAfterRelease == 0)
    }

    /// One schedule step by its number, named for the failure message.
    private func operation(
        _ number: Int, on model: IdleReleasingModel<InterleavedModel>
    ) -> (String, Task<Void, Never>) {
        let situation = situation
        switch number {
        case 0, 1: return ("prepare", Task { try? await model.prepare(onProgress: { _ in }) })
        case 2: return ("release", Task { await model.release() })
        case 3: return ("isReady", Task { _ = await model.isReady })
        case 4: return ("pass", Task { _ = try? await model.completions(for: "he", in: situation) })
        case 5: return ("idle", Task { await model.releaseIfIdle(at: .now + .seconds(7_200)) })
        default: return ("notIdle", Task { await model.releaseIfIdle(at: .now) })
        }
    }
}
