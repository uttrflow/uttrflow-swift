import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Spoken edits on the last dictation")
struct RecordedEditTests {
    static let field = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)
    static let other = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 4)

    /// A ledger holding "hello world" written at the end of "Hi, ".
    private func ledger() -> InsertionLedger {
        let ledger = InsertionLedger()
        ledger.note(
            InsertionAttempt(.accessibility, arrival: .confirmed, destination: nil, intoSecureField: false),
            text: "hello world", endingAt: FieldPlace(field: Self.field, caret: 15))
        return ledger
    }

    private func run(
        _ edit: RecordedEdit, on fake: FakeSelectionField, ledger: InsertionLedger,
        history: EditHistory = EditHistory(), focused: FieldIdentity? = field
    ) throws(TextInsertionError) {
        try RecordedEditor.apply(
            edit, to: SelectionWriter(field: fake), ledger: ledger, history: history, focused: focused,
            isSecure: false)
    }

    @Test(
        "only the whole two-word phrase names an edit",
        arguments: [
            ("delete that", RecordedEdit.delete), ("Delete that.", .delete), ("select that", .select),
            ("Undo that!", .undo),
        ])
    func parses(heard: String, edit: RecordedEdit) {
        #expect(RecordedEdit(heard: heard) == edit)
    }

    @Test(
        "the same words inside a sentence, or another verb, name no edit",
        arguments: ["please delete that file", "delete this", "copy that", "that", ""])
    func refusesOtherWords(heard: String) {
        #expect(RecordedEdit(heard: heard) == nil)
    }

    @Test("delete takes out the dictation and leaves the rest byte-identical")
    func deletes() throws {
        let fake = FakeSelectionField("Hi, hello world")
        let ledger = ledger()
        try run(.delete, on: fake, ledger: ledger)
        #expect(fake.text == "Hi, ")
        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("select selects the dictation and writes nothing")
    func selects() throws {
        let fake = FakeSelectionField("Hi, hello world")
        try run(.select, on: fake, ledger: ledger())
        #expect(fake.selection == 4..<15)
        #expect(fake.textWrites.isEmpty)
    }

    @Test("undo with no spoken edit takes out the dictation; a second undo puts it back")
    func undoes() throws {
        let fake = FakeSelectionField("Hi, hello world")
        let history = EditHistory()
        try run(.undo, on: fake, ledger: ledger(), history: history)
        #expect(fake.text == "Hi, ")
        try run(.undo, on: fake, ledger: InsertionLedger(), history: history)
        #expect(fake.text == "Hi, hello world")
    }

    @Test("a rewrite writes the planned text over the dictation, and undo puts the dictation back")
    func rewrites() throws {
        let fake = FakeSelectionField("Hi, hello world")
        let history = EditHistory()
        try RecordedEditor.rewrite(
            { $0.replacingOccurrences(of: "world", with: "there") }, on: SelectionWriter(field: fake),
            ledger: ledger(), history: history, focused: Self.field, isSecure: false)
        #expect(fake.text == "Hi, hello there")
        try run(.undo, on: fake, ledger: InsertionLedger(), history: history)
        #expect(fake.text == "Hi, hello world")
    }

    @Test("a rewrite whose plan declines refuses and writes nothing")
    func rewriteRefusesADeclinedPlan() {
        let fake = FakeSelectionField("Hi, hello world")
        #expect(throws: TextInsertionError.self) {
            try RecordedEditor.rewrite(
                { _ in nil }, on: SelectionWriter(field: fake), ledger: ledger(), history: EditHistory(),
                focused: Self.field, isSecure: false)
        }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("a field changed since the dictation refuses and keeps its text")
    func refusesAChangedField() {
        let fake = FakeSelectionField("Hi, hello wordl")
        #expect(throws: TextInsertionError.self) { try run(.delete, on: fake, ledger: ledger()) }
        #expect(fake.text == "Hi, hello wordl")
        #expect(fake.textWrites.isEmpty)
    }

    @Test("another field in front refuses, for every edit", arguments: RecordedEdit.allCases)
    func refusesAnotherField(edit: RecordedEdit) {
        let fake = FakeSelectionField("Hi, hello world")
        #expect(throws: TextInsertionError.self) {
            try run(edit, on: fake, ledger: ledger(), focused: Self.other)
        }
        #expect(fake.text == "Hi, hello world")
        #expect(fake.selectionWrites.isEmpty)
    }
}
