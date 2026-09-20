// Tests that the suggestion model's weights are fetched only for somebody who asked for the feature.

import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import Uttrflow
@testable import UttrflowUX

/// Counts how many times the weights were asked for, from whichever thread asked.
private actor Asks {
    private(set) var count = 0
    /// Every ask and release in the order they ran, so a test can see that one waited for the other.
    private(set) var steps: [String] = []

    /// Records one ask, which is what the app's detached task does in place of the real download.
    func asked() {
        count += 1
        steps.append("load")
    }

    /// Records one release of the weights.
    func released() { steps.append("release") }
}

/// Holds a load open until the test lets it land, so a switch can be flipped while it is in flight.
private actor Gate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var isOpen = false

    /// Waits until ``open()``.
    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    /// Lets every waiting load through.
    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }
}

/// What a hub that will not answer throws, which is the case the app used to swallow.
private struct HubRefused: Error {}

/// Settings with tab-to-complete in one state and nothing else said.
private func settings(suggesting: Bool) -> Settings {
    Settings(suggestions: SuggestionPreferences(isEnabled: suggesting))
}

@MainActor
@Suite("Several gigabytes are not downloaded by somebody who never asked")
struct ModelDownloadTests {
    @Test("A Mac where tab-to-complete was never turned on never asks for the weights.")
    func silenceCostsNothing() async {
        let asks = Asks()
        let app = AppDelegate(container: Sandbox().root, prepareModel: { _ in await asks.asked() })
        app.settingsChanged(to: settings(suggesting: false))
        #expect(app.modelPreparation == nil)
        #expect(await asks.count == 0)
    }

    @Test("Turning it on asks for them once, and turning it off lets them go, so on again asks again.")
    func askedForOnceWhenWanted() async {
        let asks = Asks()
        let app = AppDelegate(container: Sandbox().root, prepareModel: { _ in await asks.asked() })
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await asks.count == 1)
        app.settingsChanged(to: settings(suggesting: false))
        #expect(app.suggestionModel == .notAsked)
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await asks.count == 2)
        #expect(app.suggestionModel == .ready)
    }

    @Test("Turning it off frees the weights it loaded, once.")
    func turningOffReleases() async {
        let asks = Asks()
        let app = AppDelegate(
            container: Sandbox().root, prepareModel: { _ in await asks.asked() },
            releaseModel: { await asks.released() })
        app.settingsChanged(to: settings(suggesting: false))
        await app.modelPreparation?.value
        #expect(await asks.steps.isEmpty)
        app.settingsChanged(to: settings(suggesting: true))
        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: false))
        await app.modelPreparation?.value
        #expect(await asks.steps == ["load", "release"])
    }

    @Test("A load still running when the feature is turned off is freed when it lands, and never says ready.")
    func aLoadInFlightIsFreedAfterItLands() async {
        let asks = Asks()
        let gate = Gate()
        let app = AppDelegate(
            container: Sandbox().root,
            prepareModel: { _ in
                await gate.pass()
                await asks.asked()
            },
            releaseModel: { await asks.released() })
        app.settingsChanged(to: settings(suggesting: true))
        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        app.settingsChanged(to: settings(suggesting: false))
        await gate.open()
        await app.modelPreparation?.value
        #expect(await asks.steps == ["load", "release", "load", "release"])
        #expect(app.suggestionModel == .notAsked)
    }

    @Test("A failed load that lands after the feature was turned off does not report a failure.")
    func aLateFailureIsQuiet() async {
        let gate = Gate()
        let app = AppDelegate(
            container: Sandbox().root,
            prepareModel: { _ in
                await gate.pass()
                throw HubRefused()
            })
        app.settingsChanged(to: settings(suggesting: true))
        app.settingsChanged(to: settings(suggesting: false))
        await gate.open()
        await app.modelPreparation?.value
        #expect(app.suggestionModel == .notAsked)
    }

    @Test("A fetch that failed is asked for again, rather than leaving the feature dead until a relaunch.")
    func aFailedFetchIsAskedForAgain() async {
        let asks = Asks()
        let app = AppDelegate(
            container: Sandbox().root,
            prepareModel: { _ in
                await asks.asked()
                throw HubRefused()
            })

        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(app.suggestionModel == .failed)
        #expect(await asks.count == 1)

        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await asks.count == 2)
    }

    @Test(
        "Weights found missing by a reload are asked for again in Settings, and switching off and on fetches them."
    )
    func weightsGoneMissingAreAskedForAgain() async {
        let asks = Asks()
        let app = AppDelegate(container: Sandbox().root, prepareModel: { _ in await asks.asked() })
        app.suggestionModelWentMissing()
        #expect(app.suggestionModel == .notAsked)

        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        app.suggestionModelWentMissing()
        #expect(app.suggestionModel == .failed)
        #expect(await asks.count == 1)

        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(await asks.count == 2)
        #expect(app.suggestionModel == .ready)
    }

    @Test("What it is doing is readable, so the screen has something to say while it is not ready.")
    func progressIsReadable() async {
        let app = AppDelegate(
            container: Sandbox().root,
            prepareModel: { report in
                report(0.5)
                report(1)
            })
        #expect(app.suggestionModel == .notAsked)

        app.settingsChanged(to: settings(suggesting: true))
        await app.modelPreparation?.value
        #expect(app.suggestionModel == .ready)
    }
}
