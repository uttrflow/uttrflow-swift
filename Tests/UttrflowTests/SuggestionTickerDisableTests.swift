import Foundation
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("Disabled apps stop the suggestion ticker immediately")
struct SuggestionTickerDisableTests {
    private func makeCoordinator(
        preferences: SuggestionPreferences
    ) async throws -> (SuggestionCoordinator, URL) {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-ticker-disable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return (try await SuggestionCoordinator(container: container, preferences: preferences), container)
    }

    @Test("turning suggestions off withdraws and stops an already scheduled ticker")
    func disablingPreferencesStopsTicker() async throws {
        let (coordinator, container) = try await makeCoordinator(
            preferences: SuggestionPreferences(isEnabled: true))
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: container)
        }
        coordinator.scheduleTicker(every: 60)
        #expect(coordinator.isTickerScheduled)

        coordinator.follow(SuggestionPreferences(isEnabled: false))

        #expect(!coordinator.isTickerScheduled)
    }

    @Test("activating an app with suggestions turned off stops an already scheduled ticker")
    func activatingDisabledApplicationStopsTicker() async throws {
        let disabled = "com.example.disabled"
        let (coordinator, container) = try await makeCoordinator(
            preferences: SuggestionPreferences(isEnabled: true, turnedOff: [disabled]))
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: container)
        }
        coordinator.scheduleTicker(every: 60)
        #expect(coordinator.isTickerScheduled)

        coordinator.applicationChanged(front: disabled)

        #expect(!coordinator.isTickerScheduled)
    }
}
