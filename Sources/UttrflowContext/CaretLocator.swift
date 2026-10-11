import CoreGraphics
import Foundation

/// Finds the caret's screen rectangle from whichever of a field's answers holds it. See `Docs/predict-reliability.md`.
enum CaretLocator {
    struct Result: Sendable, Equatable {
        let caret: CGRect
        let direction: WritingDirection
    }

    /// The caret at the selection, or at the text marker alone when the field refuses to say where its selection is; `frame` is the field's own.
    static func caret(
        at selection: (location: Int, length: Int)?, frame: CGRect?, pointSize: CGFloat? = nil,
        value: String? = nil, textSelectionLocation: Int? = nil,
        paragraphDirection: WritingDirection = .unknown,
        bounds: (_ location: Int, _ length: Int) -> CGRect?, markerBounds: () -> CGRect?
    ) -> CGRect? {
        result(
            at: selection, frame: frame, pointSize: pointSize, value: value,
            textSelectionLocation: textSelectionLocation, paragraphDirection: paragraphDirection,
            bounds: bounds, markerBounds: markerBounds
        )?.caret
    }

    static func result(
        at selection: (location: Int, length: Int)?, frame: CGRect?, pointSize: CGFloat? = nil,
        value: String? = nil, textSelectionLocation: Int? = nil,
        paragraphDirection: WritingDirection = .unknown,
        bounds: (_ location: Int, _ length: Int) -> CGRect?, markerBounds: () -> CGRect?
    ) -> Result? {
        if let selection,
            let result = caret(
                inRange: selection, value: value,
                textSelectionLocation: textSelectionLocation ?? selection.location,
                paragraphDirection: paragraphDirection, bounds: bounds)
        {
            return result
        }
        // A web field answers glyph bounds with a zero-size rectangle, but its selection's text-marker range still has a place on screen.
        if let rect = markerBounds(), isLine(rect, in: frame, pointSize: pointSize) {
            return Result(
                caret: CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height),
                direction: paragraphDirection)
        }
        // An editor that draws its own text keeps a one-pixel field at the caret for input methods, so that field's frame is the caret.
        if let frame, FocusedFieldSnapshot.isCaretShaped(frame) {
            return Result(
                caret: CGRect(x: frame.minX, y: frame.minY, width: 0, height: frame.height),
                direction: paragraphDirection)
        }
        return nil
    }

    /// How many times the type size a line may stand, which leaves room for generous line spacing.
    static let linesPerPointSize: CGFloat = 3

    /// The tallest line where the field gives no type size, above any body or heading text.
    static let tallestLineWithoutType: CGFloat = 72

    /// Whether a text-marker rectangle is one line, not the whole field or a block of it, as a rich web editor answers.
    static func isLine(_ rect: CGRect, in frame: CGRect?, pointSize: CGFloat?) -> Bool {
        guard rect.height > 0 else { return false }
        if let frame, !FocusedFieldSnapshot.isCaretShaped(frame), isSame(rect, as: frame) { return false }
        let tallest = pointSize.map { $0 * linesPerPointSize } ?? tallestLineWithoutType
        return rect.height <= tallest
    }

    /// Whether two rectangles are the same to within a point on every edge.
    private static func isSame(_ rect: CGRect, as other: CGRect) -> Bool {
        abs(rect.minX - other.minX) <= 1 && abs(rect.minY - other.minY) <= 1
            && abs(rect.width - other.width) <= 1 && abs(rect.height - other.height) <= 1
    }

    /// The caret read off the glyph beside it, because a zero-length range's own bounds lies.
    private static func caret(
        inRange selection: (location: Int, length: Int), value: String?,
        textSelectionLocation: Int, paragraphDirection: WritingDirection,
        bounds: (_ location: Int, _ length: Int) -> CGRect?
    ) -> Result? {
        if selection.length > 0 {
            let length = followingCharacterLength(in: value, atUTF16Offset: textSelectionLocation) ?? 1
            guard let rect = bounds(selection.location, length), rect.height > 0 else { return nil }
            return Result(
                caret: CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height),
                direction: .unknown)
        }
        let location = selection.location
        // A line break's bounds belong to the line it ends, so use the first glyph on the next line.
        return glyph(
            at: location, value: value, textSelectionLocation: textSelectionLocation,
            paragraphDirection: paragraphDirection, bounds: bounds)
    }

    /// The caret edge beside a single glyph at the selection start.
    private static func glyph(
        at location: Int, value: String? = nil, textSelectionLocation: Int? = nil,
        paragraphDirection: WritingDirection = .unknown,
        bounds: (_ location: Int, _ length: Int) -> CGRect?
    ) -> Result? {
        let textLocation = textSelectionLocation ?? location
        let followsLineBreak = hasLineBreak(beforeUTF16Offset: textLocation, in: value)
        // The caret sits at the trailing edge of the complete character before it, including emoji graphemes.
        let precedingLength = precedingCharacterLength(in: value, beforeUTF16Offset: textLocation) ?? 1
        let before =
            location > 0 && !followsLineBreak
            ? bounds(location - precedingLength, precedingLength) : nil
        let followingLength = followingCharacterLength(in: value, atUTF16Offset: textLocation) ?? 1
        let after = bounds(location, followingLength)
        if let before, before.height > 0, let after, after.height > 0,
            abs(before.minY - after.minY) <= 2, abs(before.maxY - after.maxY) <= 2
        {
            if after.minX >= before.maxX {
                return Result(
                    caret: CGRect(x: before.maxX, y: before.minY, width: 0, height: before.height),
                    direction: .leftToRight)
            }
            if before.minX >= after.maxX {
                return Result(
                    caret: CGRect(x: before.minX, y: before.minY, width: 0, height: before.height),
                    direction: .rightToLeft)
            }
            return Result(
                caret: CGRect(
                    x: min(before.minX, after.minX), y: before.minY, width: 0, height: before.height),
                direction: .unknown)
        }
        // At the start of the value, or just after a line break, use the following glyph.
        if let after, after.height > 0, location == 0 || followsLineBreak {
            return Result(
                caret: CGRect(x: after.minX, y: after.minY, width: 0, height: after.height),
                direction: .unknown)
        }
        if let before, before.height > 0 {
            let x = paragraphDirection == .rightToLeft ? before.minX : before.maxX
            return Result(
                caret: CGRect(x: x, y: before.minY, width: 0, height: before.height),
                direction: paragraphDirection)
        }
        return nil
    }

    /// The UTF-16 length of the complete character immediately before the caret.
    private static func precedingCharacterLength(in text: String?, beforeUTF16Offset offset: Int) -> Int? {
        guard let text, offset > 0 else { return nil }
        let utf16 = text.utf16
        guard offset <= utf16.count,
            let end = String.Index(utf16.index(utf16.startIndex, offsetBy: offset), within: text)
        else { return nil }
        let start = text.index(before: end)
        return text[start..<end].utf16.count
    }

    /// The UTF-16 length of the complete character immediately after the caret.
    private static func followingCharacterLength(in text: String?, atUTF16Offset offset: Int) -> Int? {
        guard let text, offset >= 0 else { return nil }
        let utf16 = text.utf16
        guard offset < utf16.count,
            let start = String.Index(utf16.index(utf16.startIndex, offsetBy: offset), within: text)
        else { return nil }
        return text.index(after: start).utf16Offset(in: text) - offset
    }

    /// Whether the UTF-16 unit before the caret ends a line, matching Accessibility's selection offsets.
    private static func hasLineBreak(beforeUTF16Offset offset: Int, in value: String?) -> Bool {
        guard let value, offset > 0, offset <= value.utf16.count else { return false }
        let index = value.utf16.index(value.utf16.startIndex, offsetBy: offset - 1)
        return switch value.utf16[index] {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
