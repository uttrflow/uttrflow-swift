import Foundation
import Testing
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

@MainActor
@Suite("Suggestion capture routing")
struct SuggestionCaptureRoutingTests {
    @Test("A same-app field switch completes the old line and leaves the new field empty")
    func sameApplicationFieldSwitchRoutesPendingSuffixToPreviousField() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello wor", selection: NSRange(location: 9, length: 0))
        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "", selection: NSRange(location: 0, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        let secondReading = SuggestionMoment.reading(of: second)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)

        await coordinator.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        await coordinator.rememberAfterReadsDrained(
            second, as: secondReading, because: .tick, at: moment.addingTimeInterval(1),
            leaving: firstReading, typed: ["l", "d"])

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10) == ["hello world"])
        #expect(try await store.recent(in: try #require(secondReading.surface), limit: 10).isEmpty)
    }
}
