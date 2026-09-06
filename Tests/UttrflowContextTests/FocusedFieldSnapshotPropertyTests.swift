import Foundation
import Testing

@testable import UttrflowContext

/// Pieces a field's value is built from: plain words, whitespace, newlines, and every kind of character a caret can split.
private let pieces = [
    "a", "git", "commit", " ", " ", "  ", "\t", "\n", "\n", "\r\n", "🐕", "👍🏽", "e\u{301}", "n\u{303}", "नमस्ते",
    "क्ष", "é", "-", "🙏🏽", "\u{1F1EE}\u{1F1F3}",
]

/// One value with one caret, built from a seed.
struct Caret: Sendable, CustomTestStringConvertible {
    let seed: Int
    let value: String
    let selection: NSRange?
    let maxLength: Int

    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        value = (0..<Int.random(in: 0...40, using: &random)).map { _ in random.pick(pieces) }.joined()
        let units = value.utf16.count
        selection =
            random.chance(0.1)
            ? nil
            : NSRange(
                location: Int.random(in: -3...(units + 3), using: &random),
                length: random.chance(0.7) ? 0 : Int.random(in: 1...4, using: &random))
        maxLength = random.pick([0, 1, 5, 11, 40, 400])
    }

    var testDescription: String { "seed \(seed)" }

    func snapshot(in bundleIdentifier: String = "com.example.editor") -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: bundleIdentifier, applicationName: "Editor", role: "AXTextArea", value: value,
            selection: selection)
    }

    /// Where the caret lands: the last character boundary at or before its UTF-16 offset, inside the value.
    var caretIndex: String.Index {
        FocusedFieldSnapshot.index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
    }
}

private let carets = (0..<400).map(Caret.init)

@Suite("Reading the caret's line off random values")
struct FocusedFieldSnapshotPropertyTests {
    @Test(
        "A UTF-16 offset lands on a character boundary, never inside a pair or a combining sequence.",
        arguments: carets)
    func offsetsLandOnCharacters(caret: Caret) {
        let value = caret.value
        for offset in -2...(value.utf16.count + 2) {
            let index = FocusedFieldSnapshot.index(in: value, atUTF16Offset: offset)
            let clamped = min(max(offset, 0), value.utf16.count)
            #expect(String.Index(index, within: value) != nil)
            #expect(index >= value.startIndex && index <= value.endIndex)
            #expect(value.utf16.distance(from: value.startIndex, to: index) <= clamped)
            // The boundary is the nearest one, so the next character begins past the offset.
            if index < value.endIndex {
                #expect(value.utf16.distance(from: value.startIndex, to: value.index(after: index)) > clamped)
            }
        }
    }

    @Test(
        "The current line is the caret's own line up to the caret, without its indentation or any newline.",
        arguments: carets)
    func theLineIsTheCaretsOwn(caret: Caret) {
        let head = caret.value[..<caret.caretIndex]
        let line = head.lastIndex(where: \.isNewline).map { head[head.index(after: $0)...] } ?? head
        let expected = String(line.drop { $0 == " " || $0 == "\t" })
        let current = caret.snapshot().currentLine
        #expect(current == expected)
        let broken = current.contains(where: \.isNewline)
        #expect(!broken)
        #expect(head.hasSuffix(current))
    }

    @Test(
        "A terminal's line is read the same way, with only the prompt taken off, and never carries a newline.",
        arguments: carets)
    func terminalsNeverCrashOrCarryNewlines(caret: Caret) {
        for bundleIdentifier in TerminalApplications.bundleIdentifierPrefixes {
            let current = caret.snapshot(in: bundleIdentifier).currentLine
            let broken = current.contains(where: \.isNewline)
            #expect(!broken)
            #expect(current.count <= caret.value.count)
        }
    }

    @Test(
        "What precedes the line never includes the line, is trimmed at both ends, and fits the allowance.",
        arguments: carets)
    func precedingStopsBeforeTheLine(caret: Caret) {
        let head = caret.value[..<caret.caretIndex]
        let preceding = caret.snapshot().preceding(maxLength: caret.maxLength)
        guard let newline = head.lastIndex(where: \.isNewline) else {
            #expect(preceding == nil)
            return
        }
        var earlier = head[..<newline].suffix(caret.maxLength)
        while earlier.last?.isWhitespace == true { earlier.removeLast() }
        while earlier.first?.isWhitespace == true { earlier.removeFirst() }
        #expect(preceding == (earlier.isEmpty ? nil : String(earlier)))
        guard let preceding else { return }
        #expect(preceding.count <= caret.maxLength)
        #expect(preceding.first?.isWhitespace == false && preceding.last?.isWhitespace == false)
        #expect(head[..<newline].contains(preceding))
    }

    @Test(
        "The caret is at the line's end exactly when only spaces and tabs lie between it and the next newline.",
        arguments: carets)
    func lineEndIsReadForward(caret: Caret) {
        let snapshot = caret.snapshot()
        guard let selection = caret.selection else {
            #expect(!snapshot.caretAtLineEnd)
            return
        }
        let value = caret.value
        var index = FocusedFieldSnapshot.index(
            in: value, atUTF16Offset: selection.location + selection.length)
        var expected = true
        while index < value.endIndex, !value[index].isNewline {
            if value[index] != " " && value[index] != "\t" {
                expected = false
                break
            }
            index = value.index(after: index)
        }
        #expect(snapshot.caretAtLineEnd == expected)
        #expect(snapshot.hasSelection == (selection.length > 0))
    }
}
