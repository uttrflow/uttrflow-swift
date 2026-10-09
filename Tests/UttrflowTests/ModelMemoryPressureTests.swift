// Tests that the suggestion model gives memory back under pressure and does not thrash taking it again.

import Dispatch
import Foundation
import Synchronization
import Testing
import UttrflowSettings
import UttrflowTestSupport

@testable import Uttrflow
@testable import UttrflowPredict
@testable import UttrflowUX

/// Every load and release in the order they ran.
private actor Steps {
    private(set) var all: [String] = []

    func record(_ step: String) { all.append(step) }
}

/// Lets the test elapse a calm wait without advancing wall time.
private actor PressureClock {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requested: Duration?

    func wait(_ duration: Duration) async throws {
        requested = duration
        await withCheckedContinuation { continuation = $0 }
    }

    func elapse() {
        continuation?.resume()
        continuation = nil
    }
}

/// Records the three model operations used by pressure and a later query.
private actor PressureModel: ReleasableModel {
    private(set) var steps: [String] = []
    private var loaded = false
    private var reloadFailure: (any Error)?

    func failNextReload(with error: any Error) { reloadFailure = error }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        steps.append("prepare")
        loaded = true
    }

    func reload() async throws {
        steps.append("reload")
        if let error = reloadFailure {
            reloadFailure = nil
            throw error
        }
        loaded = true
    }

    func release() async {
        steps.append("release")
        loaded = false
    }

    var isReady: Bool { loaded }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] { [] }

    func logLikelihood(of candidate: String, following context: String) async -> Double? { nil }

    func confidence(ofGenerated line: String) async -> Double? { nil }

    func forgetEverything() async {}
}

/// A reload that could not find the memory to read the weights in.
private struct ReloadOutOfMemory: Error {}

/// What the idle-releasing model tells the app, in the order it told it.
private final class ModelReports: Sendable {
    enum Report: Equatable { case reload(IdleReload), weightsMissing }

    private let seen = Mutex<[Report]>([])

    func record(_ report: Report) { seen.withLock { $0.append(report) } }

    /// Hands every report so far to the app, as the app's own wiring does, and forgets them.
    @MainActor func deliver(to app: AppDelegate) {
        let reports = seen.withLock { seen in
            let reports = seen
            seen = []
            return reports
        }
        for report in reports {
            switch report {
            case .reload(let event): app.suggestionModelReloaded(event)
            case .weightsMissing: app.suggestionModelWentMissing()
            }
        }
    }
}

@Suite("How long a released model waits")
struct ModelMemoryPressurePolicyTests {
    private let start = ContinuousClock.now

    @Test("an event names its worst level")
    func levels() {
        #expect(MemoryPressureLevel(.critical) == .critical)
        #expect(MemoryPressureLevel([.warning, .critical]) == .critical)
        #expect(MemoryPressureLevel(.warning) == .warning)
        #expect(MemoryPressureLevel(.normal) == .normal)
    }

    @Test("the first release waits the first wait, and a reload clears it")
    func firstRelease() {
        var pressure = ModelMemoryPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        #expect(!pressure.isReleased)
        pressure.released(at: start)
        #expect(pressure.isReleased)
        #expect(pressure.wait == .seconds(120))
        pressure.reloaded(at: start + .seconds(130))
        #expect(!pressure.isReleased)
    }

    @Test("a reload that does not hold doubles the wait, up to the longest")
    func thrashingBacksOff() {
        var pressure = ModelMemoryPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        var now = start
        var waits: [Duration] = []
        for _ in 0..<6 {
            pressure.released(at: now)
            waits.append(pressure.wait)
            now += pressure.wait
            pressure.reloaded(at: now)
            now += .seconds(10)
        }
        #expect(
            waits == [
                .seconds(120), .seconds(240), .seconds(480), .seconds(960), .seconds(1_800), .seconds(1_800),
            ])
    }

    @Test("a reload that held for the longest wait starts over")
    func calmResets() {
        var pressure = ModelMemoryPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        pressure.released(at: start)
        pressure.reloaded(at: start + .seconds(120))
        pressure.released(at: start + .seconds(200))
        #expect(pressure.wait == .seconds(240))
        pressure.reloaded(at: start + .seconds(500))
        pressure.released(at: start + .seconds(2_400))
        #expect(pressure.wait == .seconds(120))
    }

    @Test("a warning release waits until the last reload has held for the wait")
    func releaseWaitsForReloadToHold() {
        var pressure = ModelMemoryPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        #expect(pressure.allowsRelease(at: start))
        pressure.released(at: start)
        pressure.reloaded(at: start + .seconds(5))
        #expect(!pressure.allowsRelease(at: start + .seconds(60)))
        #expect(pressure.allowsRelease(at: start + .seconds(125)))
        pressure.released(at: start + .seconds(125))
        pressure.reloaded(at: start + .seconds(130))
        #expect(!pressure.allowsRelease(at: start + .seconds(300)))
        #expect(pressure.allowsRelease(at: start + .seconds(370)))
    }

    @Test("forgetting a release leaves nothing waiting")
    func forgetting() {
        var pressure = ModelMemoryPressure()
        pressure.released(at: start)
        pressure.forget()
        #expect(!pressure.isReleased)
    }

    @Test("the kernel's watch starts and stops")
    @MainActor
    func sourceStartsAndStops() {
        let source = MemoryPressureSource()
        source.start { _ in }
        source.start { _ in }
        #expect(source.isWatching)
        source.stop()
        #expect(!source.isWatching)
    }
}

