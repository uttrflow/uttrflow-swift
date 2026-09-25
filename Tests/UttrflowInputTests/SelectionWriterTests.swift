import ApplicationServices
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A text field held in memory that answers its selection attributes as scripted and records every write.
final class FakeSelectionField: SelectionAttributes, Sendable {
    struct State: Sendable {
        var text: String
        var location: Int
        var length: Int
        var reportsValue = true
        var reportsSelection = true
        var refusesText = false
        var ignoresText = false
        var refusesSelection = false
        var textWrites: [String] = []
        var selectionWrites: [Range<Int>] = []
        /// How many `value()` calls after a write still report the pre-write text, so a fake can go stale-then-fresh.
        var staleReadsAfterWrite = 0
        /// The value `value()` reports while stale reads remain, set the moment a write lands.
        var staleValue: String?
        /// False models a field whose reported caret lags the write along with its value.
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
            guard state.staleReadsAfterWrite > 0, let stale = state.staleValue else { return state.text }
            state.staleReadsAfterWrite -= 1
            if state.staleReadsAfterWrite == 0 { state.staleValue = nil }
            return stale
        }
    }

    func selectedRange() -> CFRange? {
        state.withLock { $0.reportsSelection ? CFRange(location: $0.location, length: $0.length) : nil }
    }

    func setSelectedText(_ text: String) -> AXError {
        state.withLock { state in
            state.textWrites.append(text)
            guard !state.refusesText else { return .cannotComplete }
            guard !state.ignoresText else { return .success }
            let beforeWrite = state.text
            let replaced = NSRange(location: state.location, length: state.length)
            state.text = (state.text as NSString).replacingCharacters(in: replaced, with: text)
            if state.collapsesSelectionAfterWrite {
                state.location += text.utf16.count
                state.length = 0
            }
            if state.staleReadsAfterWrite > 0 { state.staleValue = beforeWrite }
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
    var selectionWrites: [Range<Int>] { state.withLock { $0.selectionWrites } }
}

/// The error a refused step throws, whatever its description.
private func isRejection(_ error: TextInsertionError?) -> Bool {
    if case .insertionRejected = error { true } else { false }
}

@Suite("Writing into a field through its Accessibility attributes")
struct SelectionWriterTests {
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

    @Test("refuses a field that accepts the text and does not change")
    func acceptedButUnchangedIsAFailure() {
        let field = FakeSelectionField("Hello") { $0.ignoresText = true }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).replaceSelection(with: " world")
        }
        #expect(
            error == .insertionRejected(description: "the field accepted the text and did not change"))
    }

    @Test("does not report a late-applied write as unchanged, since the value catches up on a later read")
    func lateAppliedWriteIsNotAFailure() throws {
        let field = FakeSelectionField("Hello") {
            $0.reportsSelection = false
            $0.staleReadsAfterWrite = 2
        }
        try SelectionWriter(field: field, sleep: { _ in }).replaceSelection(with: " world")
        #expect(field.text == "Hello world")
        #expect(field.textWrites == [" world"], "no fallback should have written a second time")
    }

    @Test("still refuses a write that never changes the value, once the re-reads are exhausted")
    func lateReadBudgetStillCatchesAGenuineRefusal() {
        let field = FakeSelectionField("Hello") {
            $0.ignoresText = true
            $0.reportsSelection = false
        }
        let error = #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field, sleep: { _ in }).replaceSelection(with: " world")
        }
        #expect(
            error == .insertionRejected(description: "the field accepted the text and did not change"))
    }

    @Test("does not delete the replaced characters when the write applies a moment late")
    func completionRouteDoesNotUnwindALateWrite() throws {
        let field = FakeSelectionField("I want") {
            $0.staleReadsAfterWrite = 2
            $0.collapsesSelectionAfterWrite = false
        }
        try SelectionWriter(field: field, sleep: { _ in }).replaceSelection(replacing: "want", with: "need")
        #expect(field.text == "I need")
        #expect(
            field.selectionWrites == [2..<6],
            "a caret restore would add a second selection write after the failure it does not hit")
    }

    @Test("passes a field that will not report its value, since the write cannot be checked")
    func unreadableFieldIsTrusted() throws {
        let field = FakeSelectionField("Hello") {
            $0.ignoresText = true
            $0.reportsValue = false
        }
        try SelectionWriter(field: field).replaceSelection(with: " world")
        #expect(field.textWrites == [" world"])
    }

    @Test("passes an empty write that changes nothing")
    func emptyWriteIsNotAFailure() throws {
        let field = FakeSelectionField("Hello") { $0.ignoresText = true }
        try SelectionWriter(field: field).replaceSelection(with: "")
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
}
