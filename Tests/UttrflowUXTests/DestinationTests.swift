import Testing

@testable import UttrflowUX

@Suite("Where the app can send you")
struct DestinationTests {
    /// The tab bars are built from these, so the order is the order on screen and a
    /// reordering that nobody meant would show up here rather than in a screenshot.
    @Test("settings tabs are in the approved design's sidebar order")
    func settingsTabOrder() {
        #expect(SettingsTab.allCases == [.general, .languages, .dictation, .privacy])
    }

    @Test("main tabs are in the order the window shows them")
    func mainTabOrder() {
        #expect(
            MainTab.allCases == [
                .home,
                .dictation, .history, .dictionary, .corrections, .insights, .snippets, .style, .diagnostics,
                .account,
            ])
    }

    /// Destinations are compared to decide whether a window is already showing what was
    /// asked for, so two ways of naming the same place must not look different.
    @Test("the same place is the same destination")
    func equality() {
        #expect(Destination.settings(.privacy) == .settings(.privacy))
        #expect(Destination.settings(.privacy) != .settings(.general))
        #expect(Destination.main(.dictation) != .settings(.general))
        #expect(Destination.onboarding == .onboarding)
    }

    /// They are dictionary keys and set members in the window controllers.
    @Test("destinations hash by what they name")
    func hashing() {
        let places: Set<Destination> = [.onboarding, .settings(.general), .settings(.general)]
        #expect(places.count == 2)
    }

    /// Persisted with the window state, so the stored spelling is part of the contract.
    @Test("tabs persist under stable names")
    func rawValues() {
        #expect(SettingsTab.languages.rawValue == "languages")
        #expect(MainTab.diagnostics.rawValue == "diagnostics")
    }
}
