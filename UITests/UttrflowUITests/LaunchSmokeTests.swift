// That the app opens at all, and that every settings pane draws. Nothing here needs a permission.

import XCTest

/// The floor: a build that cannot open a window is broken in a way no headless test can see.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheAppLaunches() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "the app never came up")
        app.terminate()
    }

    func testEverySettingsPaneDraws() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        app.menuBars.menuBarItems["Uttrflow"].click()
        app.menuItems["Settings..."].click()

        let settings = app.windows["Uttrflow Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings never opened")

        for pane in ["General", "Languages", "Dictation", "Suggestions", "Privacy"] {
            settings.buttons[pane].click()
            XCTAssertTrue(
                settings.staticTexts[pane].waitForExistence(timeout: 5), "\(pane) drew nothing")
        }
        app.terminate()
    }

    func testQuittingLeavesNothingRunning() {
        let app = AppUnderTest.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), "the app did not quit cleanly")
    }
}