@MainActor
@Suite("The app under memory pressure")
struct MemoryPressureTests {
    private func settings(suggesting: Bool) -> Settings {
        Settings(suggestions: SuggestionPreferences(isEnabled: suggesting))
    }

    /// An app over the caller's sandbox, which the caller keeps until the test ends.
    private func app(_ steps: Steps, in sandbox: borrowing Sandbox) -> AppDelegate {
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer,
            prepareModel: { _ in await steps.record("load") },
            releaseModel: SuggestionModelCacheOperations(
                release: { await steps.record("release") }, readBytes: { nil }, removeFiles: nil),
            allowModelReload: { await steps.record("eligible") })
        app.drawsWindows = false
        app.memoryPressure = ModelMemoryPressure(firstWait: .zero, longestWait: .seconds(1_800))
        return app
    }

    @Test("pressure releases a loaded model and says why")
    func pressureReleases() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .warning)
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release"])
        #expect(app.suggestionModel == .releasedForMemory)
        app.memoryPressureChanged(to: .critical)
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release"])
    }

    @Test("calm makes the model eligible, and a later query reloads it")
    func calmMakesModelEligibleForQuery() async throws {
        let clock = PressureClock()
        let inner = PressureModel()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600))
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer,
            scoring: model, generating: model,
            prepareModel: { onProgress in try await model.prepare(onProgress: onProgress) },
            releaseModel: SuggestionModelCacheOperations(
                release: { await model.release() }, readBytes: { nil }, removeFiles: nil),
            allowModelReload: { await model.allowReloadAfterRelease() },
            waitForCalm: { duration in try await clock.wait(duration) })
        app.drawsWindows = false
        app.memoryPressure = ModelMemoryPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await inner.steps == ["prepare"])
        app.memoryPressureChanged(to: .critical)
        app.memoryPressureChanged(to: .normal)
        try await eventually { await clock.requested == .seconds(120) }
        await clock.elapse()
        await app.pressureReload?.value
        #expect(await inner.steps == ["prepare", "release"])
        // The wrapped model, since asking the wrapper is a query that starts the reload checked below.
        #expect(await inner.isReady == false)
        #expect(app.memoryPressure.isReleased)
        #expect(app.suggestionModel == .releasedForMemory)
        #expect(await model.isReady == false)
        app.suggestionModelReloaded(.started)
        await model.pendingWork?.value
        #expect(await inner.steps == ["prepare", "release", "reload"])
        #expect(await model.isReady)
        #expect(!app.memoryPressure.isReleased)
        #expect(app.suggestionModel == .loading)
        app.suggestionModelReloaded(.finished)
        app.memoryPressureChanged(to: .warning)
        await app.modelPreparation?.value
        #expect(app.memoryPressure.wait == .seconds(240))
    }

    @Test("pressure returning before the calm has lasted cancels the reload")
    func pressureCancelsReload() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.memoryPressure = ModelMemoryPressure(firstWait: .seconds(600), longestWait: .seconds(1_800))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .warning)
        app.memoryPressureChanged(to: .normal)
        let reload = app.pressureReload
        app.memoryPressureChanged(to: .warning)
        await reload?.value
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release"])
        #expect(app.memoryPressure.isReleased)
    }

    @Test("a repeated calm keeps the countdown that is already running")
    func repeatedCalmKeepsCountdown() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.memoryPressure = ModelMemoryPressure(
            firstWait: .milliseconds(200), longestWait: .seconds(1_800))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .warning)
        app.memoryPressureChanged(to: .normal)
        let first = app.pressureReload
        app.memoryPressureChanged(to: .normal)
        #expect(app.pressureReload == first)
        await first?.value
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release", "eligible"])
        #expect(app.memoryPressure.isReleased)
    }

    @Test("pressure on a Mac that never loaded the model does nothing")
    func nothingToRelease() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.memoryPressureChanged(to: .critical)
        app.memoryPressureChanged(to: .normal)
        #expect(app.pressureReload == nil)
        app.settingsChanged(to: settings(suggesting: true))
        app.settingsChanged(to: settings(suggesting: false))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .critical)
        #expect(await steps.all == ["load", "release"])
        #expect(app.suggestionModel == .notAsked)
    }

    @Test("a reload after an idle release reads as getting ready, then ready, and the menu says so")
    func idleReloadIsShown() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.suggestionModelReloaded(.started)
        #expect(app.suggestionModel == .loading)
        #expect(
            app.menuBarPresentation.commands.contains { $0.title == "AI Suggestions, Beta — Getting ready" })
        app.suggestionModelReloaded(.started)
        #expect(app.suggestionModel == .loading)
        app.suggestionModelReloaded(.finished)
        #expect(app.suggestionModel == .ready)
        #expect(app.menuBarPresentation.commands.contains { $0.title == "AI Suggestions, Beta" })
        app.suggestionModelReloaded(.finished)
        #expect(app.suggestionModel == .ready)
    }

    @Test("a reload that fails reads as failed, and turning the feature off and on tries again")
    func failedIdleReloadIsShown() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.suggestionModelReloaded(.failed)
        #expect(app.suggestionModel == .ready)
        app.suggestionModelReloaded(.started)
        app.suggestionModelReloaded(.failed)
        #expect(app.suggestionModel == .loadFailed)
        app.suggestionModelReloaded(.started)
        #expect(app.suggestionModel == .loadFailed)
        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(app.suggestionModel == .ready)
    }

    @Test(
        "a reload that fails for lack of memory reads as a load failure, and a later query's reload shows ready",
        .bug(id: 5270))
    func genericReloadFailureIsALoadFailure() async throws {
        let inner = PressureModel()
        let reports = ModelReports()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(600)) { reports.record(.reload($0)) }
        await model.whenReloadFails { error in
            // As the app's wiring does: only weights gone from disk ask for a fetch.
            if !(error is ReloadOutOfMemory) { reports.record(.weightsMissing) }
        }
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer,
            scoring: model, generating: model,
            prepareModel: { onProgress in try await model.prepare(onProgress: onProgress) },
            releaseModel: SuggestionModelCacheOperations(
                release: { await model.release() }, readBytes: { nil }, removeFiles: nil),
            allowModelReload: { await model.allowReloadAfterRelease() })
        app.drawsWindows = false
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await model.releaseIfIdle(at: .seconds(700)) == false)

        await inner.failNextReload(with: ReloadOutOfMemory())
        #expect(await model.isReady == false)
        await model.pendingWork?.value
        reports.deliver(to: app)
        #expect(app.suggestionModel == .loadFailed)

        #expect(await model.isReady == false)
        await model.pendingWork?.value
        reports.deliver(to: app)
        #expect(await model.isReady)
        #expect(app.suggestionModel == .ready)
        #expect(await inner.steps == ["prepare", "release", "reload", "reload"])
    }

    @Test("a reload reported while the feature is off changes nothing")
    func reloadWhileOffIsIgnored() {
        let sandbox = Sandbox()
        let app = app(Steps(), in: sandbox)
        app.suggestionModelReloaded(.started)
        #expect(app.suggestionModel == .notAsked)
    }

    @Test("turning the feature off while released leaves nothing to reload")
    func offForgetsTheRelease() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .warning)
        app.settingsChanged(to: settings(suggesting: false))
        app.memoryPressureChanged(to: .normal)
        await app.pressureReload?.value
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release"])
    }

    /// An app whose first load runs until it is stopped, as a download or a slow read does.
    private func appWithSlowFirstLoad(_ steps: Steps, in sandbox: borrowing Sandbox) -> AppDelegate {
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer,
            prepareModel: { _ in
                let first = await steps.all.isEmpty
                await steps.record("load")
                guard first else { return }
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    await steps.record("stopped")
                    throw error
                }
            },
            releaseModel: SuggestionModelCacheOperations(
                release: { await steps.record("release") }, readBytes: { nil }, removeFiles: nil),
            allowModelReload: { await steps.record("eligible") })
        app.drawsWindows = false
        app.memoryPressure = ModelMemoryPressure(firstWait: .zero, longestWait: .seconds(1_800))
        return app
    }

    @Test(
        "pressure during a load stops it, and calm leaves the model unloaded",
        .timeLimit(.minutes(1)))
    func pressureStopsALoad() async throws {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = appWithSlowFirstLoad(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        try await eventually { await steps.all == ["load"] }
        app.memoryPressureChanged(to: .warning)
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "stopped", "release"])
        #expect(app.suggestionModel == .releasedForMemory)
        app.memoryPressureChanged(to: .normal)
        await app.pressureReload?.value
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "stopped", "release", "eligible"])
        #expect(app.suggestionModel == .releasedForMemory)
    }

    @Test(
        "turning the feature off during a load stops the load instead of waiting for it",
        .timeLimit(.minutes(1)))
    func offStopsALoad() async throws {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = appWithSlowFirstLoad(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        try await eventually { await steps.all == ["load"] }
        app.settingsChanged(to: settings(suggesting: false))
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "stopped", "release"])
        #expect(app.suggestionModel == .notAsked)
    }
}
