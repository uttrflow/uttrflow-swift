import CoreGraphics
import Foundation
import Testing

import UttrflowCore
import UttrflowPredict

@testable import UttrflowContext

/// One reading, named only by what each test is about.
private func snapshot(
    bundleIdentifier: String = "com.apple.Terminal",
    role: String = "AXTextField",
    identifier: String? = nil,
    placeholder: String? = nil,
    accessibilityDescription: String? = nil,
    title: String? = nil,
    value: String? = "git c",
    selection: NSRange? = NSRange(location: 5, length: 0),
    caret: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 16),
    pointSize: CGFloat? = 13,
    fontFamily: String? = nil,
    textColor: TextColor? = nil,
    isSecure: Bool = false,
    isEnabled: Bool? = nil,
    isEditable: Bool? = nil,
    writingDirection: WritingDirection = .unknown
) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: bundleIdentifier, applicationName: "Terminal", role: role,
        identifier: identifier, placeholder: placeholder,
        accessibilityDescription: accessibilityDescription, title: title,
        value: value, selection: selection,
        caret: caret, writingDirection: writingDirection, pointSize: pointSize, fontFamily: fontFamily,
        textColor: textColor,
        isSecure: isSecure, isEnabled: isEnabled, isEditable: isEditable,
        readMicroseconds: 400)
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

    @Test("A field that hides its caret can take nothing, because nothing is drawn off the line.")
    func noCaretMeansNothingDrawn() {
        #expect(snapshot(caret: nil).placement == nil)
    }

    @Test("A field that will not say what it holds can take nothing at all.")
    func nothingToReadMeansNothingDrawn() {
        #expect(snapshot(value: nil).placement == nil)
    }

    @Test("A password field can take nothing, however much else it answers.")
    func secureFieldsTakeNothing() {
        #expect(snapshot(isSecure: true).placement == nil)
    }

    @Test("A secret named only in the title is secure before its value is carried")
    func titleCanDeclareASecret() {
        let field = snapshot(title: "Card number")
        #expect(field.isSecure)
        #expect(field.value == nil)
        #expect(field.fieldLabel == nil)
        #expect(field.placement == nil)
    }

    @Test("Credential prompts in terminals hide their reply from the current line")
    func credentialPromptsAreSecure() {
        let prompts = [
            "[sudo] password for dev: hidden-reply",
            "dev@example.test's password: hidden-reply",
            "Enter passphrase for key '/Users/example/.ssh/id_ed25519': hidden-reply",
            "Enter passphrase: hidden-reply",
            "Enter code: hidden-reply",
            "Enter token: hidden-reply",
            "PIN: hidden-reply",
            "Security token: hidden-reply",
            "Password for admin: hidden-reply",
        ]

        for prompt in prompts {
            let terminal = snapshot(
                value: prompt, selection: NSRange(location: prompt.utf16.count, length: 0))
            #expect(terminal.isSecure, "prompt: \(prompt)")
            #expect(terminal.value == nil, "prompt: \(prompt)")
            #expect(terminal.currentLine.isEmpty, "prompt: \(prompt)")
            let context = PredictionContext(typed: terminal.currentLine, isSecure: terminal.isSecure)
            #expect(Quieting.reason(context) == .secureField, "prompt: \(prompt)")
        }
    }

    @Test("Credential-looking commands remain ordinary terminal input")
    func credentialCommandsRemainReadable() {
        let lines = [
            "echo 'Password: example'",
            "code src/App.swift:42",
            "Code: review",
            "echo bob's password: x",
            "bob's password manager: x",
        ]

        for line in lines {
            let terminal = snapshot(value: line, selection: NSRange(location: line.utf16.count, length: 0))
            #expect(!terminal.isSecure, "line: \(line)")
            #expect(terminal.currentLine == line, "line: \(line)")
        }
    }

    @Test("A field reported disabled cannot host a suggestion")
    func disabledFieldsTakeNothing() {
        #expect(snapshot(isEnabled: false).placement == nil)
        #expect(snapshot(isEditable: false).placement == nil)
        #expect(snapshot(isEnabled: true).placement == .inlineGhost)
        #expect(snapshot(isEnabled: nil).placement == .inlineGhost)
    }

    @Test("An unknown direction defaults to left-to-right placement without disabling right-to-left fields.")
    func unknownWritingDirectionDoesNotBlockPlacement() {
        #expect(snapshot(writingDirection: .unknown).placement == .inlineGhost)
        #expect(snapshot(writingDirection: .leftToRight).placement == .inlineGhost)
        #expect(snapshot(writingDirection: .rightToLeft).placement == .inlineGhost)
        #expect(snapshot(isEnabled: false, writingDirection: .unknown).placement == nil)
        #expect(snapshot(isEditable: false, writingDirection: .rightToLeft).placement == nil)
    }

    @Test("The reading carries through to the capability the ladder is decided from.")
    func carriesTheReadingThrough() {
        let capability = snapshot(identifier: "search").capability
        #expect(capability.application == "Terminal")
        #expect(capability.locator == "search")
        #expect(capability.readMicroseconds == 400)
    }

    @Test("A field that gives only a family, or only a colour, is still reported as answering its type.")
    func anyOneTypeAnswerCountsAsStyle() {
        #expect(snapshot(pointSize: nil, fontFamily: "Menlo").capability.reportsTextStyle)
        #expect(
            snapshot(pointSize: nil, textColor: .init(red: 0, green: 0, blue: 0))
                .capability.reportsTextStyle)
        #expect(!snapshot(pointSize: nil).capability.reportsTextStyle)
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

    @Test("Only whitespace ahead still counts as the line's end, as a terminal pads the line with spaces.")
    func whitespaceAheadIsStillTheEnd() {
        // A terminal's value: the input, then spaces to the window width, then the next grid row.
        let padded = "ls" + String(repeating: " ", count: 40) + "\n" + String(repeating: " ", count: 42)
        #expect(snapshot(value: padded, selection: NSRange(location: 2, length: 0)).caretAtLineEnd)
        // Real text ahead, not padding, is still the caret sitting inside the line.
        #expect(!snapshot(value: "ls  -la", selection: NSRange(location: 2, length: 0)).caretAtLineEnd)
    }

    @Test("Code and SQL completions can sit inside an editor's auto-closed pair.")
    func autoClosedPairsKeepCodeAndSQLSuggestionsAvailable() {
        let examples = [
            ("com.microsoft.vscode", "COUNT()", "COUNT("),
            (
                "com.jetbrains.datagrip", "SELECT * FROM users WHERE name = ''",
                "SELECT * FROM users WHERE name = '"
            ),
        ]
        for (bundleIdentifier, value, typed) in examples {
            let reading = snapshot(
                bundleIdentifier: bundleIdentifier,
                role: FocusedFieldSnapshot.proseRole,
                value: value,
                selection: NSRange(location: typed.utf16.count, length: 0))
            #expect(reading.currentLine == typed)
            #expect(reading.caretAtLineEnd)
            #expect(reading.hasTextAfterCaret)
            #expect(reading.learnableLine.isEmpty)
            #expect(
                Quieting.reason(
                    PredictionContext(
                        typed: reading.currentLine, caretAtLineEnd: reading.caretAtLineEnd,
                        isProse: reading.isProse)) == nil)
        }
    }

    @Test("Every supported auto-closed delimiter can follow a completion caret.")
    func closingDelimitersCountAsCompletionEnd() {
        for closer in [")", "]", "}", "'", "\"", "`"] {
            let typed = "value"
            let reading = snapshot(
                bundleIdentifier: "com.microsoft.vscode", value: typed + closer,
                selection: NSRange(location: typed.utf16.count, length: 0))

            #expect(reading.caretAtLineEnd, "\(closer)")
            #expect(reading.hasTextAfterCaret, "\(closer)")
        }
    }

    @Test("Accepting a completion leaves matching auto-closed punctuation in the editor.")
    func completionDoesNotDuplicateAutoClosedPunctuation() {
        let typed = "print(\"hel"
        let autoClosed = "\")"
        let reading = snapshot(
            bundleIdentifier: "com.microsoft.vscode", role: FocusedFieldSnapshot.proseRole,
            value: typed + autoClosed, selection: NSRange(location: typed.utf16.count, length: 0))
        let suggestion = Suggestion.certain("print(\"hello world\")")
            .trimmed(after: typed, matching: reading.closingPunctuationAfterCaret)

        #expect(reading.closingPunctuationAfterCaret == "\")")
        #expect(suggestion.accepting == "print(\"hello world")
        #expect(suggestion.edit(after: typed)?.inserted == "lo world")
        let inserted = suggestion.edit(after: typed)?.inserted ?? ""
        #expect(typed + inserted + autoClosed == "print(\"hello world\")")
    }

    @Test("A real code caret inside following text still silences suggestions.")
    func codeCaretBeforeAnotherTokenIsNotAtLineEnd() {
        let typed = "let result = "
        let reading = snapshot(
            bundleIdentifier: "com.microsoft.vscode", role: FocusedFieldSnapshot.proseRole,
            value: typed + "other()", selection: NSRange(location: typed.utf16.count, length: 0))

        #expect(!reading.caretAtLineEnd)
        #expect(
            Quieting.reason(
                PredictionContext(
                    typed: reading.currentLine, caretAtLineEnd: reading.caretAtLineEnd)) == .caretInsideText)
    }

    @Test("Text after a terminal caret stays text even when a prompt-like tail follows padding.")
    func paddedTerminalTailIsStillTextAfterTheCaret() {
        let row =
            "git c" + String(repeating: " ", count: 30) + "main 12:04\n" + String(repeating: " ", count: 45)
        let reading = snapshot(value: row, selection: NSRange(location: 5, length: 0))
        #expect(!reading.caretAtLineEnd)
        #expect(reading.rightPromptGap == 30)
        // A document also treats the padded tail as text after the caret.
        #expect(!snapshot(bundleIdentifier: "com.apple.TextEdit", value: row).caretAtLineEnd)
    }

    @Test("Four spaces before command text do not turn an interior caret into the line end.")
    func spacedCommandTextAfterTheCaretIsStillText() {
        let value = "ls -la    # list"
        let reading = snapshot(
            bundleIdentifier: "com.apple.Terminal", value: value,
            selection: NSRange(location: "ls -la".utf16.count, length: 0))
        #expect(!reading.caretAtLineEnd)
        #expect(reading.hasTextAfterCaret)
        let context = PredictionContext(typed: reading.currentLine, caretAtLineEnd: reading.caretAtLineEnd)
        #expect(Quieting.reason(context) == .caretInsideText)
    }

    @Test("Text directly after the caret, with no padding run, is still the caret inside the line.")
    func textDirectlyAfterTheCaretRefuses() {
        let reading = snapshot(
            value: "git commit -m x" + String(repeating: " ", count: 30) + "main",
            selection: NSRange(location: 3, length: 0))
        #expect(!reading.caretAtLineEnd)
        #expect(reading.rightPromptGap == nil)
    }

    @Test("The ghost's field ends before a padded terminal tail, and is the whole field otherwise.")
    func ghostFieldStopsBeforePaddedTerminalText() throws {
        let field = CGRect(x: 0, y: 0, width: 800, height: 400)
        let row = "git c" + String(repeating: " ", count: 11) + "main"
        let reading = FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
            value: row, selection: NSRange(location: 5, length: 0),
            caret: CGRect(x: 40, y: 20, width: 1, height: 16), field: field, pointSize: 10)
        let ghost = try #require(reading.ghostField)
        #expect(abs(ghost.maxX - (41 + 10 * 10 * FocusedFieldSnapshot.monospacedAdvance)) < 0.001)
        let plain = FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
            value: "git c", selection: NSRange(location: 5, length: 0),
            caret: CGRect(x: 40, y: 20, width: 1, height: 16), field: field, pointSize: 10)
        #expect(plain.ghostField == field)
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

    @Test("What came before the caret's line is handed on as context, most recent part first to go, trimmed.")
    func precedingTextIsTheEarlierLines() {
        let document = "Deploy the notes\nThe quick brown fox  \n  The qui"
        let caret = NSRange(location: document.utf16.count, length: 0)
        #expect(
            snapshot(value: document, selection: caret).preceding(maxLength: 400)
                == "Deploy the notes\nThe quick brown fox")
        #expect(snapshot(value: document, selection: caret).preceding(maxLength: 11) == "brown fox")
        let firstLine = snapshot(value: document, selection: NSRange(location: 16, length: 0))
        #expect(firstLine.preceding(maxLength: 400) == nil)
    }

    @Test("A single line, an empty field and whitespace-only earlier lines give no context at all.")
    func nothingBeforeMeansNoContext() {
        #expect(snapshot().preceding(maxLength: 400) == nil)
        #expect(snapshot(value: nil).preceding(maxLength: 400) == nil)
        let blankAbove = snapshot(value: "   \n\nls", selection: NSRange(location: 7, length: 0))
        #expect(blankAbove.preceding(maxLength: 400) == nil)
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

    @Test("Known editors are not prose even when their field is a text area.")
    func knownEditorsAreNotProse() {
        for bundleIdentifier in [
            "org.jkiss.dbeaver.core.product", "com.jetbrains.datagrip", "com.microsoft.VSCode",
        ] {
            #expect(
                !snapshot(bundleIdentifier: bundleIdentifier, role: FocusedFieldSnapshot.proseRole)
                    .isProse)
        }
        #expect(
            snapshot(bundleIdentifier: "com.example.editor", role: FocusedFieldSnapshot.proseRole).isProse)
    }

    @Test("A terminal's line is what was typed at the prompt, not the prompt the shell drew.")
    func aTerminalLineDropsThePrompt() {
        let prompt = "(experiments) user@host experiments % sud"
        for bundleIdentifier in TerminalApplications.bundleIdentifierPrefixes {
            #expect(
                snapshot(bundleIdentifier: bundleIdentifier, value: prompt, selection: nil)
                    .currentLine == "sud")
        }
    }

    @Test("A heredoc body is not treated as a shell command.")
    func terminalHeredocBodyIsNotACommand() {
        let value = "user@host:~/dir$ cat <<'DONE'\nrm -rf /some/path"
        #expect(
            snapshot(value: value, selection: NSRange(location: value.utf16.count, length: 0))
                .currentLine.isEmpty)
    }

    @Test("Suggestions resume after a heredoc delimiter line.")
    func terminalHeredocEndsAtItsDelimiter() {
        let value = "cat <<-\"DONE\"\nrm -rf /some/path\nDONE"
        #expect(
            snapshot(value: value, selection: NSRange(location: value.utf16.count, length: 0))
                .currentLine == "DONE")
    }

    @Test("A spaced heredoc operator suppresses suggestions until its delimiter.")
    func terminalHeredocAllowsWhitespaceBeforeItsDelimiter() {
        let unquoted = "cat << EOF\nrm -rf /some/path"
        #expect(
            snapshot(value: unquoted, selection: NSRange(location: unquoted.utf16.count, length: 0))
                .currentLine.isEmpty)
        let quoted = "cat << 'END TAG'\nrm -rf /some/path\nEND TAG"
        #expect(
            snapshot(value: quoted, selection: NSRange(location: quoted.utf16.count, length: 0))
                .currentLine == "END TAG")
    }

    @Test("Indented heredoc delimiters close only with the opener's indentation rule.")
    func terminalHeredocHonorsIndentedDelimiters() {
        let tabs = "cat <<-DONE\nrm -rf /some/path\n\tDONE"
        #expect(
            snapshot(value: tabs, selection: NSRange(location: tabs.utf16.count, length: 0))
                .currentLine == "DONE")
        let spaces = "cat <<~SQL\nrm -rf /some/path\n    SQL"
        #expect(
            snapshot(value: spaces, selection: NSRange(location: spaces.utf16.count, length: 0))
                .currentLine == "SQL")
        let spaced = "cat <<'END TAG'\nrm -rf /some/path\nEND TAG"
        #expect(
            snapshot(value: spaced, selection: NSRange(location: spaced.utf16.count, length: 0))
                .currentLine == "END TAG")
    }

    @Test("A heredoc-looking token inside a quoted argument does not start a heredoc.")
    func quotedHeredocTextDoesNotSuppressSuggestions() {
        let value = "printf 'literal <<DONE'\nrm -rf /some/path"
        #expect(
            snapshot(value: value, selection: NSRange(location: value.utf16.count, length: 0))
                .currentLine == "rm -rf /some/path")
    }

    @Test("A shell here-string is not parsed as a heredoc.")
    func hereStringDoesNotSuppressSuggestions() {
        let value = "printf <<< 'literal'\nrm -rf /some/path"
        #expect(
            snapshot(value: value, selection: NSRange(location: value.utf16.count, length: 0))
                .currentLine == "rm -rf /some/path")
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
            snapshot(value: "user@host experiments % ", selection: nil)
                .currentLine.isEmpty)
    }

    @Test("A terminal publishes the prose role and is still not prose, so it answers at once.")
    func terminalsAreNeverProse() {
        for bundleIdentifier in TerminalApplications.bundleIdentifierPrefixes {
            #expect(
                !snapshot(bundleIdentifier: bundleIdentifier, role: FocusedFieldSnapshot.proseRole)
                    .isProse)
        }
    }

    @Test(
        "A one-pixel field one line tall is the caret an editor parked its input field at; a real field or a collapsed one is not."
    )
    func aHiddenInputFieldIsTheCaret() {
        #expect(FocusedFieldSnapshot.isCaretShaped(CGRect(x: 682, y: 239, width: 1, height: 21)))
        #expect(FocusedFieldSnapshot.isCaretShaped(CGRect(x: 0, y: 0, width: 0, height: 16)))
        #expect(!FocusedFieldSnapshot.isCaretShaped(CGRect(x: 0, y: 0, width: 400, height: 21)))
        #expect(!FocusedFieldSnapshot.isCaretShaped(CGRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(!FocusedFieldSnapshot.isCaretShaped(CGRect(x: 0, y: 0, width: 1, height: 900)))
    }

    @Test("Only a role text is entered into is taken for the field, never the word or group under the caret.")
    func onlyTextEntryRolesAreTheField() {
        #expect(FocusedFieldSnapshot.isTextEntry("AXTextArea"))
        #expect(FocusedFieldSnapshot.isTextEntry("AXTextField"))
        #expect(FocusedFieldSnapshot.isTextEntry("AXComboBox"))
        #expect(!FocusedFieldSnapshot.isTextEntry("AXStaticText"))
        #expect(!FocusedFieldSnapshot.isTextEntry("AXGroup"))
        #expect(!FocusedFieldSnapshot.isTextEntry(nil))
    }
}

