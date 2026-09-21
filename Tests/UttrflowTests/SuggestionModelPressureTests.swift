// Tests that the suggestion model gives memory back under pressure and does not thrash taking it again.

import Dispatch
import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import Uttrflow
@testable import UttrflowUX

/// Every load and release in the order they ran.
private actor Steps {
    private(set) var all: [String] = []

    func record(_ step: String) { all.append(step) }
}

@Suite("How long a released model waits")
struct SuggestionModelPressurePolicyTests {
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
        var pressure = SuggestionModelPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        #expect(!pressure.isReleased)
        pressure.released(at: start)
        #expect(pressure.isReleased)
        #expect(pressure.wait == .seconds(120))
        pressure.reloaded(at: start + .seconds(130))
        #expect(!pressure.isReleased)
    }

    @Test("a reload that does not hold doubles the wait, up to the longest")
    func thrashingBacksOff() {
        var pressure = SuggestionModelPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
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
        var pressure = SuggestionModelPressure(firstWait: .seconds(120), longestWait: .seconds(1_800))
        pressure.released(at: start)
        pressure.reloaded(at: start + .seconds(120))
        pressure.released(at: start + .seconds(200))
        #expect(pressure.wait == .seconds(240))
        pressure.reloaded(at: start + .seconds(500))
        pressure.released(at: start + .seconds(2_400))
        #expect(pressure.wait == .seconds(120))
    }

    @Test("forgetting a release leaves nothing waiting")
    func forgetting() {
        var pressure = SuggestionModelPressure()
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
            container: sandbox.root, prepareModel: { _ in await steps.record("load") },
            releaseModel: { await steps.record("release") })
        app.memoryPressure = SuggestionModelPressure(firstWait: .zero, longestWait: .seconds(1_800))
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

    @Test("calm after pressure loads the model again")
    func calmReloads() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.memoryPressureChanged(to: .critical)
        app.memoryPressureChanged(to: .normal)
        await app.pressureReload?.value
        await app.modelPreparation?.value
        #expect(await steps.all == ["load", "release", "load"])
        #expect(app.suggestionModel == .ready)
        #expect(!app.memoryPressure.isReleased)
    }

    @Test("pressure returning before the calm has lasted cancels the reload")
    func pressureCancelsReload() async {
        let steps = Steps()
        let sandbox = Sandbox()
        let app = app(steps, in: sandbox)
        app.memoryPressure = SuggestionModelPressure(firstWait: .seconds(600), longestWait: .seconds(1_800))
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
}
