// Tests that the suggestion model's weights are fetched only for somebody who asked for the feature.

import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import Uttrflow
@testable import UttrflowUX

/// Counts how many times the weights were asked for, from whichever thread asked.
private actor Asks {
    private var count = 0

    /// Records one ask, which is what the app's detached task does in place of the real download.
    func asked() { count += 1 }

    /// How many asks have landed, waited for a moment first so a detached task has time to run.
    func settled(expecting: Int) async -> Int {
        for _ in 0..<100 where count < expecting {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return count
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
        #expect(await asks.settled(expecting: 1) == 0)
    }

    @Test("Turning it on asks for them, and turning it off and on again does not ask twice.")
    func askedForOnceWhenWanted() async {
        let asks = Asks()
        let app = AppDelegate(container: Sandbox().root, prepareModel: { _ in await asks.asked() })
        app.settingsChanged(to: settings(suggesting: true))
        #expect(await asks.settled(expecting: 1) == 1)
        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        #expect(await asks.settled(expecting: 2) == 1)
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
        await settle(app, until: .failed)
        #expect(await asks.settled(expecting: 1) == 1)

        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        #expect(await asks.settled(expecting: 2) == 2)
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
        await settle(app, until: .ready)
        #expect(app.suggestionModel == .ready)
    }

    /// Waits for the app to reach one reading, since the fetch runs beside the test rather than in it.
    private func settle(_ app: AppDelegate, until readiness: SuggestionModelReadiness) async {
        for _ in 0..<200 where app.suggestionModel != readiness {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
