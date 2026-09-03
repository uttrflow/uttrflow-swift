import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// One reading, named only by what each test is about.
private func snapshot(
    bundleIdentifier: String = "com.apple.Terminal",
    role: String = "AXTextField",
    identifier: String? = nil,
    placeholder: String? = nil,
    accessibilityDescription: String? = nil,
    value: String? = "git c",
    selection: NSRange? = NSRange(location: 5, length: 0),
    caret: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 16),
    pointSize: CGFloat? = 13,
    isSecure: Bool = false
) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: bundleIdentifier, applicationName: "Terminal", role: role,
        identifier: identifier, placeholder: placeholder,
        accessibilityDescription: accessibilityDescription, value: value, selection: selection,
        caret: caret, pointSize: pointSize, isSecure: isSecure, readMicroseconds: 400)
}

@Suite("What one reading of the focused field says")
struct FocusedFieldSnapshotTests {
    @Test("A field that answers everything takes the inline ghost.")
    func fullyAnsweringFieldsTakeTheGhost() {
        #expect(snapshot().placement == .inlineGhost)
    }

    @Test("A field that hides its styling still takes the inline ghost, in a defaulted font.")
    func noStyleStillTakesTheGhost() {
        #expect(snapshot(pointSize: nil).placement == .inlineGhost)
    }

    @Test("A field that hides its caret leaves only the strip.")
    func noCaretMeansTheStrip() {
        #expect(snapshot(caret: nil).placement == .windowStrip)
    }

    @Test("A field that will not say what it holds can take nothing at all.")
    func nothingToReadMeansNothingDrawn() {
        #expect(snapshot(value: nil).placement == nil)
    }

    @Test("A password field can take nothing, however much else it answers.")
    func secureFieldsTakeNothing() {
        #expect(snapshot(isSecure: true).placement == nil)
    }

    @Test("The reading carries through to the capability the ladder is decided from.")
    func carriesTheReadingThrough() {
        let capability = snapshot(identifier: "search").capability
        #expect(capability.application == "Terminal")
        #expect(capability.locator == "search")
        #expect(capability.readMicroseconds == 400)
    }

    @Test("The locator takes the first name the field publishes.")
    func locatorPrefersTheIdentifier() {
        #expect(snapshot(identifier: "a", placeholder: "b").locator == "a")
        #expect(snapshot(placeholder: "b", accessibilityDescription: "c").locator == "b")
        #expect(snapshot(accessibilityDescription: "c").locator == "c")
        #expect(snapshot().locator == nil)
    }

    @Test("The caret is at the end when nothing follows it.")
    func caretAtTheEnd() {
        #expect(snapshot().caretAtLineEnd)
        #expect(!snapshot(selection: NSRange(location: 2, length: 0)).caretAtLineEnd)
    }

    @Test("A selection reaching the end still counts as the end.")
    func aSelectionToTheEndIsTheEnd() {
        #expect(snapshot(selection: NSRange(location: 1, length: 4)).caretAtLineEnd)
    }

    @Test("A field that says nothing about its caret is not at the end of anything.")
    func noSelectionIsNotTheEnd() {
        #expect(!snapshot(selection: nil).caretAtLineEnd)
        #expect(!snapshot(value: nil).caretAtLineEnd)
    }

    @Test("The end of a line counts as the end, however many lines follow it.")
    func theEndOfALineIsTheEnd() {
        let document = "one\ntwo\nthree"
        #expect(snapshot(value: document, selection: NSRange(location: 3, length: 0)).caretAtLineEnd)
        #expect(snapshot(value: document, selection: NSRange(location: 7, length: 0)).caretAtLineEnd)
        #expect(!snapshot(value: document, selection: NSRange(location: 5, length: 0)).caretAtLineEnd)
    }

