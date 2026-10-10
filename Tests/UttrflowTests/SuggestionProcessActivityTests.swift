import Foundation
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
private final class RecordingSuggestionProcessActivity: SuggestionProcessActivityManaging {
    private(set) var events: [String] = []

    func begin() { events.append("begin") }
    func end() { events.append("end") }
}

@MainActor
@Suite("Suggestion process activity follows the coordinator lifecycle")
struct SuggestionProcessActivityTests {
    @Test("the latency activity begins with suggestions and ends when they stop")
    func activityFollowsStartAndStop() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-process-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let activity = RecordingSuggestionProcessActivity()
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            processActivity: activity)

        coordinator.start()
        #expect(activity.events == ["begin"])

        coordinator.stop()
        #expect(activity.events == ["begin", "end"])
    }
}
