// That the app opens at all, and that every settings pane draws. Nothing here needs a permission.

import XCTest

/// The floor: a build that cannot open a window is broken in a way no headless test can see.
@MainActor
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheAppLaunches() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "the app never came up")
        AppUnderTest.terminate(app)
    }

    func testEverySettingsPaneDraws() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        app.menuBars.menuBarItems["Uttrflow"].click()
        app.menuItems["Settings…"].click()

        // Settings is a page of the main window, next to its sidebar.
        let settings = app.windows["Uttrflow"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings never opened")

        // A beta tab is read out with its status, as `BetaFeature.accessibilityName` words it.
        let labels = ["AI suggestions": "AI suggestions, beta"]
        for pane in ["General", "Languages", "Dictation", "AI suggestions", "Privacy", "Diagnostics"] {
            let tab = settings.buttons[labels[pane] ?? pane]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "there is no \(pane) tab")
            tab.click()
            XCTAssertTrue(tab.isSelected, "\(pane) did not open")
        }
        AppUnderTest.terminate(app)
    }

    func testQuittingLeavesNothingRunning() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        AppUnderTest.terminate(app)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), "the app did not quit cleanly")
    }

    func testLaunchUsesDisposableStoresAndLocks() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let container = AppUnderTest.container(for: app)
        XCTAssertNotNil(container)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: container!.appending(path: "Uttrflow/instance.lock").path(percentEncoded: false)),
            "the app did not place its instance lock in the disposable container")
        XCTAssertNotNil(
            AppUnderTest.savedValue(forKey: "com.uttrflow.settings.v1", container: container!),
            "the app did not pin settings in its disposable defaults suite")
        AppUnderTest.terminate(app)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container!.path(percentEncoded: false)),
            "the test container was not cleaned up")
    }
}
