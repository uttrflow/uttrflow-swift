import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Undo last dictation, from a click or a key")
struct UndoLastDictationTests {
    static let field = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)

    private func ledger(_ text: String = "hello world", caret: Int = 15) -> InsertionLedger {
        let ledger = InsertionLedger()
        ledger.note(
            InsertionAttempt(.accessibility, arrival: .confirmed, destination: nil, intoSecureField: false),
            text: text, endingAt: FieldPlace(field: Self.field, caret: caret))
        return ledger
    }

    private func undo(
        _ fake: FakeSelectionField,
        ledger: InsertionLedger,
        history: EditHistory = EditHistory()
    ) throws(TextInsertionError) -> String {
        try RecordedEditor.undoDictation(
            on: SelectionWriter(field: fake), ledger: ledger, history: history, focused: Self.field,
            isSecure: false)
    }

    @Test("takes out exactly the dictation, returns its words and leaves the rest byte-identical")
    func removesTheDictation() throws {
        let fake = FakeSelectionField("Hi, hello world")
        let removed = try undo(fake, ledger: ledger())
        #expect(removed == "hello world")
        #expect(fake.text == "Hi, ")
    }

    @Test("a dictation over several lines is undone by one press, with no spoken confirmation")
    func removesSeveralLines() throws {
        let fake = FakeSelectionField("Hi, hello\n\nworld")
        _ = try undo(fake, ledger: ledger("hello\n\nworld", caret: 16))
        #expect(fake.text == "Hi, ")
    }

    @Test("the removal can be taken back by the spoken undo")
    func staysUndoable() throws {
        let fake = FakeSelectionField("Hi, hello world")
        let history = EditHistory()
        _ = try undo(fake, ledger: ledger(), history: history)
        try RecordedEditor.apply(
            .undo, to: SelectionWriter(field: fake), ledger: InsertionLedger(), history: history,
            focused: Self.field, isSecure: false)
        #expect(fake.text == "Hi, hello world")
    }

    @Test("a field the user has since changed refuses with zero writes")
    func refusesAChangedField() {
        let fake = FakeSelectionField("Hi, hello word")
        #expect(throws: TextInsertionError.self) { try undo(fake, ledger: ledger()) }
        #expect(fake.text == "Hi, hello word")
        #expect(fake.textWrites.isEmpty)
    }

    @Test("text typed after the dictation refuses with zero writes")
    func refusesTextTypedAfter() {
        let fake = FakeSelectionField("Hi, hello world, and more")
        #expect(throws: TextInsertionError.self) { try undo(fake, ledger: ledger()) }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("an empty ledger refuses with zero writes")
    func refusesWithNothingRecorded() {
        let fake = FakeSelectionField("Hi, hello world")
        #expect(throws: TextInsertionError.self) { try undo(fake, ledger: InsertionLedger()) }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("another field in front refuses with zero writes")
    func refusesAnotherField() {
        let fake = FakeSelectionField("Hi, hello world")
        let other = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 4)
        #expect(throws: TextInsertionError.self) {
            try RecordedEditor.undoDictation(
                on: SelectionWriter(field: fake), ledger: ledger(), history: EditHistory(), focused: other,
                isSecure: false)
        }
        #expect(fake.textWrites.isEmpty)
    }
}