    @Test("What a completion continues is the caret's own line, not the whole document.")
    func theLineIsWhatIsTyped() {
        let document = "Deploy the notes\nThe quick brown fox\nThe qui"
        #expect(
            snapshot(value: document, selection: NSRange(location: 44, length: 0)).currentLine == "The qui")
        #expect(snapshot(value: document, selection: NSRange(location: 22, length: 0)).currentLine == "The q")
        #expect(
            snapshot(value: document, selection: NSRange(location: 16, length: 0)).currentLine
                == "Deploy the notes")
    }

    @Test("A field with no newline in it is all one line.")
    func oneLineIsTheWholeValue() {
        #expect(snapshot().currentLine == "git c")
        #expect(snapshot(value: nil).currentLine.isEmpty)
    }

    @Test("An indented line drops its leading whitespace, so it matches what capture stored.")
    func indentationIsDropped() {
        let indented = "    git status"
        #expect(
            snapshot(value: indented, selection: NSRange(location: indented.utf16.count, length: 0))
                .currentLine == "git status")
        // A tab-indented continuation line, up to the caret, is trimmed the same way.
        let block = "def run():\n\tgit status"
        #expect(
            snapshot(value: block, selection: NSRange(location: block.utf16.count, length: 0))
                .currentLine == "git status")
    }

    @Test("Whitespace typed after the content is kept, so accepting does not double a space.")
    func trailingWhitespaceIsKept() {
        #expect(
            snapshot(value: "git ", selection: NSRange(location: 4, length: 0)).currentLine == "git ")
    }

    @Test("A caret at the very start, and one just after a newline, are both on an empty line.")
    func anEmptyLineIsEmpty() {
        #expect(snapshot(value: "one\ntwo", selection: NSRange(location: 0, length: 0)).currentLine.isEmpty)
        #expect(snapshot(value: "one\ntwo", selection: NSRange(location: 4, length: 0)).currentLine.isEmpty)
        #expect(snapshot(value: "one\n", selection: NSRange(location: 4, length: 0)).currentLine.isEmpty)
    }

    @Test("A field that will not say where its caret is is read to the end of what it holds.")
    func noCaretReadsToTheEnd() {
        #expect(snapshot(value: "one\ntwo", selection: nil).currentLine == "two")
    }

    @Test("A caret counted in UTF-16 lands where the characters are, not where the code units are.")
    func caretOffsetsAreUTF16() {
        #expect(snapshot(value: "🐕 wag", selection: NSRange(location: 6, length: 0)).currentLine == "🐕 wag")
        #expect(snapshot(value: "🐕 wag", selection: NSRange(location: 2, length: 0)).currentLine == "🐕")
        #expect(
            snapshot(value: "e\u{301}clair", selection: NSRange(location: 3, length: 0)).currentLine
                == "\u{e9}c")
    }

    @Test("A caret inside one character is read as being before it, so no character is cut in half.")
    func aSplitCharacterIsNotCut() {
        #expect(snapshot(value: "🐕 wag", selection: NSRange(location: 1, length: 0)).currentLine.isEmpty)
        #expect(
            snapshot(value: "e\u{301}clair", selection: NSRange(location: 1, length: 0)).currentLine.isEmpty)
        #expect(!snapshot(value: "e\u{301}clair", selection: NSRange(location: 1, length: 0)).caretAtLineEnd)
    }

    @Test("A caret beyond what the field holds is read as being at its end.")
    func aCaretPastTheEndIsTheEnd() {
        #expect(snapshot(value: "one", selection: NSRange(location: 99, length: 0)).currentLine == "one")
        #expect(snapshot(value: "one", selection: NSRange(location: -1, length: 0)).currentLine.isEmpty)
    }

    @Test("Selected text is text the next keystroke would replace.")
    func selectionIsNoticed() {
        #expect(snapshot(selection: NSRange(location: 0, length: 5)).hasSelection)
        #expect(!snapshot().hasSelection)
        #expect(!snapshot(selection: nil).hasSelection)
    }

    @Test("A multi-line field is the only one that reads as prose.")
    func onlyTextAreasAreProse() {
        #expect(
            snapshot(bundleIdentifier: "com.example.editor", role: FocusedFieldSnapshot.proseRole)
                .isProse)
        #expect(!snapshot(bundleIdentifier: "com.example.editor").isProse)
    }

    @Test("A terminal's line is what was typed at the prompt, not the prompt the shell drew.")
    func aTerminalLineDropsThePrompt() {
        let prompt = "(experiments) naveenbhatt@Naveens-MacBook-Pro-2 experiments % sud"
        for bundleIdentifier in TerminalApplications.bundleIdentifiers {
            #expect(
                snapshot(bundleIdentifier: bundleIdentifier, value: prompt, selection: nil)
                    .currentLine == "sud")
        }
    }

    @Test("Only the caret's own line has a prompt taken off it, and only in a terminal.")
    func onlyTerminalsDropThePrompt() {
        let scrollback = "user@host:~/dir$ git status\nuser@host:~/dir$ git a"
        #expect(snapshot(value: scrollback, selection: nil).currentLine == "git a")
        #expect(
            snapshot(bundleIdentifier: "com.example.editor", value: "user@host:~/dir$ git a", selection: nil)
                .currentLine == "user@host:~/dir$ git a")
    }

    @Test("A terminal line holding only a prompt is empty, so nothing is captured from it.")
    func anEmptyPromptCapturesNothing() {
        #expect(
            snapshot(value: "naveenbhatt@Naveens-MacBook-Pro-2 experiments % ", selection: nil)
                .currentLine.isEmpty)
    }

    @Test("A terminal publishes the prose role and is still not prose, so it answers at once.")
    func terminalsAreNeverProse() {
        for bundleIdentifier in TerminalApplications.bundleIdentifiers {
            #expect(
                !snapshot(bundleIdentifier: bundleIdentifier, role: FocusedFieldSnapshot.proseRole)
                    .isProse)
        }
    }
}
