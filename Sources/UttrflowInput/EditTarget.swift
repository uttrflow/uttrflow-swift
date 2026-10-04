// Edits text already written into another app's field, by its recorded range and only once the range is verified.
import ApplicationServices
import UttrflowCore

/// A recorded insertion to edit, and what is known now about the field in front.
public struct EditTarget: Sendable, Equatable {
    /// The span the insertion was confirmed at.
    public let record: InsertionRecord
    /// The field focused now, or `nil` when it cannot be told apart.
    public let focused: FieldIdentity?
    /// Whether the field focused now is a secure field.
    public let isSecure: Bool

    public init(record: InsertionRecord, focused: FieldIdentity?, isSecure: Bool) {
        self.record = record
        self.focused = focused
        self.isSecure = isSecure
    }
}

extension SelectionWriter {
    /// Replaces the recorded span with `text`, or deletes it when `text` is empty, refusing anything it cannot verify.
    func edit(_ target: EditTarget, to text: String) throws(TextInsertionError) {
        let span = target.record.range
        guard !target.isSecure else {
            throw .insertionRejected(description: "the field is a secure field")
        }
        guard target.focused == target.record.field else {
            throw .insertionRejected(description: "the field in front is not where the text was written")
        }
        guard let length = field.length() ?? field.value()?.utf16.count, span.upperBound <= length else {
            throw .insertionRejected(description: "the field will not report the range")
        }
        guard spanText(span) == target.record.text else {
            throw .insertionRejected(description: "the text at the range is no longer what was written")
        }
        // The caret at the span's end is the evidence nothing was typed or moved since the write.
        guard let caret = field.selectedRange(), caret.length == 0, caret.location == span.upperBound else {
            throw .insertionRejected(description: "the selection moved since the text was written")
        }
        let range = CFRange(location: span.lowerBound, length: span.count)
        guard field.setSelectedRange(range) == .success, let selected = field.selectedRange(),
            selected.location == range.location, selected.length == range.length
        else {
            throw .insertionRejected(description: "the field will not select the range")
        }
        do {
            try setSelectedText(text)
        } catch {
            // A write that may still land is left alone, since moving the selection could misplace it.
            if error != .insertionUnconfirmed { _ = field.setSelectedRange(caret) }
            throw error
        }
        let written = text.utf16.count
        guard let after = field.selectedRange(), after.length == 0,
            after.location == span.lowerBound + written,
            field.length() ?? field.value()?.utf16.count == length - span.count + written
        else { throw .insertionUnconfirmed }
    }

    /// The text a UTF-16 range covers, read by range or cut from the whole value.
    private func spanText(_ span: Range<Int>) -> String? {
        if let text = field.text(in: span) { return text }
        guard let value = field.value(), span.upperBound <= value.utf16.count else { return nil }
        return String(decoding: Array(value.utf16)[span], as: UTF16.self)
    }
}
