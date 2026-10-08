import Foundation
import Testing
import UttrflowPredict
import UttrflowTestSupport

@testable import Uttrflow

@MainActor
@Suite("Suggestion generation task ownership", .serialized)
struct SuggestionGeneratingTaskSlotTests {
    @Test("a late turn completion leaves the newer task cancellable")
    func lateCompletionPreservesNewerTask() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-generating-slot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }

        var turns = TurnGate()
        let start = Date()
        guard case .free(let stalledTurn) = turns.begin(at: start) else {
            Issue.record("The first turn should be admitted")
            return
        }
        let stalledTask = Task<[String], any Error> { [] }
        coordinator.generating.store(stalledTask, for: stalledTurn)

        guard case .stalled(let liveTurn) = turns.begin(at: start.addingTimeInterval(TurnGate.stallSeconds))
        else {
            Issue.record("A turn after the stall limit should replace the stalled turn")
            return
        }
        let cancelled = Signal()
        let liveTask = Task<[String], any Error> {
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(60))
                return []
            } onCancel: {
                cancelled.fire()
            }
        }
        coordinator.generating.store(liveTask, for: liveTurn)

        _ = await stalledTask.result
        coordinator.generating.finish(turn: stalledTurn)
        #expect(coordinator.generating.turn == liveTurn)

        coordinator.stop()
        try await arrival(of: cancelled.fired)
        _ = await liveTask.result
    }
}
