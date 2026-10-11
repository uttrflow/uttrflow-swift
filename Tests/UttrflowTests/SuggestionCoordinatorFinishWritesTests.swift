// Tests that a quit cannot lose a suggestion accepted just before it.

import Foundation
import Synchronization
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("SuggestionCoordinator.finishWrites")
struct SuggestionCoordinatorFinishWritesTests {
    @Test("update activity stays busy through suggestion typing quiet time")
    func updateActivityTracksSuggestionTicker() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "sc-update-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldReader: { nil }, frontmostBundleIdentifier: { "com.example.editor" })
        #expect(!coordinator.isActiveForUpdate)
        coordinator.noteActivity()
        #expect(coordinator.isActiveForUpdate)
        coordinator.stop()
        #expect(!coordinator.isActiveForUpdate)
    }

    @Test("finishWrites waits for an in-flight acceptance to record before returning")
    func waitsForInFlightAcceptance() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "sc-finishwrites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))

        let recorded = Mutex(false)
        coordinator.acceptances.enqueue {
            try? await Task.sleep(for: .milliseconds(80))
            recorded.withLock { $0 = true }
        }

        await coordinator.finishWrites()
        #expect(recorded.withLock { $0 }, "finishWrites returned before the acceptance recorded")
    }
}
