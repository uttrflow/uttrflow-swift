// Tests that the suggestion model's weights are fetched only for somebody who asked for the feature.

import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import Uttrflow

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
        let app = AppDelegate(container: Sandbox().root, prepareModel: { await asks.asked() })
        app.settingsChanged(to: settings(suggesting: false))
        #expect(await asks.settled(expecting: 1) == 0)
    }

    @Test("Turning it on asks for them, and turning it off and on again does not ask twice.")
    func askedForOnceWhenWanted() async {
        let asks = Asks()
        let app = AppDelegate(container: Sandbox().root, prepareModel: { await asks.asked() })
        app.settingsChanged(to: settings(suggesting: true))
        #expect(await asks.settled(expecting: 1) == 1)
        app.settingsChanged(to: settings(suggesting: false))
        app.settingsChanged(to: settings(suggesting: true))
        #expect(await asks.settled(expecting: 2) == 1)
    }
}
