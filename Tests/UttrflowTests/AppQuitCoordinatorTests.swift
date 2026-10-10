import Synchronization
import Testing

@testable import Uttrflow
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("AppQuitCoordinator", .timeLimit(.minutes(1)))
struct AppQuitCoordinatorTests {
    @Test("reply is sent when finishing a recording overruns the quit budget", .timeLimit(.minutes(1)))
    func replyWhenFinishRecordingOverrunsBudget() async throws {
        let clock = ManualClock()
        let finishStarted = Mutex(false)
        let finishCancelled = Mutex(false)
        let replied = Mutex(false)

        let running = Task {
            await AppQuitCoordinator.finish(
                budget: .seconds(15),
                clock: clock,
                pipeline: AppQuitCoordinator.Pipeline(
                    currentState: { .recording },
                    finishRecording: {
                        finishStarted.withLock { $0 = true }
                        await withTaskCancellationHandler {
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(3600))
                            }
                        } onCancel: {
                            finishCancelled.withLock { $0 = true }
                        }
                    },
                    states: { AsyncStream { _ in } }),
                catchUpClipboard: {},
                flushClipboard: {},
                finishCompletions: {},
                stopController: {},
                reply: { replied.withLock { $0 = true } })
        }

        try await eventually { finishStarted.withLock { $0 } }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(15))
        await running.value

        try await eventually { finishCancelled.withLock { $0 } }
        #expect(replied.withLock { $0 })
    }

    @Test("completed recording is kept before replying", .timeLimit(.minutes(1)))
    func completedRecordingIsKeptBeforeReplying() async {
        let clock = ManualClock()
        let events = Mutex([String]())
        let states = AsyncStream<DictationState> { continuation in
            continuation.yield(.recording)
            continuation.yield(
                .inserted(
                    DictationOutcome(
                        text: "hello", method: .clipboard, cleanedBy: .rules)))
            continuation.finish()
        }

        await AppQuitCoordinator.finish(
            budget: .seconds(15),
            clock: clock,
            pipeline: AppQuitCoordinator.Pipeline(
                currentState: { .recording },
                finishRecording: { events.withLock { $0.append("finish") } },
                states: { states }),
            catchUpClipboard: {},
            flushClipboard: { events.withLock { $0.append("flush") } },
            finishCompletions: { events.withLock { $0.append("completions") } },
            stopController: { events.withLock { $0.append("stop") } },
            reply: { events.withLock { $0.append("reply") } })

        #expect(events.withLock { $0 } == ["flush", "completions", "finish", "stop", "reply"])
    }

    @Test("a copy made just before quitting is taken before flushing", .timeLimit(.minutes(1)))
    func lastCopyIsTakenBeforeFlushing() async {
        let events = Mutex([String]())

        await AppQuitCoordinator.finish(
            budget: .seconds(15),
            clock: ManualClock(),
            pipeline: nil,
            catchUpClipboard: { events.withLock { $0.append("catch up") } },
            flushClipboard: { events.withLock { $0.append("flush") } },
            finishCompletions: {},
            stopController: {},
            reply: { events.withLock { $0.append("reply") } })

        #expect(events.withLock { $0 } == ["catch up", "flush", "reply"])
    }
}
