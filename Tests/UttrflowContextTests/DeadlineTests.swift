import Testing

@testable import UttrflowContext

/// How long the losing work sleeps: far past any allowance, so the race returning before it finishes is the whole point.
private let lateBySeconds = 30

@Suite("Holding a read to a time")
struct DeadlineTests {
    @Test("An answer that arrives in time is the answer.")
    func promptAnswersAreKept() async {
        let answer = await Deadline.first(withinMilliseconds: 500) { "here" }
        #expect(answer == "here")
    }

    @Test("An answer that does not arrive in time is nothing, and the race did not wait for it.")
    func lateAnswersAreNothing() async {
        let witness = Witness()
        let answer: String? = await Deadline.first(withinMilliseconds: 50) {
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
        let answer: String? = await Deadline.first(withinMilliseconds: 500) { nil }
        #expect(answer == nil)
    }

    @Test("An answer that takes a while but arrives inside the allowance is still the answer.")
    func slowButTimelyAnswersAreKept() async {
        let answer = await Deadline.first(withinMilliseconds: 800) {
            try? await Task.sleep(for: .milliseconds(20))
            return "here"
        }
        #expect(answer == "here")
    }

    @Test(
        "The race is over when the allowance is, however long the work would take: the loser has not finished when the caller has its answer.",
        arguments: [1, 10, 40, 80])
    func theRaceEndsOnTime(allowance: Int) async {
        let witness = Witness()
        let answer: String? = await Deadline.first(withinMilliseconds: allowance) {
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
        let answer: String? = await Deadline.first(withinMilliseconds: 40) {
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
        let answer: String? = await Deadline.first(withinMilliseconds: 30) {
            try? await Task.sleep(for: .seconds(lateBySeconds))
            await witness.woke(cancelled: Task.isCancelled)
            guard !Task.isCancelled else { return nil }
            await witness.finished()
            return "late"
        }
        #expect(answer == nil)
        var woke: Bool?
        for _ in 0..<200 where woke == nil {
            woke = await witness.cancelledWhenWoken
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(woke == true)
        #expect(await witness.didFinish == false)
    }
}

/// What the losing work saw when it woke and whether it ever finished, reported from outside the race.
private actor Witness {
    var cancelledWhenWoken: Bool?
    var didFinish = false

    func woke(cancelled: Bool) { cancelledWhenWoken = cancelled }
    func finished() { didFinish = true }
}