/// A terminal reading of one line with the caret at its end, under a window title.
private func terminalLine(_ line: String, title: String) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea", value: line,
        selection: NSRange(location: line.utf16.count, length: 0),
        caret: CGRect(x: 10, y: 20, width: 1, height: 16),
        pointSize: 13, readMicroseconds: 400, windowTitle: title)
}

@Suite("A terminal whose screen a full-screen program holds")
struct FullScreenProgramTests {
    @Test(
        "An fzf query or an editor's buffer line gets no ghost and is never read as a command.",
        arguments: [
            ("> git st", "tools — fzf — 80×24"), ("git sta", "tools — vim deploy.sh — 80×24"),
            ("make te", "tools — nvim — 120×40"), ("> git st", "fzf"), ("git sta", "tools — less — 80×24"),
        ])
    func programLinesAreLeftAlone(_ line: String, _ title: String) {
        let reading = terminalLine(line, title: title)
        #expect(reading.placement == nil, "\(title)")
        #expect(reading.currentLine.isEmpty, "\(title)")
        #expect(reading.learnableLine.isEmpty, "\(title)")
    }

    @Test("The same lines at the shell are read and may take the ghost.")
    func shellLinesStillWork() {
        let reading = terminalLine("user@host tools % git st", title: "tools — -zsh — 80×24")
        #expect(reading.placement == .inlineGhost)
        #expect(reading.currentLine == "git st")
        #expect(terminalLine("➜  vimrc git sta", title: "vimrc — -zsh — 80×24").currentLine == "git sta")
    }

