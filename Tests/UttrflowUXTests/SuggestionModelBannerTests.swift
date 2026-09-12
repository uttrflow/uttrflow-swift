// A switch that is on and silent has to say why, or it is indistinguishable from a broken feature.

import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import UttrflowUX

@Suite("What the Suggestions screen says while the model is not ready")
struct SuggestionModelBannerTests {
    /// Settings with tab-to-complete in one state and nothing else said.
    private func settings(suggesting: Bool) -> Settings {
        Settings(suggestions: SuggestionPreferences(isEnabled: suggesting))
    }

    /// The capabilities of a Mac whose model is at one point in its arrival.
    private func capabilities(_ readiness: SuggestionModelReadiness) -> SettingsCapabilities {
        var capabilities = SettingsCapabilities.everything
        capabilities.suggestionModel = readiness
        return capabilities
    }

    private func bannerFor(
        _ readiness: SuggestionModelReadiness, suggesting: Bool = true
    ) -> SettingsBanner? {
        SettingsPresenter.suggestionModelBanner(
            settings(suggesting: suggesting), capabilities(readiness))
    }

    @Test("a ready model says nothing, because there is nothing to explain")
    func readySaysNothing() {
        #expect(bannerFor(.ready) == nil)
    }

    @Test("nor does a Mac that never asked for the feature")
    func neverAskedSaysNothing() {
        #expect(bannerFor(.notAsked) == nil)
        #expect(bannerFor(.downloading(fractionCompleted: 0.4), suggesting: false) == nil)
    }

    @Test("a download says so, and says how big it is before it is over")
    func downloadingSaysSo() throws {
        let shown = try #require(bannerFor(.downloading(fractionCompleted: nil)))
        #expect(shown.title == "Getting ready")
        #expect(shown.message.contains("3 GB"))
    }

    @Test("and carries the percentage once there is one to carry")
    func downloadingCarriesProgress() throws {
        #expect(try #require(bannerFor(.downloading(fractionCompleted: 0.4))).title.contains("40%"))
        #expect(try #require(bannerFor(.downloading(fractionCompleted: 0.075))).title.contains("8%"))
    }

    @Test("loading is its own state, since it happens on every launch and no bytes move")
    func loadingSaysSo() throws {
        let shown = try #require(bannerFor(.loading))
        #expect(shown.title == "Getting ready")
        #expect(shown.message.contains("once per launch"))
    }

    @Test("a failure is shown rather than swallowed, and says what to do about it")
    func failureIsShown() throws {
        let shown = try #require(bannerFor(.failed))
        #expect(shown.title.contains("could not"))
        #expect(shown.message.contains("off and on"))
    }
}
