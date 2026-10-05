import ApplicationServices
import Foundation
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowInput

/// The attribute probes for a focused accessibility element.
private struct MockFocusedAccessibilityElement {
    let role: String
    let selectedTextIsReadable: Bool
    let selectedTextIsSettable: Bool

    func isEligibleForTextInsertion() -> Bool {
        FocusedTextFieldEligibility.accepts(
            role: role,
            selectedTextIsReadable: { selectedTextIsReadable },
            selectedTextIsSettable: { selectedTextIsSettable })
    }
}

/// A text field held in memory that answers its selection attributes as scripted and records every write.
final class FakeSelectionField: SelectionAttributes, Sendable {
    struct State: Sendable {
        var text: String
        var location: Int
        var length: Int
        var reportsValue = true
        var reportsSelection = true
        var readsByRange = true
        var reportedLength: Int?
        var wholeReads = 0
        var unitsRead = 0
        var refusesText = false
        /// How long the field takes to answer a text write, spent on `clock`.
        var answersAfter: Duration = .zero
        var clock: ManualClock?
        var ignoresText = false
        var movesCaretOnly = false
        var refusesSelection = false
        var textWrites: [String] = []
        var selectionWrites: [Range<Int>] = []
        /// Text another writer inserts immediately before this write is applied.
        var concurrentTextBeforeWrite: String?
        /// False models a field that leaves the original selection in place after writing.
        var collapsesSelectionAfterWrite = true
    }

    let state: Mutex<State>

    init(_ text: String, caret: Int? = nil, length: Int = 0, script: (inout State) -> Void = { _ in }) {
        var state = State(text: text, location: caret ?? text.utf16.count, length: length)
        script(&state)
        self.state = Mutex(state)
    }

    func value() -> String? {
        state.withLock { state in
            guard state.reportsValue else { return nil }
            state.wholeReads += 1
            state.unitsRead += state.text.utf16.count
            return state.text
        }
    }

    func length() -> Int? {
        state.withLock {
            guard $0.reportsValue, $0.readsByRange else { return nil }
            return $0.reportedLength ?? $0.text.utf16.count
        }
    }

    func text(in range: Range<Int>) -> String? {
        state.withLock { state in
            guard state.reportsValue, state.readsByRange, range.upperBound <= state.text.utf16.count
            else { return nil }
            state.unitsRead += range.count
            return (state.text as NSString).substring(
                with: NSRange(location: range.lowerBound, length: range.count))
        }
    }

    func selectedRange() -> CFRange? {
        state.withLock { $0.reportsSelection ? CFRange(location: $0.location, length: $0.length) : nil }
    }

    func setSelectedText(_ text: String) -> AXError {
        state.withLock { state in
            state.clock?.advance(by: state.answersAfter)
            state.textWrites.append(text)
            guard !state.refusesText else { return .cannotComplete }
            guard !state.ignoresText else { return .success }
            if state.movesCaretOnly {
                state.location += text.utf16.count
                state.length = 0
                return .success
            }
            if let concurrentText = state.concurrentTextBeforeWrite {
                let concurrentRange = NSRange(location: state.location, length: state.length)
                state.text = (state.text as NSString).replacingCharacters(
                    in: concurrentRange, with: concurrentText)
                state.location += concurrentText.utf16.count
                state.length = 0
                state.concurrentTextBeforeWrite = nil
            }
            let replaced = NSRange(location: state.location, length: state.length)
            state.text = (state.text as NSString).replacingCharacters(in: replaced, with: text)
            if state.collapsesSelectionAfterWrite {
                state.location += text.utf16.count
                state.length = 0
            }
            return .success
        }
    }

    func setSelectedRange(_ range: CFRange) -> AXError {
        state.withLock { state in
            state.selectionWrites.append(range.location..<(range.location + range.length))
            guard !state.refusesSelection else { return .attributeUnsupported }
            state.location = range.location
            state.length = range.length
            return .success
        }
    }

    var text: String { state.withLock { $0.text } }
    var selection: Range<Int> { state.withLock { $0.location..<($0.location + $0.length) } }
    var textWrites: [String] { state.withLock { $0.textWrites } }
    var wholeReads: Int { state.withLock { $0.wholeReads } }
    var unitsRead: Int { state.withLock { $0.unitsRead } }
    var selectionWrites: [Range<Int>] { state.withLock { $0.selectionWrites } }
}

/// The error a refused step throws, whatever its description.
private func isRejection(_ error: TextInsertionError?) -> Bool {
    if case .insertionRejected = error { true } else { false }
}

