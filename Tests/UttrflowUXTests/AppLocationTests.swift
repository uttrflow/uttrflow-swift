import Testing

@testable import UttrflowUX

@Suite("Where the app can send you")
struct AppLocationTests {
    /// The tab bars are built from these, so an unmeant reordering shows up here, not in a screenshot.
    @Test("settings tabs are in the approved design's sidebar order")
    func settingsTabOrder() {
        #expect(
            SettingsTab.allCases == [.general, .languages, .dictation, .suggestions, .privacy, .diagnostics])
    }

    @Test("main tabs are in the order the window shows them")
    func mainTabOrder() {
        #expect(
            MainTab.allCases == [
                .home,
                .history, .dictionary, .corrections, .insights, .snippets, .account,
            ])
    }

    /// Two ways of naming one place compare equal, which is how "already showing it" is decided.
    @Test("the same place is the same destination")
    func equality() {
        #expect(AppLocation.settings(.privacy) == .settings(.privacy))
        #expect(AppLocation.settings(.privacy) != .settings(.general))
        #expect(AppLocation.main(.history) != .settings(.general))
        #expect(AppLocation.onboarding == .onboarding)
    }

    /// They are dictionary keys and set members in the window controllers.
    @Test("destinations hash by what they name")
    func hashing() {
        let places: Set<AppLocation> = [.onboarding, .settings(.general), .settings(.general)]
        #expect(places.count == 2)
    }

    /// Persisted with the window state, so the stored spelling is part of the contract.
    @Test("tabs persist under stable names")
    func rawValues() {
        #expect(SettingsTab.languages.rawValue == "languages")
        #expect(SettingsTab.diagnostics.rawValue == "diagnostics")
        #expect(MainTab.corrections.rawValue == "corrections")
    }
}
