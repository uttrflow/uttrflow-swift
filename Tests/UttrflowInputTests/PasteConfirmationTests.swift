import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
import UttrflowTestSupport

/// A caret that answers nothing until the application has been asked a given number of times.
private final class SlowFocus: AccessibilityFocus, @unchecked Sendable {
    private let answer: String?
    private let readsBeforeItLands: Int
    private let readCost: Duration
    private let charging: ManualClock?
    private let reads = Mutex(0)

    /// `answer` is what the field holds once it has taken the paste; `nil` is a field that never says.
    init(
        answer: String?,
        readsBeforeItLands: Int = 0,
        costing readCost: Duration = .zero,
        on charging: ManualClock? = nil
    ) {
        self.answer = answer
        self.readsBeforeItLands = readsBeforeItLands
        self.readCost = readCost
        self.charging = charging
    }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }

    /// The real exact-count rule: a field holding fewer than `count` characters answers nothing at all.
    func precedingText(_ count: Int) -> String? {
        guard case .text(let seen) = tail(upTo: count), seen.count >= count else { return nil }
        return seen
    }

    func tail(upTo count: Int) -> FieldTail {
        guard let answer else { return .unreadable }
        let read = reads.withLock { reads -> Int in
            reads += 1
            return reads
        }
        charging?.advance(by: readCost)
        // As short as the field is: the point of #223 is that a short field is still readable.
        return .text(read > readsBeforeItLands ? answer : "what was already there")
    }

    var readCount: Int { reads.withLock { $0 } }
}

@Suite("PasteConfirmation")
struct PasteConfirmationTests {
    private let interval = Duration.milliseconds(1)
    private let budget = Duration.milliseconds(10)

    private func confirming(
        _ focus: any AccessibilityFocus, on clock: ManualClock = ManualClock(advancesWhenSlept: true)
    ) -> PasteConfirmation {
        PasteConfirmation(focus: focus, clock: clock, budget: budget, interval: interval)
    }

    /// #223: a search box or a chat line holds less than the 96 asked for, and was reported unverifiable.
    @Test("confirms a paste into a field shorter than the read length")
    func confirmsAShortField() async {
        let focus = SlowFocus(answer: "ok")

        let outcome = await confirming(focus).waitFor("ok")

        #expect(outcome == .landed(.milliseconds(1)))
    }

    /// The Electron case, which is most of them: waiting on a field that never answers proves nothing.
    @Test("says nothing was proved when the field will not report what it holds")
    func unreadableField() async {
        let focus = SlowFocus(answer: nil)

        #expect(await confirming(focus).waitFor("dictated words") == .notReported)
        #expect(focus.readCount == 0, "a field that will not answer must not be polled")
    }

    @Test("reports how long the application took to take the paste")
    func landsAfterAWhile() async {
        let focus = SlowFocus(answer: "and then dictated words", readsBeforeItLands: 3)

        let outcome = await confirming(focus).waitFor("dictated words")

        #expect(outcome == .landed(.milliseconds(3)))
    }

    /// A paste that never arrives must end the wait rather than hold the dictation open.
    @Test("gives up once the budget is spent")
    func givesUp() async {
        let outcome = await confirming(SlowFocus(answer: "nothing like it")).waitFor("dictated words")

        #expect(outcome == .gaveUp(.milliseconds(10)))
    }

    /// A field that rewraps what it was given still holds the same words.
    @Test("matches through the whitespace an application adds on the way in")
    func collapsesWhitespace() async {
        let focus = SlowFocus(answer: "before:\n\n  two   lines  of it")

        #expect(await confirming(focus).waitFor("two lines\nof it") == .landed(.milliseconds(1)))
    }

    /// Otherwise the previous dictation, still sitting at the caret, would confirm this one.
    @Test("is not satisfied by different words already at the caret")
    func refusesTheWrongWords() async {
        let focus = SlowFocus(answer: "the dictation before this one")

        #expect(await confirming(focus).waitFor("dictated words") == .gaveUp(.milliseconds(10)))
    }

    /// Longer than the tail compared, so the match is of the end rather than the whole.
    @Test("confirms a long dictation by the end of it, which is what sits against the caret")
    func matchesTheTailOfSomethingLong() async {
        let spoken = String(repeating: "a sentence that keeps going. ", count: 20)
        let focus = SlowFocus(answer: "context before it " + spoken)

        #expect(await confirming(focus).waitFor(spoken) == .landed(.milliseconds(1)))
    }

    @Test("proves nothing about an empty transcript rather than claiming it landed")
    func emptyText() async {
        #expect(await confirming(SlowFocus(answer: "anything")).waitFor("") == .notReported)
    }

    /// #1308: an ignored paste must not be reported as landed just because the old caret text already matched.
    @Test("does not confirm a caret unchanged since before the paste, even when it already matched")
    func refusesAnUnchangedPreExistingMatch() async {
        let focus = SlowFocus(answer: "dictated words")

        let outcome = await confirming(focus).waitFor("dictated words", before: .text("dictated words"))

        #expect(outcome == .gaveUp(.milliseconds(10)))
        #expect(InsertionArrival(outcome) == .unconfirmed)
    }

