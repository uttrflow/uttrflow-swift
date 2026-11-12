import Foundation
import Testing
import UttrflowTestSupport
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

@MainActor
@Suite("Suggestion settings keep learning consent in sync", .serialized, .timeLimit(.minutes(1)))
struct SuggestionConsentTests {
    @Test("removing a left-alone application restores learning consent", .bug(id: 5741))
    func removingALeftAloneApplicationRestoresLearningConsent() async throws {
        let bundleIdentifier = "com.example.notes"
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-consent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let consentFile = CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false))
        var declined = CapturePreferences()
        declined.record(.declined, for: bundleIdentifier)
        try consentFile.save(declined)

        let before = SuggestionPreferences(isEnabled: true, turnedOff: [bundleIdentifier])
        let coordinator = try await SuggestionCoordinator(container: container, preferences: before)
        defer { coordinator.stop() }

        var after = before
        after.removePreferences(for: bundleIdentifier)
        #expect(after.state(of: bundleIdentifier) == .on)

        coordinator.follow(after)
        try await eventually { await coordinator.capture.decisions().state(of: bundleIdentifier) == .allowed }

        #expect(await coordinator.capture.decisions().state(of: bundleIdentifier) == .allowed)
        #expect(consentFile.load().state(of: bundleIdentifier) == .allowed)
    }
}