@Suite("Writing into a field through its Accessibility attributes")
struct SelectionWriterTests {
    @Test("A hostile starting caret cannot overflow while confirming a write.")
    func hostileStartingCaretDoesNotOverflow() {
        for location in [NSNotFound, Int.max, Int.max - 1, Int.min, -1, 5, 6] {
            for length in [0, 1, Int.max, -1] {
                let field = FakeSelectionField("hello", caret: location, length: length) {
                    $0.ignoresText = true
                }
                #expect(throws: TextInsertionError.self) {
                    try SelectionWriter(field: field).replaceSelection(with: "x")
                }
            }
        }
    }

    @Test("A hostile selection cannot overflow the comparison window.")
    func hostileSelectionDoesNotOverflowWindow() throws {
        let field = FakeSelectionField("hello", caret: .max, length: .max) {
            $0.reportedLength = .max
            $0.ignoresText = true
        }
        try SelectionWriter(field: field).replaceSelection(with: "")
    }

    @Test func rejectsReadableSelectionOnANonSettableElement() {
        let element = MockFocusedAccessibilityElement(
            role: "AXTextField", selectedTextIsReadable: true, selectedTextIsSettable: false)

        #expect(!element.isEligibleForTextInsertion())
    }

    @Test("A write answering cannot-complete after the timeout is unconfirmed and stops the fallback")
    func lateAnswerIsUnconfirmed() {
        let clock = ManualClock()
        let field = FakeSelectionField("Hello ") {
            $0.refusesText = true
            $0.clock = clock
            $0.answersAfter = SelectionWriter<FakeSelectionField>.messagingTimeout
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field, clock: ElapsedClock(clock)).replaceSelection(with: "world")
        }
        #expect(error == .insertionUnconfirmed)
        #expect(error?.stopsFallback == true, "the typed route must not write the words a second time")
    }

    @Test("A write refused inside the messaging timeout is a refusal the next route may retry")
    func promptRefusalFallsThrough() {
        let clock = ManualClock()
        let field = FakeSelectionField("Hello ") {
            $0.refusesText = true
            $0.clock = clock
            $0.answersAfter = .milliseconds(1_999)
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field, clock: ElapsedClock(clock)).replaceSelection(with: "world")
        }
        #expect(isRejection(error))
        #expect(error?.stopsFallback == false)
    }

    @Test("Only a cannot-complete answer at or past the timeout is unconfirmed")
    func writeFailureMapping() {
        let limit = SelectionWriter<FakeSelectionField>.messagingTimeout
        let cases: [(AXError, Duration, Bool)] = [
            (.cannotComplete, limit, true), (.cannotComplete, limit * 3, true),
            (.cannotComplete, .zero, false), (.attributeUnsupported, limit, false),
            (.illegalArgument, limit * 2, false), (.failure, limit, false),
        ]
        for (result, elapsed, unconfirmed) in cases {
            let error = SelectionWriter<FakeSelectionField>.writeFailure(result, after: elapsed)
            #expect((error == .insertionUnconfirmed) == unconfirmed, "\(result.rawValue) after \(elapsed)")
        }
    }

    @Test("replaces the selection with the text")
    func replacesTheSelection() throws {
        let field = FakeSelectionField("Hello earth", caret: 6, length: 5)
        try SelectionWriter(field: field).replaceSelection(with: "world")
        #expect(field.text == "Hello world")
        #expect(field.selection == 11..<11)
    }

    @Test("accepts replacing a selection with the same text, since the caret still moved")
    func sameTextReplacementIsNotAFailure() throws {
        let field = FakeSelectionField("same", caret: 0, length: 4)
        try SelectionWriter(field: field).replaceSelection(with: "same")
        #expect(field.text == "same")
        #expect(field.selection == 4..<4, "a genuine write still collapses the selection to a caret past it")
        #expect(field.textWrites == ["same"], "no fallback should have written a second time")
    }

    @Test("rejects a write that moves the caret over a different selection and leaves the text as it was")
    func caretMovedButDifferentSelectionUnchangedIsRejected() {
        let field = FakeSelectionField("other", caret: 0, length: 5) { $0.movesCaretOnly = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: "words")
        }
        #expect(error == .insertionRejected(description: "the field accepted the text and did not change"))
    }

    @Test("does not claim a write landed when the field still reports its old value")
    func acceptedButUnchangedIsAFailure() {
        let field = FakeSelectionField("Hello") { $0.ignoresText = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(error == .insertionUnconfirmed)
    }

    @Test("marks a successful write ambiguous when the resulting selection is unavailable")
    func unknownResultingSelectionIsAmbiguous() {
        let field = FakeSelectionField("Hello") {
            $0.reportsSelection = false
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(error == .insertionUnconfirmed)
        #expect(field.text == "Hello world")
        #expect(field.textWrites == [" world"])
    }

    @Test("marks an accepted write ambiguous when the resulting caret is unexpected")
    func unexpectedResultingCaretIsAmbiguous() {
        let field = FakeSelectionField("Hello") { $0.collapsesSelectionAfterWrite = false }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(error == .insertionUnconfirmed)
    }

    @Test("does not move the selection after an accepted write has an unexpected result")
    func completionRouteDoesNotUnwindAnAmbiguousWrite() {
        let field = FakeSelectionField("I want") {
            $0.collapsesSelectionAfterWrite = false
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(error == .insertionUnconfirmed)
        #expect(field.text == "I need")
        #expect(
            field.selectionWrites == [2..<6],
            "an ambiguous write must not restore the old caret over its resulting selection")
    }

    @Test("marks a concurrent selection move ambiguous after Accessibility accepts the write")
    func concurrentSelectionMoveIsAmbiguous() {
        let field = FakeSelectionField("Hello earth", caret: 6, length: 5) {
            $0.concurrentTextBeforeWrite = "neighbor"
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: "world")
        }
        #expect(error == .insertionUnconfirmed)
        #expect(field.text == "Hello neighborworld")
        #expect(field.textWrites == ["world"], "the accepted text write is never repeated")
    }

    @Test("confirms a write by its resulting selection even when the whole value is unreadable")
    func unreadableValueCanBeConfirmedBySelection() throws {
        let field = FakeSelectionField("Hello") { $0.reportsValue = false }
        try SelectionWriter(field: field).replaceSelection(with: " world")
        #expect(field.textWrites == [" world"])
    }

    @Test("passes an empty write that changes nothing")
    func emptyWriteIsNotAFailure() throws {
        let field = FakeSelectionField("Hello") { $0.ignoresText = true }
        try SelectionWriter(field: field).replaceSelection(with: "")
        #expect(field.text == "Hello")
        #expect(field.textWrites == [""])
    }

    @Test("reports a field that refuses the text")
    func refusedText() {
        let field = FakeSelectionField("Hello") { $0.refusesText = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(isRejection(error))
        #expect(field.text == "Hello")
    }

    @Test("widens the selection back over the replaced words and writes once")
    func replacesOverTheWordsBeforeTheCaret() throws {
        let field = FakeSelectionField("I want")
        try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        #expect(field.text == "I need")
        #expect(field.selectionWrites == [2..<6])
        #expect(field.textWrites == ["need"])
    }

    @Test("takes a selection after the caret in with the words before it")
    func replacesOverASelection() throws {
        let field = FakeSelectionField("I want it", caret: 6, length: 3)
        try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        #expect(field.text == "I need")
        #expect(field.selectionWrites == [2..<9])
    }

    @Test("puts the caret back when the field takes the selection and refuses the text")
    func refusedWriteRestoresTheCaret() {
        let field = FakeSelectionField("I want") { $0.refusesText = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(isRejection(error))
        #expect(field.text == "I want")
        #expect(field.selectionWrites == [2..<6, 6..<6])
        #expect(field.selection == 6..<6)
    }

    @Test("refuses when the text before the caret is not what would be replaced")
    func changedTextIsNotTakenBack() {
        let field = FakeSelectionField("I was")
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(
            error
                == .insertionRejected(description: "the text before the caret is not what would be replaced"))
        #expect(field.selectionWrites.isEmpty)
        #expect(field.textWrites.isEmpty)
        #expect(field.text == "I was")
    }

    @Test("refuses when there is less text before the caret than would be replaced")
    func tooLittleText() {
        let field = FakeSelectionField("at")
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(error == .insertionRejected(description: "the field has too little text before the caret"))
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses a field that will not report its selection")
    func hiddenSelection() {
        let field = FakeSelectionField("I want") { $0.reportsSelection = false }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(error == .insertionRejected(description: "the field will not report its selection"))
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses a field that will not take the selection, writing nothing")
    func refusedSelection() {
        let field = FakeSelectionField("I want") { $0.refusesSelection = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        }
        #expect(isRejection(error))
        #expect(field.textWrites.isEmpty)
        #expect(field.text == "I want")
    }

    @Test("writes at the caret when nothing is to be replaced")
    func nothingReplacedIsAPlainWrite() throws {
        let field = FakeSelectionField("I") { $0.refusesSelection = true }
        try SelectionWriter(field: field).replaceSelection(replacing: "", with: " want")
        #expect(field.text == "I want")
        #expect(field.selectionWrites.isEmpty)
    }

    @Test("reads only around the caret in a long field, never its whole value")
    func longFieldIsReadByRange() throws {
        let long = String(repeating: "word ", count: 200_000) + "I want"
        let field = FakeSelectionField(long)
        try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        #expect(field.text.hasSuffix("I need"))
        #expect(field.wholeReads == 0)
        #expect(field.unitsRead < 1_000)
    }

    @Test("still catches an unchanged write when the check reads by range")
    func unchangedWriteIsCaughtByRange() {
        let field = FakeSelectionField(String(repeating: "word ", count: 1_000)) { $0.ignoresText = true }
        #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(field.wholeReads == 0)
    }

    @Test("falls back to the whole value for a field that will not read by range")
    func noRangedReadFallsBackToTheValue() throws {
        let field = FakeSelectionField("I want it", caret: 6, length: 3) { $0.readsByRange = false }
        try SelectionWriter(field: field).replaceSelection(replacing: "want", with: "need")
        #expect(field.text == "I need")
        #expect(field.selectionWrites == [2..<9])
        #expect(field.wholeReads > 0)
    }
}
