import Foundation
import UttrflowCore
import UttrflowPipeline

/// Coordinates the work that must happen after macOS asks the app to quit.
enum AppQuitCoordinator {
    struct Pipeline: Sendable {
        var currentState: @Sendable () async -> DictationState
        var finishRecording: @Sendable () async -> Void
        var states: @Sendable () async -> AsyncStream<DictationState>
    }

    static func finish(
        budget: Duration,
        clock: any Clock<Duration>,
        pipeline: Pipeline?,
        catchUpClipboard: @escaping @Sendable () async -> Void,
        flushClipboard: @escaping @Sendable () async -> Void,
        finishCompletions: @escaping @Sendable () async -> Void,
        stopController: @escaping @Sendable () async -> Void,
        reply: @escaping @Sendable () async -> Void
    ) async {
        _ = try? await withStageTimeout(budget, clock: clock) {
            // A copy since the last poll is lost for good otherwise: the next launch starts past it.
            await catchUpClipboard()
            await flushClipboard()
            await finishCompletions()
            if let pipeline, await pipeline.currentState().isListening {
                await pipeline.finishRecording()
            }
            if let pipeline {
                for await state in await pipeline.states() where !state.isBusy { break }
            }
            await stopController()
        }
        await reply()
    }
}
