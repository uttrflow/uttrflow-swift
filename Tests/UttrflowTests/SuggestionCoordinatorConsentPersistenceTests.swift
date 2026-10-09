import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

@MainActor
@Suite("SuggestionCoordinator.consentPersistence")
struct SuggestionCoordinatorConsentPersistenceTests {
    @Test("a failed consent save is reported and keeps the refusal in memory")
    func reportsConsentSaveFailure() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "sc-consent-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        let consentPath = CapturePreferencesFile.defaultFile(in: container)
        try FileManager.default.createDirectory(at: consentPath, withIntermediateDirectories: true)

        let reported = await withCheckedContinuation { continuation in
            coordinator.onConsentPersistenceFailure = { error in
                continuation.resume(returning: SuggestionLog.failure(error))
            }
            coordinator.follow(
                SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.editor"]))
        }

        #expect(!reported.isEmpty)
        #expect(await coordinator.capture.decisions().state(of: "com.example.editor") == .declined)
    }
}
