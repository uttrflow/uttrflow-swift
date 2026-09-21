// What reopening the app from the Dock or Finder brings up.

/// Decides what a reopen shows from the app's own windows, since Settings or a panel may be open beside them.
enum Reopening {
    /// Shows the main window whenever it is not on screen, unless setup is, which the main window would cover.
    static func showsMainWindow(mainWindowIsVisible: Bool, onboardingIsVisible: Bool) -> Bool {
        !mainWindowIsVisible && !onboardingIsVisible
    }
}