    @Test(
        "A listed word that is only the directory, host or tab name leaves the shell prompt readable.",
        arguments: [
            "watch — -zsh — 80×24", "view — -zsh — 80×24", "top — bash — 120×40", "man — fish — 80×24",
            "less (-zsh)", "watch (zsh)", "me@top: ~/src/watch", "~/notes/view", "me@view: ~",
        ])
    func directoryWordsAreNotThePrograms(_ title: String) {
        let reading = terminalLine("user@host watch % git st", title: title)
        #expect(reading.placement == .inlineGhost, "\(title)")
        #expect(reading.currentLine == "git st", "\(title)")
    }

    @Test(
        "A listed program in front is found in every title shape a terminal writes.",
        arguments: [
            "~ — vim notes.md — 80×24", "watch — vim notes.md — 80×24", "tools — top — 80×24",
            "Default (vim)",
            "top (htop)", "vim notes.md", "sudo vim /etc/hosts", "fzf", "man ls", "watch -n1 git status",
            "me@host: less build.log",
        ])
    func frontProgramsAreFound(_ title: String) {
        let reading = terminalLine("git sta", title: title)
        #expect(reading.placement == nil, "\(title)")
        #expect(reading.currentLine.isEmpty, "\(title)")
    }

    @Test("Outside a terminal a window title naming an editor changes nothing.")
    func otherApplicationsAreUnaffected() {
        let reading = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.notes", applicationName: "Notes", role: "AXTextArea",
            value: "git sta",
            selection: NSRange(location: 7, length: 0), caret: CGRect(x: 10, y: 20, width: 1, height: 16),
            pointSize: 13, readMicroseconds: 400, windowTitle: "vim tips")
        #expect(reading.currentLine == "git sta")
    }
}
