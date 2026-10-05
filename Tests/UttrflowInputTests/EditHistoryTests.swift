import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Undoing a spoken edit")
struct EditHistoryTests {
    static let field = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)
    static let other = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 4)

    private func deleteHello(in field: FakeSelectionField, history: EditHistory) throws {
        let record = InsertionRecord(field: Self.field, range: 4..<9, text: "hello")
        let target = EditTarget(record: record, focused: Self.field, isSecure: false)
        history.note(try SelectionWriter(field: field).edit(target, to: ""))
    }

    private func undo(
        _ field: FakeSelectionField, _ history: EditHistory, focused: FieldIdentity? = field
    ) throws {
        try SelectionWriter(field: field).undo(from: history, focused: focused, isSecure: false)
    }

    @Test("delete then undo restores the exact text and caret")
    func undoRestores() throws {
        let field = FakeSelectionField("Hi, hello there", caret: 9)
        let history = EditHistory()
        try deleteHello(in: field, history: history)
        #expect(field.text == "Hi,  there")
        try undo(field, history)
        #expect(field.text == "Hi, hello there")
        #expect(field.selection == 9..<9)
    }

    @Test("an undo of an undo re-applies the edit")
    func undoOfUndoReapplies() throws {
        let field = FakeSelectionField("Hi, hello there", caret: 9)
        let history = EditHistory()
        try deleteHello(in: field, history: history)
        try undo(field, history)
        try undo(field, history)
        #expect(field.text == "Hi,  there")
        #expect(field.selection == 4..<4)
    }

    @Test("refuses after the user typed beside the span, and forgets the edit")
    func refusesAfterTyping() throws {
        let field = FakeSelectionField("Hi, hello there", caret: 9)
        let history = EditHistory()
        try deleteHello(in: field, history: history)
        field.state.withLock {
            $0.text = "Hi,  xthere"
            $0.location = 4
        }
        #expect(throws: TextInsertionError.self) { try undo(field, history) }
        #expect(field.text == "Hi,  xthere")
        #expect(history.take(in: Self.field) == nil)
    }

    @Test("refuses from another field and forgets the edit")
    func refusesAnotherField() throws {
        let field = FakeSelectionField("Hi, hello", caret: 9)
        let history = EditHistory()
        try deleteHello(in: field, history: history)
        #expect(throws: TextInsertionError.self) { try undo(field, history, focused: Self.other) }
        #expect(history.take(in: Self.field) == nil)
        #expect(field.text == "Hi, ")
    }

    @Test("an edit is not undoable once the window passes")
    func windowHolds() throws {
        let clock = ManualClock()
        let history = EditHistory(clock: clock)
        let field = FakeSelectionField("Hi, hello", caret: 9)
        try deleteHello(in: field, history: history)
        clock.advance(by: EditHistory.window + .seconds(1))
        #expect(throws: TextInsertionError.self) { try undo(field, history) }
        #expect(field.text == "Hi, ")
    }

    @Test("only the last depth edits are kept")
    func depthHolds() {
        let history = EditHistory()
        for index in 0..<(EditHistory.depth + 3) {
            let record = InsertionRecord(field: Self.field, range: index..<index, text: "")
            history.note(EditUndo(written: record, removed: "w\(index)", before: "", after: ""))
        }
        var taken: [String] = []
        while let undo = history.take(in: Self.field) { taken.append(undo.removed) }
        #expect(taken.count == EditHistory.depth)
        #expect(taken.first == "w\(EditHistory.depth + 2)")
    }

    @Test("removed text never appears in a description")
    func removedTextIsNotDescribed() {
        let record = InsertionRecord(field: Self.field, range: 4..<4, text: "")
        let undo = EditUndo(written: record, removed: "secret words", before: "Hi, ", after: " there")
        for text in [
            String(describing: undo), String(reflecting: undo), "\(undo)",
            "\(Mirror(reflecting: undo).children.count)",
        ] {
            #expect(!text.contains("secret"))
            #expect(!text.contains("there"))
        }
    }
}
