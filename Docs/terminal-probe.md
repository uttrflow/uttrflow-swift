# What the dictation read gets from a terminal

A terminal publishes its whole screen as one `AXTextArea` value: scrollback, the shell prompt, a
right-side prompt, a multiplexer's status line and a remote shell all sit in it. The dictation read
takes only the shell input from it, through `CaretText.inTerminal` and `ShellPrompt`
([predict-terminal-paths.md](predict-terminal-paths.md)). This page holds the probe plan for six
terminal shapes and what that read makes of each.

## The fixtures

Six snapshots in `Tests/Fixtures/AccessibilitySnapshots/`, in the `AccessibilitySnapshot` schema.
`TerminalFixtureReplayTests` reads each through `FocusedFieldRead.text` and then
`CaretText.inTerminal`, with the window title the snapshot records:

```bash
swift test --filter TerminalFixtureReplayTests
```

**These are built by hand, not recorded.** Names, hosts and paths are invented. A live recording
replaces a fixture file without changing the test's code; only its expected outcome moves.

| Fixture | Shape | Before the caret | After the caret |
|---|---|---|---|
| `terminal-local-default-prompt.json` | `user@host dir %` prompt, an open bracket in scrollback | the typed command | empty |
| `terminal-two-line-right-prompt.json` | a directory line, then a `❯` line with a right-side clock | the typed command | the padding and the right-side prompt |
| `terminal-multiplexer-pane.json` | `host:dir user$` prompt with a multiplexer status line below it | the typed command | empty: nothing below the caret's row is read |
| `terminal-remote-shell.json` | a login banner, then a remote `user@host:dir$` prompt | the typed command | empty |
| `terminal-full-screen-editor.json` | an editor's buffer, the title naming the editor | no edges | no edges |
| `terminal-here-document.json` | a here-document body with `heredoc>` continuation prompts | no edges | no edges |

## What the probe found

- In every fixture the dictated command is unaffected by scrollback: the text before the caret is
  the shell input alone.
- A full-screen program is known only from the window title. A title that does not name the
  program leaves its screen read as a shell line.
- The text after the caret keeps a right-side prompt and its padding as they are.
- A prompt shaped `user@host dir $ `, with a space before the `$`, is not recognised as a prompt
  by `ShellPrompt`; the whole line is read as input. The fixtures use the `%` and `host:dir user$`
  shapes, which are recognised.
- The snapshot records the working directory as the `document`, but the dictation read does not
  use it; the window title stands for the document.

## Probe plan for a live recording

Per terminal application, with Accessibility granted to the terminal you run from
([compatibility.md](compatibility.md), "How to add a row"):

1. Write down the application's version and the macOS version.
2. For each shape in the table, bring the screen to it, put the caret at the end of a part-typed
   command, and run `swift run uttrflow-dev context --delay 5`. Record the value, the selection,
   the window title and `AXDocument`.
3. Save the reading as a snapshot file in the schema above, with names, hosts and paths replaced
   by invented ones, and move the expected outcome in the test if it differs.
4. Fill the terminal's row in [compatibility.md](compatibility.md).

## Not measured here

Live recordings from a terminal application, a multiplexer or a remote shell on this host. A
multiplexer split side by side puts two panes on one row; no fixture covers it.