    /// An unreadable pre-paste caret cannot establish whether identical words were already present.
    @Test("does not confirm an identical match after an unreadable pre-paste read")
    func unreadableBeforeDoesNotConfirmAnIdenticalExistingMatch() async {
        let focus = SlowFocus(answer: "dictated words")

        let outcome = await confirming(focus).waitFor("dictated words", before: .unreadable)

        #expect(outcome == .gaveUp(.milliseconds(10)))
        #expect(InsertionArrival(outcome) == .unconfirmed)
    }

    /// A caret that changes after the paste, even to the same words, is genuine evidence it landed.
    @Test("confirms once the caret changes, even when it settles back on words seen before the paste")
    func confirmsOnceTheCaretActuallyChanges() async {
        let focus = SlowFocus(answer: "dictated words", readsBeforeItLands: 2)

        let outcome = await confirming(focus).waitFor("dictated words", before: .text("dictated words"))

        #expect(outcome == .landed(.milliseconds(2)))
    }

    /// A `before` reading that did not already match must not stop an ordinary paste from confirming.
    @Test("confirms normally when the words were not already at the caret before the paste")
    func beforeThatDidNotMatchStillConfirms() async {
        let focus = SlowFocus(answer: "dictated words")

        let outcome = await confirming(focus).waitFor("dictated words", before: .text("something else"))

        #expect(outcome == .landed(.milliseconds(1)))
    }

    /// #213: the shipped budget and interval, against a read that costs more than the sleep before it.
    private func inALargeDocument(
        _ answer: String, landingAfter readsBeforeItLands: Int = 0
    ) -> (PasteConfirmation, ManualClock) {
        let clock = ManualClock(advancesWhenSlept: true)
        let focus = SlowFocus(
            answer: answer, readsBeforeItLands: readsBeforeItLands,
            costing: .milliseconds(100), on: clock)
        return (
            PasteConfirmation(
                focus: focus, clock: clock, budget: PasteConfirmation.budget,
                interval: PasteConfirmation.interval),
            clock
        )
    }

    /// #213: a budget tallied from the sleeps charges nothing for the whole-field read between them.
    @Test("spends the budget on elapsed time rather than on a count of sleeps")
    func chargesTheReadsToTheBudget() async {
        let (confirmation, clock) = inALargeDocument("nothing like it")

        let outcome = await confirmation.waitFor("dictated words")

        #expect(outcome == .gaveUp(.milliseconds(1640)))
        #expect(clock.now.offset == .milliseconds(1640), "the dictation is busy for every one of these")
    }

    /// #213: the figure handed to the log is the wait the user sat through, reads included.
    @Test("reports the whole wait, not only the part of it spent sleeping")
    func reportsElapsedTimeWhenItLands() async {
        let (confirmation, _) = inALargeDocument("and then dictated words", landingAfter: 3)

        #expect(await confirmation.waitFor("dictated words") == .landed(.milliseconds(520)))
    }
}

/// A clock whose sleep lasts until its task is cancelled, then throws, time moving to its deadline.
private final class CancellableClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant

    private struct State {
        var waiting: CheckedContinuation<Void, any Error>?
        var cancelled = false
        var offset = Duration.zero
    }

    private let state = Mutex(State())
    /// Yields each time a sleep begins, which is when a test may cancel.
    let sleeps: AsyncStream<Void>
    private let started: AsyncStream<Void>.Continuation

    init() {
        (sleeps, started) = AsyncStream.makeStream()
    }

    var now: Instant { Instant(offset: state.withLock { $0.offset }) }
    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        defer { state.withLock { $0.offset = max($0.offset, deadline.offset) } }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                let cancelled = state.withLock { state -> Bool in
                    if !state.cancelled { state.waiting = continuation }
                    return state.cancelled
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
                started.yield()
            }
        } onCancel: {
            let waiting = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                state.cancelled = true
                defer { state.waiting = nil }
                return state.waiting
            }
            waiting?.resume(throwing: CancellationError())
        }
    }
}

/// A field that never takes the paste and cancels the task reading it on the given read.
private final class CancellingFocus: AccessibilityFocus, @unchecked Sendable {
    private let reads = Mutex(0)
    private let cancelOn: Int
    /// Cancels the waiting task, which a read on the Accessibility queue cannot reach as its current task.
    let canceller = Mutex<(@Sendable () -> Void)?>(nil)

    init(cancelOn: Int) { self.cancelOn = cancelOn }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func precedingText(_ count: Int) -> String? { nil }

    func tail(upTo count: Int) -> FieldTail {
        let read = reads.withLock { reads -> Int in
            reads += 1
            return reads
        }
        if read == cancelOn { canceller.withLock { $0 }?() }
        return .text("what was already there")
    }

