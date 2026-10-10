import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Focus over one fake range-editing field, or nothing editable when `field` is nil.
private struct EditableFocus: AccessibilityFocus {
    let field: FakeSelectionField?
    let focused: FieldIdentity?
    func focusedTextField() -> (any FocusedTextField)? { field.map { SelectionWriter(field: $0) } }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedFieldIdentity() -> FieldIdentity? { focused }
}

/// A field that takes text but cannot edit by range.
private struct PlainField: FocusedTextField {
    func replaceSelection(with text: String) throws(TextInsertionError) {}
}

private struct PlainFocus: AccessibilityFocus {
    func focusedTextField() -> (any FocusedTextField)? { PlainField() }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
}

@Suite("The recorded editor in the field in front")
struct RecordedEditorFocusTests {
    private static let field = RecordedEditTests.field

    /// A ledger holding "hello world" written at the end of "Hi, ".
    private func ledger() -> InsertionLedger {
        let ledger = InsertionLedger()
        ledger.note(
            InsertionAttempt(.accessibility, arrival: .confirmed, destination: nil, intoSecureField: false),
            text: "hello world", endingAt: FieldPlace(field: Self.field, caret: 15))
        return ledger
    }

    private func editor(
        _ fake: FakeSelectionField?, ledger: InsertionLedger, focused: FieldIdentity? = field
    ) -> RecordedEditor {
        RecordedEditor(
            ledger: ledger, history: EditHistory(), focus: EditableFocus(field: fake, focused: focused))
    }

    @Test("run carries out the spoken edit in the focused field and returns its notice")
    func runDeletesTheDictation() async throws {
        let fake = FakeSelectionField("Hi, hello world")
        let notice = try await editor(fake, ledger: ledger()).run(.delete)
        #expect(fake.text == "Hi, ")
        #expect(notice == "Deleted 2 words. Say \u{201C}undo that\u{201D} to bring them back.")
    }

    @Test("run refuses a field that cannot edit by range, and changes nothing")
    func runRefusesAPlainField() async {
        let editor = RecordedEditor(ledger: ledger(), history: EditHistory(), focus: PlainFocus())
        await #expect(throws: TextInsertionError.self) { try await editor.run(.delete) }
    }

    @Test("rewrite puts the planned text over the last dictation and returns the plan")
    func rewriteReplacesTheDictation() async throws {
        let fake = FakeSelectionField("Hi, hello world")
        let planned = try await editor(fake, ledger: ledger()).rewrite(
            { $0.replacingOccurrences(of: "world", with: "there") }, writing: { $0 })
        #expect(planned == "hello there")
        #expect(fake.text == "Hi, hello there")
    }

    @Test("rewrite without a separate text step writes the plan itself")
    func rewriteWritesThePlan() async throws {
        let fake = FakeSelectionField("Hi, hello world")
        try await editor(fake, ledger: ledger()).rewrite { $0.uppercased() }
        #expect(fake.text == "Hi, HELLO WORLD")
    }

    @Test("rewrite refuses when the plan declines, and leaves the field alone")
    func rewriteDeclined() async {
        let fake = FakeSelectionField("Hi, hello world")
        let editor = editor(fake, ledger: ledger())
        await #expect(throws: TextInsertionError.self) {
            try await editor.rewrite({ _ in String?.none })
        }
        #expect(fake.text == "Hi, hello world")
    }

    @Test("rewrite refuses when nothing was dictated into this field")
    func rewriteWithNoDictation() async {
        let fake = FakeSelectionField("Hi, hello world")
        let editor = editor(fake, ledger: InsertionLedger())
        await #expect(throws: TextInsertionError.self) { try await editor.rewrite({ $0 }) }
    }

    @Test("rewrite refuses a field that cannot edit by range")
    func rewriteRefusesAPlainField() async {
        let editor = RecordedEditor(ledger: ledger(), history: EditHistory(), focus: PlainFocus())
        await #expect(throws: TextInsertionError.self) { try await editor.rewrite({ $0 }) }
    }
}
