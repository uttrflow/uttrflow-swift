// Tests that the update gate hears about dictation, panel and onboarding as they change.

import Foundation
import Testing
import UttrflowUX

@testable import Uttrflow

@Suite("Update activity wiring")
@MainActor
struct UpdateActivityWiringTests {
    @Test("an update staged mid-dictation installs a minute after the dictation ends")
    func dictationEndingStartsTheQuietClock() {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        var installed = false
        app.render(.recording)
        app.updates.stage({ installed = true })
        app.render(.idle)
        app.updates.refresh(at: Date().addingTimeInterval(UpdateGate.settleSeconds + 5))
        #expect(installed)
    }

    @Test(
        "an update staged while busy waits for quiet, then installs a minute later",
        arguments: [
            UpdateActivity(isDictating: true),
            UpdateActivity(isPanelOpen: true),
            UpdateActivity(isOnboarding: true),
            UpdateActivity(isSuggesting: true),
        ])
    func stagedWhileBusyInstallsOnceQuiet(busy: UpdateActivity) {
        let now = ActivityBox(busy)
        var installed = false
        let controller = UpdateController { now.activity }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        controller.stage({ installed = true }, at: start)
        now.activity = UpdateActivity()
        controller.refresh(at: start.addingTimeInterval(1))
        controller.refresh(at: start.addingTimeInterval(30))
        #expect(!installed)
        controller.refresh(at: start.addingTimeInterval(1 + UpdateGate.settleSeconds))
        #expect(installed)
    }
}

/// What the app is doing, changeable after the controller has captured it.
@MainActor
private final class ActivityBox {
    var activity: UpdateActivity

    init(_ activity: UpdateActivity) { self.activity = activity }
}
