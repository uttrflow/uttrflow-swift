import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A caret that answers nothing until the application has been asked a given number of times.
private final class SlowFocus: AccessibilityFocus, @unchecked Sendable {
    private let answer: String?
    private let readsBeforeItLands: Int
    private let reads = Mutex(0)

    /// `answer` is what the field holds once it has taken the paste; `nil` is a field that never says.
    init(answer: String?, readsBeforeItLands: Int = 0) {
        self.answer = answer
        self.readsBeforeItLands = readsBeforeItLands
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
        // As short as the field is: the point of #223 is that a short field is still readable.
        return .text(read > readsBeforeItLands ? answer : "what was already there")
    }

    var readCount: Int { reads.withLock { $0 } }
}

@Suite("PasteConfirmation")
struct PasteConfirmationTests {
    private let interval = Duration.milliseconds(1)
    private let budget = Duration.milliseconds(10)

    private func confirming(_ focus: any AccessibilityFocus) -> PasteConfirmation {
        PasteConfirmation(focus: focus, budget: budget, interval: interval)
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
}