    var readCount: Int { reads.withLock { $0 } }
}

@Suite("PasteConfirmation, cancelled")
struct PasteConfirmationCancellationTests {
    @Test("a task cancelled before it starts reads nothing")
    func cancelledOnEntry() async {
        let focus = CancellingFocus(cancelOn: 0)
        let confirmation = PasteConfirmation(focus: focus, clock: CancellableClock())
        let task = Task { () -> PasteConfirmation.Outcome in
            while !Task.isCancelled { await Task.yield() }
            return await confirmation.waitFor("dictated words")
        }
        task.cancel()

        #expect(await task.value == .cancelled(.zero))
        #expect(focus.readCount == 0)
    }

    @Test("cancelling during the wait between reads stops it without another read")
    func cancelledWhileSleeping() async {
        let focus = CancellingFocus(cancelOn: 0)
        let clock = CancellableClock()
        let confirmation = PasteConfirmation(focus: focus, clock: clock)
        let task = Task { await confirmation.waitFor("dictated words") }
        for await _ in clock.sleeps { break }
        task.cancel()

        #expect(await task.value == .cancelled(PasteConfirmation.interval))
        #expect(focus.readCount == 1, "only the read before the first wait")
    }

    @Test("a clock that does not throw on cancellation still stops the reads")
    func cancelledWithAQuietClock() async {
        let focus = CancellingFocus(cancelOn: 2)
        let clock = ManualClock(advancesWhenSlept: true)
        let confirmation = PasteConfirmation(focus: focus, clock: clock)
        let task = Task { () -> PasteConfirmation.Outcome in
            while focus.canceller.withLock({ $0 }) == nil { await Task.yield() }
            return await confirmation.waitFor("dictated words")
        }
        focus.canceller.withLock { $0 = { task.cancel() } }
        let outcome = await task.value

        guard case .cancelled = outcome else {
            Issue.record("expected a cancelled wait, got \(outcome)")
            return
        }
        #expect(focus.readCount == 2)
    }

    @Test("a cancelled wait is reported upwards as unconfirmed, never as confirmed")
    func cancelledIsUnconfirmed() {
        #expect(InsertionArrival(.cancelled(.milliseconds(40))) == .unconfirmed)
    }
}

/// A field that holds `field` once the write lands, read back the way the system reader cuts it: by characters before a UTF-16 caret.
private final class ClusterFieldFocus: AccessibilityFocus, @unchecked Sendable {
    private let field: String

    init(field: String) { self.field = field }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func precedingText(_ count: Int) -> String? {
        BackwardSelection.text(in: field, endingAt: field.utf16.count, exactly: count)
    }

    func tail(upTo count: Int) -> FieldTail {
        BackwardSelection.tail(in: field, endingAt: field.utf16.count, upTo: count).map(FieldTail.text)
            ?? .unreadable
    }
}

@Suite("PasteConfirmation, grapheme clusters at the end of a write")
struct PasteConfirmationClusterTests {
    private static let clusters = [
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F1EE}\u{1F1F3}", "e\u{301}\u{323}",
        "\u{915}\u{94D}\u{937}",
    ]

    private func waitFor(_ written: String, in field: String) async -> PasteConfirmation.Outcome {
        let confirmation = PasteConfirmation(
            focus: ClusterFieldFocus(field: field), clock: ManualClock(advancesWhenSlept: true),
            budget: .milliseconds(10), interval: .milliseconds(1))
        return await confirmation.waitFor(written, before: .text("before"))
    }

    @Test(
        "A write ending in a ZWJ emoji, flag, combining mark or conjunct is confirmed at the caret.",
        arguments: clusters)
    func confirmsAWriteEndingInACluster(cluster: String) async {
        let written = "dictated words " + cluster

        #expect(await waitFor(written, in: "already there " + written) == .landed(.milliseconds(1)))
    }

    @Test(
        "A write made only of clusters longer than the read in UTF-16 units is still confirmed.",
        arguments: clusters)
    func confirmsAClusterOnlyWrite(cluster: String) async {
        let written = String(repeating: cluster, count: PasteConfirmation.readLength + 4)

        #expect(written.utf16.count > PasteConfirmation.readLength * 2)
        #expect(await waitFor(written, in: written) == .landed(.milliseconds(1)))
    }

    @Test("A field that keeps only the base of the last cluster is not confirmed.")
    func refusesAFieldMissingTheEndOfTheLastCluster() async {
        let written = "dictated words e\u{301}\u{323}"

        #expect(await waitFor(written, in: "dictated words e") == .gaveUp(.milliseconds(10)))
    }

    @Test("A field that stores the precomposed form of a decomposed write is confirmed.")
    func confirmsACanonicallyEquivalentField() async {
        #expect(await waitFor("dictated cafe\u{301}", in: "dictated caf\u{E9}") == .landed(.milliseconds(1)))
    }
}
