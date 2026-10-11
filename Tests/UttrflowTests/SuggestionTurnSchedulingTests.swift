import Testing
import UttrflowPredict
import UttrflowTestSupport

@testable import Uttrflow

private actor HeldSleeps {
    private var waits: [CheckedContinuation<Void, Never>?] = []
    private(set) var delays: [Duration] = []

    func sleep(_ delay: Duration) async {
        await withCheckedContinuation { continuation in
            delays.append(delay)
            waits.append(continuation)
        }
    }

    func release(_ index: Int) {
        waits[index]?.resume()
        waits[index] = nil
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SuggestionTurnSchedulingTests {
    @TaskLocal private static var taskMarker: Int?

    @Test(arguments: [-1, 0, 19])
    func delayedWakeUsesTheExistingMinimum(_ milliseconds: Int) async throws {
        let sleeps = HeldSleeps()
        let owner = SuggestionTurnScheduling(sleep: { await sleeps.sleep($0) })
        var reasons: [SuggestionReason] = []
        owner.wake(.keystroke, afterMilliseconds: milliseconds) { reasons.append($0) }
        let task = try #require(owner.pendingWake)
        try await eventually { await sleeps.delays.count == 1 }
        #expect(await sleeps.delays == [.milliseconds(max(milliseconds, 1))])
        #expect(owner.hasPendingWake)
        await sleeps.release(0)
        await task.value
        #expect(reasons == [.keystroke])
        #expect(!owner.hasPendingWake)
    }

    @Test func replacementAndCancellationRejectReturnedSleeps() async throws {
        let sleeps = HeldSleeps()
        let owner = SuggestionTurnScheduling(sleep: { await sleeps.sleep($0) })
        var reasons: [SuggestionReason] = []
        owner.wake(.keystroke, afterMilliseconds: 20) { reasons.append($0) }
        let old = try #require(owner.pendingWake)
        try await eventually { await sleeps.delays.count == 1 }
        owner.wake(.returnPressed, afterMilliseconds: 40) { reasons.append($0) }
        let replacement = try #require(owner.pendingWake)
        try await eventually { await sleeps.delays.count == 2 }
        #expect(old.isCancelled)
        await sleeps.release(0)
        await old.value
        #expect(reasons.isEmpty)
        #expect(owner.hasPendingWake)
        await sleeps.release(1)
        await replacement.value
        #expect(reasons == [.returnPressed])
        owner.wake(.tick, afterMilliseconds: 30) { reasons.append($0) }
        let cancelled = try #require(owner.pendingWake)
        try await eventually { await sleeps.delays.count == 3 }
        owner.cancelPendingWake()
        await sleeps.release(2)
        await cancelled.value
        #expect(!owner.hasPendingWake)
        #expect(reasons == [.returnPressed])
    }

    @Test func releasingTheOwnerDoesNotWakeOrRetainIt() async throws {
        let sleeps = HeldSleeps()
        var owner: SuggestionTurnScheduling? = SuggestionTurnScheduling(sleep: { await sleeps.sleep($0) })
        weak let released = owner
        var reasons: [SuggestionReason] = []
        owner?.wake(.tick, afterMilliseconds: 10) { reasons.append($0) }
        let task = try #require(owner?.pendingWake)
        try await eventually { await sleeps.delays.count == 1 }
        owner = nil
        #expect(released == nil)
        await sleeps.release(0)
        await task.value
        #expect(reasons.isEmpty)
    }

    @Test func busyTurnsKeepTheMostUrgentWake() async throws {
        let sleeps = HeldSleeps()
        let owner = SuggestionTurnScheduling()
        let now = ContinuousClock.now
        var reasons: [SuggestionReason] = []
        let run: @MainActor (Int, SuggestionReason) async -> Void = { _, _ in await sleeps.sleep(.zero) }
        owner.wake(.keystroke, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        let task = try #require(owner.running)
        try await eventually { await sleeps.delays.count == 1 }
        for reason in [SuggestionReason.tick, .keystroke, .applicationChanged, .returnPressed, .tick] {
            owner.wake(reason, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        }
        #expect(owner.turns.admitted == 1)
        await sleeps.release(0)
        await task.value
        #expect(reasons == [.returnPressed])
        #expect(owner.runningTurn == nil)
        #expect(!owner.turns.isRunning)
    }

    @Test func aLatePredecessorLeavesItsSuccessorCancellableAndStopDiscardsItsWake() async throws {
        let sleeps = HeldSleeps()
        let owner = SuggestionTurnScheduling()
        let now = ContinuousClock.now
        let run: @MainActor (Int, SuggestionReason) async -> Void = { _, _ in await sleeps.sleep(.zero) }
        var reasons: [SuggestionReason] = []
        owner.wake(.tick, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        let old = try #require(owner.running)
        try await eventually { await sleeps.delays.count == 1 }
        var stalls = 0
        owner.wake(
            .applicationChanged, at: now.advanced(by: .seconds(TurnGate.stallSeconds)),
            stalled: {
                stalls += 1; #expect(!old.isCancelled)
            }, run: run,
            next: { reasons.append($0) })
        let replacement = try #require(owner.running)
        try await eventually { await sleeps.delays.count == 2 }
        #expect(stalls == 1)
        #expect(old.isCancelled)
        await sleeps.release(0)
        await old.value
        #expect(owner.runningTurn == 2)
        #expect(owner.turns.isCurrent(2))
        #expect(!replacement.isCancelled)
        owner.wake(.returnPressed, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        owner.state.stop()
        owner.turns.abandon()
        owner.runningTurn = nil
        owner.cancelRunning()
        await sleeps.release(1)
        await replacement.value
        #expect(replacement.isCancelled)
        #expect(reasons.isEmpty)
        #expect(!owner.turns.isRunning)
    }

    @Test func aRunningTaskDoesNotRetainItsOwnerOrWakeAfterRelease() async throws {
        let sleeps = HeldSleeps()
        var owner: SuggestionTurnScheduling? = SuggestionTurnScheduling()
        weak let released = owner
        var reasons: [SuggestionReason] = []
        let now = ContinuousClock.now
        let run: @MainActor (Int, SuggestionReason) async -> Void = { _, _ in await sleeps.sleep(.zero) }
        owner?.wake(.tick, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        let task = try #require(owner?.running)
        try await eventually { await sleeps.delays.count == 1 }
        owner?.wake(.returnPressed, at: now, stalled: {}, run: run, next: { reasons.append($0) })
        owner = nil
        #expect(released == nil)
        await sleeps.release(0)
        await task.value
        #expect(reasons.isEmpty)
    }

    @Test func theRunWrapperKeepsTaskLocalValuesAndCancellation() async throws {
        let sleeps = HeldSleeps()
        let owner = SuggestionTurnScheduling()
        try await Self.$taskMarker.withValue(17) {
            owner.wake(
                .tick, at: .now, stalled: {},
                run: { _, _ in
                    #expect(Self.taskMarker == 17)
                    await sleeps.sleep(.zero)
                    #expect(Self.taskMarker == 17)
                    #expect(Task.isCancelled)
                }, next: { _ in })
            let task = try #require(owner.running)
            try await eventually { await sleeps.delays.count == 1 }
            owner.cancelRunning()
            await sleeps.release(0)
            await task.value
        }
    }

    @Test func defaultSleepAndAnUnqueuedCompletionSettle() async throws {
        let owner = SuggestionTurnScheduling()
        var reasons: [SuggestionReason] = []
        owner.wake(.tick, afterMilliseconds: 1) { reasons.append($0) }
        let delayed = try #require(owner.pendingWake)
        await delayed.value
        #expect(reasons == [.tick])
        owner.wake(.tick, at: .now, stalled: {}, run: { _, _ in }, next: { reasons.append($0) })
        let running = try #require(owner.running)
        await running.value
        #expect(owner.runningTurn == nil)
        #expect(!owner.turns.isRunning)
        #expect(reasons == [.tick])
    }
}
