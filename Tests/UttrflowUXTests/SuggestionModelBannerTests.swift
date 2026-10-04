// A switch that is on and silent has to say why, or it is indistinguishable from a broken feature.

import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import UttrflowUX

@Suite("What the Suggestions screen says about model readiness and tap startup")
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

    private func bannerForRuntime(_ runtime: SuggestionRuntimeStatus) -> SettingsBanner? {
        var capabilities = capabilities(.ready)
        capabilities.suggestionRuntime = runtime
        return SettingsPresenter.suggestionModelBanner(settings(suggesting: true), capabilities)
    }

    @Test("a ready model says nothing, because there is nothing to explain")
    func readySaysNothing() {
        #expect(bannerFor(.ready) == nil)
    }

    @Test("a failed tap names the cause and permission fix with a ready model")
    func tapFailureWhileReady() throws {
        let shown = try #require(bannerForRuntime(.tapFailed))
        #expect(shown.title.contains("could not start"))
        #expect(shown.message.contains("Privacy & Security"))
    }

    @Test("a failed corpus names the cause and recovery with a ready model")
    func corpusFailureWhileReady() throws {
        let shown = try #require(bannerForRuntime(.corpusFailed))
        #expect(shown.title.contains("could not start"))
        #expect(shown.message.contains("corpus"))
        #expect(shown.message.contains("file access"))
    }

    @Test("tap setup in progress says suggestions are paused briefly")
    func tapStarting() throws {
        let shown = try #require(bannerForRuntime(.starting))
        #expect(shown.title == "Suggestions are paused briefly")
        #expect(shown.message.contains("resume automatically"))
    }

    @Test("a long tap rest keeps Settings informed")
    func tapResting() throws {
        let shown = try #require(bannerForRuntime(.tapResting))
        #expect(shown.title == "Suggestions are paused briefly")
        #expect(shown.message.contains("resume automatically"))
    }

    @Test("secure input does not report suggestions running with a ready model")
    func secureInputIsReported() throws {
        let shown = try #require(bannerForRuntime(.secureInputBlocked))
        #expect(shown.title == "Suggestions are paused")
        #expect(shown.message.contains("secure input"))
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

    @Test("a model set aside for memory says so, and says it comes back by itself")
    func releasedForMemorySaysSo() throws {
        let shown = try #require(bannerFor(.releasedForMemory))
        #expect(shown.title == "Paused to free memory")
        #expect(shown.message.contains("come back on their own"))
        #expect(bannerFor(.releasedForMemory, suggesting: false) == nil)
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
        #expect(shown.message.contains("try again"))
        let pane = SettingsPresenter.window(
            showing: .suggestions, settings: settings(suggesting: true),
            capabilities: capabilities(.failed)
        ).pane
        let retry = pane.groups.flatMap(\.rows).first { $0.id == "retrySuggestionModel" }
        #expect(retry?.control == .action(title: "Retry", change: .retrySuggestionModel))
        #expect(SettingsChange.retrySuggestionModel.isRequestToAct)
    }
}
