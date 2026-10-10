// Runs "delete that", "select that" and "undo that" on the last dictation, by its recorded range. See `Docs/commands.md`.
public import UttrflowCore

/// One spoken edit on the last dictation; it only removes or selects what Uttrflow wrote, never rewrites a word.
public enum RecordedEdit: String, Sendable, CaseIterable {
    /// Takes the last dictation out of the field.
    case delete
    /// Selects the last dictation.
    case select
    /// Undoes the last spoken edit, or, with none to undo, takes the last dictation out.
    case undo

    /// The notice once the edit ran, given the text it took out; it counts the words but never names one.
    func done(removing removed: String?) -> String {
        guard let removed else {
            return self == .select ? "Selected the last dictation." : "Undid the last edit."
        }
        let count = removed.split(whereSeparator: \.isWhitespace).count
        let (words, them) = count == 1 ? ("1 word", "it") : ("\(count) words", "them")
        return "Deleted \(words). Say \u{201C}undo that\u{201D} to bring \(them) back."
    }

    /// The edit the whole utterance names, ignoring the recogniser's case and closing mark; nil for anything else.
    public init?(heard: String) {
        let keys = heard.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)).key }
        guard keys.count == 2, keys[1] == "that", let edit = RecordedEdit(rawValue: keys[0]) else {
            return nil
        }
        self = edit
    }
}

/// The field writes a recorded edit needs, which only an Accessibility field that reads ranges offers.
protocol RecordedSpanEditing: Sendable {
    func edit(_ target: EditTarget, to text: String) throws(TextInsertionError) -> EditUndo
    func select(_ target: EditTarget) throws(TextInsertionError)
    func undo(from history: EditHistory, focused: FieldIdentity?, isSecure: Bool) throws(TextInsertionError)
}

extension SelectionWriter: RecordedSpanEditing {}

/// Carries out a `RecordedEdit` in the focused field, against the ledger of confirmed insertions.
public struct RecordedEditor: Sendable {
    private let ledger: InsertionLedger
    private let history: EditHistory
    private let focus: any AccessibilityFocus

    public init(ledger: InsertionLedger, history: EditHistory, focus: any AccessibilityFocus) {
        self.ledger = ledger
        self.history = history
        self.focus = focus
    }

    /// Runs `edit` in the field in front, returning its notice; it throws, changing nothing, unless the dictation is still there.
    @discardableResult
    public func run(_ edit: RecordedEdit) async throws(TextInsertionError) -> String {
        let focus = focus
        let ledger = ledger
        let history = history
        return try await AccessibilityThread.run { () throws(TextInsertionError) in
            let focused = focus.focusedFieldIdentity()
            let secure = focus.focusedFieldIsSecure()
            guard let field = focus.focusedTextField() as? any RecordedSpanEditing else {
                throw .insertionRejected(description: "the field cannot edit by range")
            }
            return try Self.apply(
                edit, to: field, ledger: ledger, history: history, focused: focused, isSecure: secure)
        }
    }

    /// Writes the text of `plan`'s answer over the last dictation and returns it; a declined plan throws, writing nothing.
    public func rewrite<Planned: Sendable>(
        _ plan: @escaping @Sendable (String) -> Planned?,
        writing text: @escaping @Sendable (Planned) -> String
    ) async throws(TextInsertionError) -> Planned {
        let focus = focus
        let ledger = ledger
        let history = history
        return try await AccessibilityThread.run { () throws(TextInsertionError) in
            let focused = focus.focusedFieldIdentity()
            let secure = focus.focusedFieldIsSecure()
            guard let field = focus.focusedTextField() as? any RecordedSpanEditing else {
                throw .insertionRejected(description: "the field cannot edit by range")
            }
            return try Self.rewrite(
                plan, writing: text, on: field, ledger: ledger, history: history, focused: focused,
                isSecure: secure)
        }
    }

    /// Writes the text `plan` makes of the last dictation in its place; it throws, changing nothing, when `plan` declines.
    public func rewrite(_ plan: @escaping @Sendable (String) -> String?) async throws(TextInsertionError) {
        _ = try await rewrite(plan, writing: { $0 })
    }

    /// Rewrites the last dictation in `field` with the text `plan` makes of it.
    static func rewrite(
        _ plan: (String) -> String?, on field: any RecordedSpanEditing, ledger: InsertionLedger,
        history: EditHistory, focused: FieldIdentity?, isSecure: Bool
    ) throws(TextInsertionError) {
        _ = try rewrite(
            plan, writing: { $0 }, on: field, ledger: ledger, history: history, focused: focused,
            isSecure: isSecure)
    }

    /// Rewrites the last dictation in `field` with `plan`; split out so it runs against a fake field in tests.
    static func rewrite<Planned>(
        _ plan: (String) -> Planned?, writing text: (Planned) -> String, on field: any RecordedSpanEditing,
        ledger: InsertionLedger, history: EditHistory, focused: FieldIdentity?, isSecure: Bool
    ) throws(TextInsertionError) -> Planned {
        guard let record = CommandScope.default.span(in: ledger.records(in: focused)) else {
            throw .insertionRejected(description: "there is no dictation here to edit")
        }
        guard let planned = plan(record.text) else {
            throw .insertionRejected(description: "the words to change are not in the last dictation")
        }
        let target = EditTarget(record: record, focused: focused, isSecure: isSecure)
        try write(text(planned), over: target, in: field, ledger: ledger, history: history)
        return planned
    }

    /// Applies `edit` to `field` and returns its notice; split out so it runs against a fake field in tests.
    @discardableResult
    static func apply(
        _ edit: RecordedEdit, to field: any RecordedSpanEditing, ledger: InsertionLedger,
        history: EditHistory, focused: FieldIdentity?, isSecure: Bool
    ) throws(TextInsertionError) -> String {
        if edit == .undo, history.holdsEdit(in: focused) {
            try field.undo(from: history, focused: focused, isSecure: isSecure)
            return edit.done(removing: nil)
        }
        guard let record = CommandScope.default.span(in: ledger.records(in: focused)) else {
            throw .insertionRejected(description: "there is no dictation here to edit")
        }
        let target = EditTarget(record: record, focused: focused, isSecure: isSecure)
        switch edit {
        case .select:
            try field.select(target)
            return edit.done(removing: nil)
        case .delete, .undo:
            guard !spansParagraphs(record.text) else {
                throw .insertionRejected(description: "the last dictation runs over more than one line")
            }
            try write("", over: target, in: field, ledger: ledger, history: history)
            return edit.done(removing: record.text)
        }
    }

    /// Whether `text` runs over more than one line; a spoken delete of that much is refused, not run.
    static func spansParagraphs(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).count > 1
    }

    /// Writes `text` over `target`, keeping the edit undoable; the ledger is emptied either way.
    private static func write(
        _ text: String, over target: EditTarget, in field: any RecordedSpanEditing, ledger: InsertionLedger,
        history: EditHistory
    ) throws(TextInsertionError) {
        do {
            history.note(try field.edit(target, to: text))
        } catch {
            ledger.clear()
            throw error
        }
        // Offsets after the edit name other text now, so none is kept.
        ledger.clear()
    }
}
