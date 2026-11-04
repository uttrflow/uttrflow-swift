import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Confirming a delete over more than one line")
struct ConfirmedDeleteTests {
    static let field = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)
    static let text = "Hi, hello\n\nworld"

    private func ledger() -> InsertionLedger {
        let ledger = InsertionLedger()
        ledger.note(
            InsertionAttempt(.accessibility, arrival: .confirmed, destination: nil, intoSecureField: false),
            text: "hello\n\nworld", endingAt: FieldPlace(field: Self.field, caret: 16))
        return ledger
    }

    @discardableResult
    private func run(
        _ edit: RecordedEdit, _ fake: FakeSelectionField, _ ledger: InsertionLedger,
        _ pending: PendingConfirmation, history: EditHistory = EditHistory()
    ) throws(TextInsertionError) -> String {
        try RecordedEditor.apply(
            edit, to: SelectionWriter(field: fake), ledger: ledger, history: history, focused: Self.field,
            isSecure: false, pending: pending)
    }

    @Test("the word is heard whole, and only the configured word")
    func parses() {
        #expect(RecordedEdit(heard: "Confirm.") == .confirm)
        #expect(RecordedEdit(heard: "confirm that") == nil)
        #expect(RecordedEdit(heard: "yes") == nil)
        #expect(ConfirmationPolicy.window == .seconds(3))
    }

    @Test("delete refuses at first and asks for the word, writing nothing")
    func armsAndRefuses() {
        let fake = FakeSelectionField(Self.text)
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger(), PendingConfirmation()) }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("the word inside the window runs the delete, and undo brings it back")
    func confirmRuns() throws {
        let fake = FakeSelectionField(Self.text)
        let ledger = ledger()
        let pending = PendingConfirmation()
        let history = EditHistory()
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger, pending, history: history) }
        let notice = try run(.confirm, fake, ledger, pending, history: history)
        #expect(fake.text == "Hi, ")
        #expect(notice == "Deleted 2 words. Say \u{201C}undo that\u{201D} to bring them back.")
        try run(.undo, fake, InsertionLedger(), pending, history: history)
        #expect(fake.text == Self.text)
    }

    @Test("the word after the window refuses and does nothing")
    func lateRefuses() {
        let clock = ManualClock()
        let pending = PendingConfirmation(clock: clock)
        let fake = FakeSelectionField(Self.text)
        let ledger = ledger()
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger, pending) }
        clock.advance(by: ConfirmationPolicy.window + .milliseconds(1))
        #expect(throws: TextInsertionError.self) { try run(.confirm, fake, ledger, pending) }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("the word with nothing asked, or twice, refuses")
    func strayWordRefuses() throws {
        let fake = FakeSelectionField(Self.text)
        let ledger = ledger()
        let pending = PendingConfirmation()
        #expect(throws: TextInsertionError.self) { try run(.confirm, fake, ledger, pending) }
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger, pending) }
        try run(.confirm, fake, ledger, pending)
        #expect(throws: TextInsertionError.self) { try run(.confirm, fake, InsertionLedger(), pending) }
    }

    @Test("a field that changed between the ask and the word refuses and keeps its text")
    func changedFieldRefuses() {
        let fake = FakeSelectionField(Self.text)
        let ledger = ledger()
        let pending = PendingConfirmation()
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger, pending) }
        fake.state.withLock { $0.text = "Hi, hello\n\nwurld" }
        #expect(throws: TextInsertionError.self) { try run(.confirm, fake, ledger, pending) }
        #expect(fake.textWrites.isEmpty)
    }

    @Test("another command between the ask and the word cancels the ask")
    func otherCommandCancels() throws {
        let fake = FakeSelectionField(Self.text)
        let ledger = ledger()
        let pending = PendingConfirmation()
        #expect(throws: TextInsertionError.self) { try run(.delete, fake, ledger, pending) }
        try run(.select, fake, ledger, pending)
        #expect(throws: TextInsertionError.self) { try run(.confirm, fake, ledger, pending) }
        #expect(fake.textWrites.isEmpty)
    }
}
