// Replaces a field's selection through its Accessibility attributes, checking each step.
import ApplicationServices
import Foundation
import UttrflowCore
import UttrflowPredict

/// The Accessibility attributes a selection is read and written through; the real one wraps an `AXUIElement`.
protocol SelectionAttributes: Sendable {
    /// The field's whole contents, when it will say.
    func value() -> String?
    /// The field's length in UTF-16 units, when it will say.
    func length() -> Int?
    /// The text a UTF-16 range covers, when the field reads by range.
    func text(in range: Range<Int>) -> String?
    /// The selection in UTF-16 units, when the field will say.
    func selectedRange() -> CFRange?
    /// Writes over the selection, or at the caret when there is none.
    func setSelectedText(_ text: String) -> AXError
    /// Moves the selection.
    func setSelectedRange(_ range: CFRange) -> AXError
}

/// Writes into one focused field through its attributes, so the order of the steps is testable without a window.
struct SelectionWriter<Field: SelectionAttributes>: FocusedTextField {
    /// The field this writes into.
    let field: Field
    /// Times each write, so one that ran out the messaging timeout is told apart from a refusal.
    var clock = ElapsedClock()
    /// How long one Accessibility message may take before the system gives up waiting for it.
    static var messagingTimeout: Duration { .seconds(2) }

    func replaceSelection(with text: String) throws(TextInsertionError) {
        // Read first so the write can be checked; a field that will not answer is trusted.
        let selectionBefore = field.selectedRange()
        let window = window(around: selectionBefore)
        let before = snapshot(window)
        let alreadyHeld = selectedText(selectionBefore) == text

        try setSelectedText(text)

        guard !text.isEmpty else { return }
        guard let selectionBefore else { throw .insertionUnconfirmed }
        let (expectedLocation, overflow) = selectionBefore.location.addingReportingOverflow(
            text.utf16.count)
        guard !overflow,
            let after = field.selectedRange(), after.length == 0,
            after.location == expectedLocation
        else {
            // An unconfirmed write may still land, so typed fallback must not repeat it. See `Docs/insertion.md`.
            throw .insertionUnconfirmed
        }

        // A success that changed nothing is the failure this catches, unless the selection already held the text. See `Docs/insertion.md`.
        if !alreadyHeld, let before, let after = snapshot(window), before == after {
            throw .insertionRejected(
                description: "the field accepted the text and did not change")
        }
    }

    /// Whether a reading is the selection `selection`.
    private static func same(_ reading: CFRange?, _ selection: CFRange) -> Bool {
        reading?.location == selection.location && reading?.length == selection.length
    }

