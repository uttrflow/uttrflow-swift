import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A clock a test moves itself: sleeping on it costs no real time, so nothing here races CI for a core.
final class ScriptedClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let offset = Mutex(Duration.zero)

    var now: Instant { Instant(offset: elapsed) }
    var minimumResolution: Duration { .nanoseconds(1) }

    /// How far the clock has been moved, which is what a wall clock would have shown.
    var elapsed: Duration { offset.withLock { $0 } }

    /// Moves the clock on by hand, which is how a read charges the test for what it cost.
    func advance(by duration: Duration) { offset.withLock { $0 += duration } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        offset.withLock { $0 = max($0, deadline.offset) }
        await Task.yield()
    }
}

/// A caret that answers nothing until the application has been asked a given number of times.
private final class SlowFocus: AccessibilityFocus, @unchecked Sendable {
    private let answer: String?
    private let readsBeforeItLands: Int
    private let readCost: Duration
    private let charging: ScriptedClock?
    private let reads = Mutex(0)

    /// `answer` is what the field holds once it has taken the paste; `nil` is a field that never says.
    init(
        answer: String?,
        readsBeforeItLands: Int = 0,
        costing readCost: Duration = .zero,
        on charging: ScriptedClock? = nil
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
        _ focus: any AccessibilityFocus, on clock: ScriptedClock = ScriptedClock()
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

    /// #213: the shipped budget and interval, against a read that costs more than the sleep before it.
    private func inALargeDocument(
        _ answer: String, landingAfter readsBeforeItLands: Int = 0
    ) -> (PasteConfirmation, ScriptedClock) {
        let clock = ScriptedClock()
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
        #expect(clock.elapsed == .milliseconds(1640), "the dictation is busy for every one of these")
    }

    /// #213: the figure handed to the log is the wait the user sat through, reads included.
    @Test("reports the whole wait, not only the part of it spent sleeping")
    func reportsElapsedTimeWhenItLands() async {
        let (confirmation, _) = inALargeDocument("and then dictated words", landingAfter: 3)

        #expect(await confirmation.waitFor("dictated words") == .landed(.milliseconds(520)))
    }
}
