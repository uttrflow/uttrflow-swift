import Testing

@testable import UttrflowContext
@testable import UttrflowCore

@Suite("CaretText")
struct CaretTextTests {
    @Test("splits the field at an empty selection")
    func splitsAtCaret() {
        let sides = CaretText.around("hello world", selection: 5..<5)
        #expect(sides == CaretText.Sides(preceding: "hello", following: " world"))
    }

    @Test("leaves the selected text out of both sides")
    func skipsSelection() {
        let sides = CaretText.around("hello brave world", selection: 6..<11)
        #expect(sides == CaretText.Sides(preceding: "hello ", following: " world"))
    }

    @Test("knows nothing when the field reports no value or no selection")
    func nothingWithoutBoth() {
        #expect(CaretText.around(nil, selection: 0..<0) == nil)
        #expect(CaretText.around("hello", selection: nil) == nil)
    }

    @Test("an empty field is an empty start, not nothing")
    func emptyField() {
        #expect(CaretText.around("", selection: 0..<0) == CaretText.Sides(preceding: "", following: ""))
    }

    @Test("clamps a selection the field reported past its own ends")
    func clamps() {
        #expect(
            CaretText.around("hello", selection: 9..<12)
                == CaretText.Sides(preceding: "hello", following: ""))
        #expect(
            CaretText.around("hello", selection: -3..<2)
                == CaretText.Sides(preceding: "", following: "llo"))
        #expect(
            CaretText.around("hello", selection: -3..<(-1))
                == CaretText.Sides(preceding: "", following: "hello"))
    }

    @Test("cuts each side to the limit the insertion point keeps")
    func limits() {
        let long = String(repeating: "a", count: 500) + "|" + String(repeating: "b", count: 500)
        let sides = CaretText.around(long, selection: 500..<501)
        #expect(sides?.preceding.count == InsertionPoint.precedingLimit)
        #expect(sides?.following.count == InsertionPoint.followingLimit)
        #expect(sides?.preceding.allSatisfy { $0 == "a" } == true)
        #expect(sides?.following.allSatisfy { $0 == "b" } == true)
    }

    @Test("bounds a long combining sequence by UTF-16 units before the caret")
    func boundsLongCombiningSequenceBeforeCaret() {
        let cluster = "a" + String(repeating: "\u{301}", count: 400)
        let sides = CaretText.around(cluster + "|", selection: cluster.utf16.count..<cluster.utf16.count + 1)

        #expect(sides?.preceding.utf16.count == InsertionPoint.precedingLimit)
        #expect(sides?.preceding.unicodeScalars.allSatisfy { $0.value == 0x301 } == true)
    }

    @Test("bounds a long combining sequence by UTF-16 units after the selection")
    func boundsLongCombiningSequenceAfterSelection() {
        let cluster = "a" + String(repeating: "\u{301}", count: 200)
        let sides = CaretText.around("|" + cluster, selection: 1..<1)

        #expect(sides?.following.utf16.count == InsertionPoint.followingLimit)
        #expect(sides?.following.unicodeScalars.first?.value == 0x61)
        #expect(sides?.following.unicodeScalars.dropFirst().allSatisfy { $0.value == 0x301 } == true)
    }

    @Test("keeps surrogate pairs whole when a UTF-16 limit falls inside one")
    func keepsSurrogatePairsWholeAtLimits() {
        let before = "😀" + String(repeating: "a", count: InsertionPoint.precedingLimit - 1) + "|"
        let after = "|" + String(repeating: "a", count: InsertionPoint.followingLimit - 1) + "😀tail"
        let beforeSides = CaretText.around(before, selection: before.utf16.count - 1..<before.utf16.count)
        let afterSides = CaretText.around(after, selection: 1..<1)

        #expect(beforeSides?.preceding == String(repeating: "a", count: InsertionPoint.precedingLimit - 1))
        #expect(afterSides?.following == String(repeating: "a", count: InsertionPoint.followingLimit - 1))
    }

    @Test("counts the selection in UTF-16 units, the way Accessibility reports it")
    func utf16Offsets() {
        let text = "😀 hello"
        #expect(
            CaretText.around(text, selection: 2..<2) == CaretText.Sides(preceding: "😀", following: " hello"))
        #expect(CaretText.around(text, selection: 1..<1)?.following.hasSuffix(" hello") == true)
    }

    /// Reads a terminal screen with the caret at its end, as a shell prompt waiting for input leaves it.
    private func terminalSides(_ screen: String, title: String? = "zsh") -> CaretText.Sides? {
        CaretText.inTerminal(screen, selection: screen.utf16.count..<screen.utf16.count, windowTitle: title)
    }

    @Test("passes on only the shell input, never an open bracket in scrollback or the prompt")
    func terminalDropsScrollbackAndPrompt() {
        let screen = "sample@devbox ~/demo % echo foo(\nfoo(: no such command\nsample@devbox ~/demo % git st"
        #expect(terminalSides(screen) == CaretText.Sides(preceding: "git st", following: ""))
    }

    @Test("reads only the input after a multi-line prompt's last line")
    func terminalMultiLinePrompt() {
        let screen = "make: done [\n~/demo on trunk\n❯ ls -la"
        #expect(terminalSides(screen)?.preceding == "ls -la")
    }

    @Test("gives no edges inside a heredoc body")
    func terminalHeredocBody() {
        #expect(terminalSides("~/demo $ cat <<EOF\nfirst (line\nsecond") == nil)
    }

    @Test("gives no edges where a full-screen program holds the screen")
    func terminalFullScreenProgram() {
        #expect(terminalSides("~/demo $ ls", title: "vim notes.txt") == nil)
    }

    @Test("keeps the rest of the caret's row and nothing below it")
    func terminalFollowingRow() {
        let screen = "~/demo $ git log\nolder output"
        #expect(
            CaretText.inTerminal(screen, selection: 12..<12, windowTitle: nil)
                == CaretText.Sides(preceding: "git", following: " log"))
    }

    @Test("gives no edges without a value or a selection")
    func terminalUnanswered() {
        #expect(CaretText.inTerminal(nil, selection: 0..<0, windowTitle: nil) == nil)
        #expect(CaretText.inTerminal("~/demo $ ls", selection: nil, windowTitle: nil) == nil)
    }

    @Test("gives no edges when the caret's row is too long to read whole")
    func terminalCutRow() {
        #expect(terminalSides(String(repeating: "x", count: FocusedFieldSnapshot.lineReadLimit + 1)) == nil)
    }
}
