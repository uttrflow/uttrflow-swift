import Foundation
import Testing

@testable import UttrflowContext

@Suite("A long field is read only around its caret")
struct ValueWindowTests {
    /// A terminal holding a long scrollback of numbered lines, with a command being typed on the last.
    private static var scrollback: NSString {
        let lines = (1...200_000).map(String.init).joined(separator: "\n")
        return NSString(string: lines + "\n~/src $ git comm")
    }

    /// What the reader keeps when it asks only for a range, and the units the field was asked to copy.
    private static func windowed(
        _ text: NSString, selection: NSRange
    ) -> (value: String?, selection: NSRange?, copied: Int) {
        var copied = 0
        let read = ValueWindow.read(
            count: text.length, selection: selection,
            whole: {
                copied += text.length
                return text as String
            },
            part: { range in
                copied += range.length
                return text.substring(with: range)
            })
        return (read.value, read.selection, copied)
    }

    /// A terminal snapshot of the given value and selection.
    private static func snapshot(_ value: String?, _ selection: NSRange?) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
            value: value, selection: selection)
    }

    @Test("A turn copies a bounded stretch of a long scrollback, and reads the same line from it.")
    func scrollbackIsBounded() {
        let text = Self.scrollback
        let caret = NSRange(location: text.length, length: 0)
        let read = Self.windowed(text, selection: caret)
        #expect(read.copied <= ValueWindow.unitsBefore + ValueWindow.unitsAfter)
        #expect(read.copied < text.length / 50)
        let whole = Self.snapshot(text as String, caret)
        let part = Self.snapshot(read.value, read.selection)
        #expect(part.currentLine == whole.currentLine && !part.currentLine.isEmpty)
        #expect(part.preceding(maxLength: 400) == whole.preceding(maxLength: 400))
        #expect(part.caretAtLineEnd == whole.caretAtLineEnd)
    }

    @Test("A caret in the middle of the scrollback reads the same line and line end as the whole value.")
    func middleCaretMatches() {
        let text = Self.scrollback
        let caret = NSRange(location: text.length / 2, length: 0)
        let read = Self.windowed(text, selection: caret)
        let whole = Self.snapshot(text as String, caret)
        let part = Self.snapshot(read.value, read.selection)
        #expect(read.copied <= ValueWindow.unitsBefore + ValueWindow.unitsAfter)
        #expect(part.currentLine == whole.currentLine && !part.currentLine.isEmpty)
        #expect(part.caretAtLineEnd == whole.caretAtLineEnd)
    }

    @Test("A short value is read whole, as before.")
    func shortValueIsWhole() {
        let text = NSString(string: "~ $ ls -la")
        let caret = NSRange(location: text.length, length: 0)
        let read = Self.windowed(text, selection: caret)
        #expect(read.value == text as String)
        #expect(read.selection == caret)
        #expect(read.copied == text.length)
    }

    @Test("A field that cannot answer for a range is read whole.")
    func unsupportedRangeFallsBack() {
        let text = Self.scrollback
        let caret = NSRange(location: text.length, length: 0)
        let read = ValueWindow.read(
            count: text.length, selection: caret, whole: { text as String }, part: { _ in nil })
        #expect(read.value?.utf16.count == text.length)
        #expect(read.selection == caret)
        let noCount = ValueWindow.read(
            count: nil, selection: caret, whole: { "whole" }, part: { _ in "part" })
        #expect(noCount.value == "whole")
    }

    @Test("A range answer of the wrong length is not trusted.")
    func shortAnswerFallsBack() {
        let text = Self.scrollback
        let caret = NSRange(location: text.length, length: 0)
        let read = ValueWindow.read(
            count: text.length, selection: caret, whole: { "whole" }, part: { _ in "short" })
        #expect(read.value == "whole")
    }
}