    /// Grows the selection back over what is replaced first, so one write replaces it and undo sees one edit.
    func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError) {
        guard !replaced.isEmpty else { return try replaceSelection(with: text) }
        let caret = try selectBackwards(over: replaced)
        do {
            try replaceSelection(with: text)
        } catch {
            if error == .insertionUnconfirmed { throw error }
            // A field that takes the selection and refuses the text keeps its caret, not a selection.
            _ = try? select(caret)
            throw error
        }
    }

    /// Moves the selection's start back over `replaced`, once it is confirmed to be there, and answers with the selection it replaces.
    private func selectBackwards(over replaced: String) throws(TextInsertionError) -> CFRange {
        guard let selection = field.selectedRange(),
            let (text, caret, length) = textBefore(selection.location, covering: replaced.count)
        else {
            throw .insertionRejected(description: "the field will not report its selection")
        }
        guard let preceding = BackwardSelection.range(in: text, endingAt: caret, covering: replaced.count)
        else {
            throw .insertionRejected(description: "the field has too little text before the caret")
        }
        // Checked like the typed route, so a character typed since the edit was worked out is never taken back.
        guard BackwardSelection.confirms(replaced, in: text, endingAt: caret) else {
            throw .insertionRejected(description: "the text before the caret is not what would be replaced")
        }
        let (remaining, remainingOverflow) = length.subtractingReportingOverflow(selection.location)
        let (location, locationOverflow) = selection.location.subtractingReportingOverflow(preceding.count)
        guard !remainingOverflow, !locationOverflow else {
            throw .insertionRejected(description: "the field reported an invalid selection")
        }
        let selected = min(max(selection.length, 0), max(remaining, 0))
        let (selectionLength, lengthOverflow) = preceding.count.addingReportingOverflow(selected)
        guard !lengthOverflow else {
            throw .insertionRejected(description: "the field reported an invalid selection")
        }
        try select(CFRange(location: location, length: selectionLength))
        return selection
    }

    /// Text ending at `caret`, read by range where the field allows it, with the caret's offset into it and the field's length.
    private func textBefore(_ caret: Int, covering characters: Int) -> (String, Int, Int)? {
        if let length = field.length(),
            let window = CaretWindow.before(caret, characters: characters, ranged: field.text(in:))
        {
            return (window, window.utf16.count, length)
        }
        return field.value().map { ($0, caret, $0.utf16.count) }
    }

    /// The text the selection covers before the write, when the field will say.
    private func selectedText(_ selection: CFRange?) -> String? {
        guard let selection, selection.location >= 0, selection.length > 0 else { return nil }
        let (end, overflow) = selection.location.addingReportingOverflow(selection.length)
        guard !overflow else { return nil }
        let range = selection.location..<end
        if let text = field.text(in: range) { return text }
        guard let value = field.value(), range.upperBound <= value.utf16.count else { return nil }
        let units = Array(value.utf16)[range]
        return String(decoding: units, as: UTF16.self)
    }

    /// Writes the text, mapping a failure through `writeFailure(_:after:)`.
    func setSelectedText(_ text: String) throws(TextInsertionError) {
        let start = clock.nanoseconds
        let result = field.setSelectedText(text)
        guard result != .success else { return }
        let elapsed = Duration.nanoseconds(Int64(clamping: clock.nanoseconds &- start))
        throw Self.writeFailure(result, after: elapsed)
    }

    /// A write that timed out may still land, so it is unconfirmed; any other failure is a refusal. See `Docs/insertion.md`.
    static func writeFailure(_ result: AXError, after elapsed: Duration) -> TextInsertionError {
        guard result == .cannotComplete, elapsed >= messagingTimeout else {
            return .insertionRejected(description: "the field refused the text (\(result.rawValue))")
        }
        return .insertionUnconfirmed
    }

    /// Units either side of the selection the no-change check compares.
    static var margin: Int { 64 }

    /// The stretch around the selection the no-change check reads, or `nil` where only the whole value will do.
    private func window(around selection: CFRange?) -> Range<Int>? {
        guard let selection, let length = field.length(), length >= 0,
            selection.length >= 0, (0...length).contains(selection.location)
        else { return nil }
        let (end, endOverflow) = selection.location.addingReportingOverflow(selection.length)
        guard !endOverflow, end <= length else { return nil }
        let (upper, marginOverflow) = end.addingReportingOverflow(Self.margin)
        guard !marginOverflow else { return nil }
        let lower = max(0, selection.location - Self.margin)
        return lower..<min(length, upper)
    }

    /// The field's length and the text in `window`, or its whole value where no window can be read.
    private func snapshot(_ window: Range<Int>?) -> FieldSnapshot? {
        if let window, let length = field.length(), let text = field.text(in: window) {
            return FieldSnapshot(length: length, text: text)
        }
        return field.value().map { FieldSnapshot(length: nil, text: $0) }
    }

    /// Sets the selection, which a field that hides its range refuses.
    private func select(_ range: CFRange) throws(TextInsertionError) {
        let result = field.setSelectedRange(range)
        guard result == .success else {
            throw .insertionRejected(
                description: "the field refused the selection (\(result.rawValue))")
        }
    }
}

/// What the no-change check compares before and after a write.
private struct FieldSnapshot: Equatable {
    /// The field's length in UTF-16 units, or `nil` when `text` is its whole value.
    let length: Int?
    /// The text read.
    let text: String
}
