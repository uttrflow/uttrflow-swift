// Edits text already written into another app's field, by its recorded range and only once the range is verified.
import ApplicationServices
public import UttrflowCore

/// A recorded insertion to edit, and what is known now about the field in front.
public struct EditTarget: Sendable, Equatable {
    /// The span the insertion was confirmed at.
    public let record: InsertionRecord
    /// The field focused now, or `nil` when it cannot be told apart.
    public let focused: FieldIdentity?
    /// Whether the field focused now is a secure field.
    public let isSecure: Bool
    /// The text that must sit just before the span, empty when nothing is checked.
    public let before: String
    /// The text that must sit just after the span, empty when nothing is checked.
    public let after: String

    public init(
        record: InsertionRecord, focused: FieldIdentity?, isSecure: Bool, before: String = "",
        after: String = ""
    ) {
        self.record = record
        self.focused = focused
        self.isSecure = isSecure
        self.before = before
        self.after = after
    }
}

/// What an edit takes out, kept in memory so the edit can be undone while its neighbours are unchanged.
public struct EditUndo: Sendable, Equatable {
    /// How many UTF-16 units either side of the span are checked before an undo writes.
    public static let contextUnits = 32

    /// The span the edit's own text now occupies.
    public let written: InsertionRecord
    /// The text the edit takes out, which an undo puts back.
    public let removed: String
    /// The text just before the span, as the edit leaves it.
    public let before: String
    /// The text just after the span, as the edit leaves it.
    public let after: String

    /// The edit an undo makes, verified against the span and its neighbours.
    public func target(focused: FieldIdentity?, isSecure: Bool) -> EditTarget {
        EditTarget(record: written, focused: focused, isSecure: isSecure, before: before, after: after)
    }
}

// The removed words never reach a log or a crash report through a description.
extension EditUndo: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "EditUndo(\(written.range), \(removed.utf16.count) units removed)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension SelectionWriter {
    /// Replaces the recorded span with `text`, or deletes it when `text` is empty, refusing anything it cannot verify.
    @discardableResult
    func edit(_ target: EditTarget, to text: String) throws(TextInsertionError) -> EditUndo {
        let span = target.record.range
        let (length, caret) = try verified(target)
        let leftOf = spanText(max(0, span.lowerBound - EditUndo.contextUnits)..<span.lowerBound) ?? ""
        let rightOf = spanText(span.upperBound..<min(length, span.upperBound + EditUndo.contextUnits)) ?? ""
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
        let now = InsertionRecord(
            field: target.record.field, range: span.lowerBound..<(span.lowerBound + written), text: text)
        return EditUndo(written: now, removed: target.record.text, before: leftOf, after: rightOf)
    }

    /// Selects the recorded span, refusing anything it cannot verify.
    func select(_ target: EditTarget) throws(TextInsertionError) {
        let span = target.record.range
        _ = try verified(target)
        let range = CFRange(location: span.lowerBound, length: span.count)
        guard field.setSelectedRange(range) == .success, let selected = field.selectedRange(),
            selected.location == range.location, selected.length == range.length
        else {
            throw .insertionRejected(description: "the field will not select the range")
        }
    }

    /// Moves the caret `units` back from the end of the recorded span, staying inside it, refusing what it cannot verify.
    func placeCaret(in target: EditTarget, back units: Int) throws(TextInsertionError) {
        let span = target.record.range
        guard (0...span.count).contains(units) else {
            throw .insertionRejected(description: "the caret would leave the text that was written")
        }
        guard units > 0 else { return }
        _ = try verified(target)
        let place = CFRange(location: span.upperBound - units, length: 0)
        guard field.setSelectedRange(place) == .success, let moved = field.selectedRange(),
            moved.location == place.location, moved.length == 0
        else {
            throw .insertionRejected(description: "the field will not move the caret")
        }
    }

    /// The field's length and caret once the span is proved to still hold its recorded text, untouched.
    private func verified(_ target: EditTarget) throws(TextInsertionError) -> (length: Int, caret: CFRange) {
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
        let beforeRange = (span.lowerBound - target.before.utf16.count)..<span.lowerBound
        let afterRange = span.upperBound..<(span.upperBound + target.after.utf16.count)
        guard beforeRange.lowerBound >= 0, afterRange.upperBound <= length,
            target.before.isEmpty || spanText(beforeRange) == target.before,
            target.after.isEmpty || spanText(afterRange) == target.after
        else {
            throw .insertionRejected(description: "the text around the range differs from what the edit left")
        }
        // The caret at the span's end is the evidence nothing was typed or moved since the write.
        guard let caret = field.selectedRange(), caret.length == 0, caret.location == span.upperBound else {
            throw .insertionRejected(description: "the selection moved since the text was written")
        }
        return (length, caret)
    }

    /// The text a UTF-16 range covers, read by range or cut from the whole value.
    private func spanText(_ span: Range<Int>) -> String? {
        if let text = field.text(in: span) { return text }
        guard let value = field.value(), span.upperBound <= value.utf16.count else { return nil }
        return String(decoding: Array(value.utf16)[span], as: UTF16.self)
    }
}
