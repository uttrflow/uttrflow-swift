import Synchronization
import Testing

import UttrflowCore

/// How long the losing work sleeps: far past any allowance, so the race returning before it finishes is the whole point.
private let lateBySeconds = 30

@Suite("Holding a read to a time")
struct DeadlineTests {
    @Test("An answer that arrives in time is the answer.")
    func promptAnswersAreKept() async {
        let clock = PatientClock()
        let answer = await withDeadline(.milliseconds(500), clock: clock) { "here" }
        #expect(answer == "here")
        #expect(clock.ranOut == false, "the answer was waited out rather than taken")
    }

    @Test("An answer that does not arrive in time is nothing, and the race did not wait for it.")
    func lateAnswersAreNothing() async {
        let witness = Witness()
        let answer: String? = await withDeadline(.milliseconds(50)) {
            // Cancelled at the allowance, the sleep ends at once, and work that minds its cancellation stops here.
            try? await Task.sleep(for: .seconds(lateBySeconds))
            guard !Task.isCancelled else { return nil }
            await witness.finished()
            return "late"
        }
        #expect(answer == nil)
        #expect(await witness.didFinish == false)
    }

    @Test("Work that answers nothing is nothing, promptly.")
    func nothingIsNothing() async {
        let clock = PatientClock()
        let answer: String? = await withDeadline(.milliseconds(500), clock: clock) { nil }
        #expect(answer == nil)
        #expect(clock.ranOut == false, "nothing was waited out rather than taken")
    }

    @Test("An answer that takes a while but arrives inside the allowance is still the answer.")
    func slowButTimelyAnswersAreKept() async {
        let clock = PatientClock()
        let answer = await withDeadline(.milliseconds(800), clock: clock) {
            try? await Task.sleep(for: .milliseconds(20))
            return "here"
        }
        #expect(answer == "here")
        #expect(clock.ranOut == false, "the answer was waited out rather than taken")
    }

    @Test(
        "The race is over when the allowance is, however long the work would take: the loser has not finished when the caller has its answer.",
        arguments: [1, 10, 40, 80])
    func theRaceEndsOnTime(allowance: Int) async {
        let witness = Witness()
        let answer: String? = await withDeadline(.milliseconds(allowance)) {
            try? await Task.sleep(for: .seconds(lateBySeconds))
            guard !Task.isCancelled else { return nil }
            await witness.finished()
            return "late"
        }
        #expect(answer == nil)
        // Judged by the loser's own state rather than a clock, since a loaded test run has been seen to stall the process for ten seconds.
        #expect(await witness.didFinish == false)
    }

    @Test("Work that cannot be stopped is left to finish on its own rather than waited for.")
    func unstoppableWorkIsLeftBehind() async {
        let witness = Witness()
        let answer: String? = await withDeadline(.milliseconds(40)) {
            // A read on another queue answers when it answers; cancelling the waiting task does not hurry it.
            await withCheckedContinuation { continuation in
                Task.detached {
                    try? await Task.sleep(for: .seconds(lateBySeconds))
                    await witness.finished()
                    continuation.resume(returning: "late")
                }
            }
        }
        #expect(answer == nil)
        #expect(await witness.didFinish == false)
    }

    @Test(
        "The loser is cancelled: its sleep is cut short, it finds itself cancelled, and what follows the check never runs."
    )
    func theLoserIsCancelled() async {
        let witness = Witness()
        let answer: String? = await withDeadline(.milliseconds(30)) {
            try? await Task.sleep(for: .seconds(lateBySeconds))
            await witness.woke(cancelled: Task.isCancelled)
            guard !Task.isCancelled else { return nil }
            await witness.finished()
            return "late"
        }
        #expect(answer == nil)
        #expect(await witness.wakes() == true)
        #expect(await witness.didFinish == false)
    }
}

/// What the losing work saw when it woke and whether it ever finished, reported from outside the race.
private actor Witness {
    var cancelledWhenWoken: Bool?
    var didFinish = false
    private var waitingToWake: [CheckedContinuation<Bool, Never>] = []

    func woke(cancelled: Bool) {
        cancelledWhenWoken = cancelled
        for waiting in waitingToWake { waiting.resume(returning: cancelled) }
        waitingToWake = []
    }

    func finished() { didFinish = true }

    /// Suspends until the losing work wakes, and answers whether it found itself cancelled.
    func wakes() async -> Bool {
        if let cancelledWhenWoken { return cancelledWhenWoken }
        return await withCheckedContinuation { waitingToWake.append($0) }
    }
}

/// A clock for the in-time cases: its sleeps end only when cancelled, or at a real ceiling it then reports reaching.
private final class PatientClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant

    /// Far past any answer in these tests, so reaching it means the race waited instead of taking the answer.
    private static let ceiling = Duration.seconds(30)
    private let reachedCeiling = Mutex(false)

    var now: Instant { .now }
    var minimumResolution: Duration { .nanoseconds(1) }

    /// Whether any sleep ran to the ceiling rather than being cancelled.
    var ranOut: Bool { reachedCeiling.withLock { $0 } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await Task.sleep(for: Self.ceiling)
        reachedCeiling.withLock { $0 = true }
    }
}
