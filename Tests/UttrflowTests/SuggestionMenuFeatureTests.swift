import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

@Suite("The menu suggestion tick follows the last external application")
struct SuggestionMenuFeatureTests {
    @Test("opening the menu preserves a denied external app as its suggestion context")
    func deniedApplicationStaysUncheckedAfterMenuActivation() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let application = "com.example.notes"
        var context = AppDelegate.suggestionApplicationContext(previous: nil, frontmost: application)

        context = AppDelegate.suggestionApplicationContext(
            previous: context, frontmost: "com.uttrflow.Uttrflow")

        #expect(context == application)
        let settings = Settings(
            suggestions: SuggestionPreferences(isEnabled: true, turnedOff: [application]))
        let onMenuOpen = MenuBarFeatures(
            settings, applicationBundleIdentifier: context, at: moment)
        let onRefresh = MenuBarFeatures(
            settings, applicationBundleIdentifier: context, at: moment)

        #expect(!onMenuOpen.suggestions)
        #expect(!onRefresh.suggestions)
    }
}
