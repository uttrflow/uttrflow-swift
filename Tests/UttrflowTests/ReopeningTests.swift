// Tests what reopening the app from the Dock or Finder brings up.

import Testing

@testable import Uttrflow

@Suite("Reopening the app from the Dock")
struct ReopeningTests {
    @Test("brings the main window back when it is closed, even with Settings open")
    func showsAClosedMainWindow() {
        #expect(Reopening.showsMainWindow(mainWindowIsVisible: false, onboardingIsVisible: false))
    }

    @Test("leaves a main window already on screen as it is")
    func leavesAVisibleMainWindow() {
        #expect(!Reopening.showsMainWindow(mainWindowIsVisible: true, onboardingIsVisible: false))
    }

    @Test("leaves setup in front rather than covering it with the main window")
    func leavesSetupInFront() {
        #expect(!Reopening.showsMainWindow(mainWindowIsVisible: false, onboardingIsVisible: true))
    }
}
