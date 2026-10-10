// Tests that the stores built at launch stay inside the budget in Docs/startup.md; `make bench` runs it.

import AppKit
import Foundation
import Testing

@testable import Uttrflow

@MainActor
@Suite("The launch path's store setup")
struct LaunchBudgetTests {
    /// The most the stores and monitors built before the shortcut may add; see `Docs/startup.md`.
    private static let budget = Duration.milliseconds(100)

    @Test("builds every store inside the launch budget")
    func storeSetupStaysInsideTheBudget() {
        let clock = ContinuousClock()
        // The fastest of three, so one scheduling stall on a busy runner is not read as a slow store.
        var fastest = Duration.seconds(60)
        for _ in 0..<3 {
            let sandbox = Sandbox()
            let start = clock.now
            let app = AppDelegate(container: sandbox.root)
            fastest = min(fastest, start.duration(to: clock.now))
            _ = app
        }
        print("AppDelegate stores built in \(fastest)")
        #expect(fastest < Self.budget)
    }
}
