# Telling a spoken command from content

"delete that", "scratch that" and "new line" are also words people dictate. An edit command
that destroys text needs a separation stronger than the neighbouring-word evidence
`MentionGuard` uses for inline marks. This page measures the candidate rules and records the
one chosen.

## Rules measured

| Rule | Fires when |
|---|---|
| whole-utterance | the whole utterance, all pieces of one hold joined, is a command phrase |
| whole-piece | one pause-delimited piece is a command phrase |
| key | the command phrase is spoken while a second shortcut is held |
| prefix | a piece starts with the word `command` followed by a command phrase |

Leading and trailing fillers (`um`, `please`, ...) are ignored by every rule.

## Corpus and method

`python3 Scripts/command_rule_probe.py` builds 300 invented cases from templates: 216 where
the phrase is content (embedded in prose, quoted, mentioned, at the end of a clause, said
alone, said alone after a pause) and 84 where the speaker means a command (alone, after a
filler, with "please", as the second piece of one hold, and run on without a pause). Every
case runs in hold-to-talk and hands-free mode. Under the prefix rule the speaker says the
prefix for a command; under the key rule the speaker holds the key for a command and never
for content. `python3 Scripts/command_rule_probe_test.py` pins the counts below.

The probe works on text, not on the recogniser's output for synthesised audio, so it cannot
see recognition errors on the command phrase itself, nor how often a speaker forgets the
key or the prefix.

## Result

Host: Apple M5 Pro, 48 GB. Command: `python3 Scripts/command_rule_probe.py`, exit 0.

| Rule | False commands (of 216) | Destructive false | Missed commands (of 84) |
|---|---|---|---|
| whole-utterance | 18 | 12 | 30 |
| whole-piece | 24 | 16 | 12 |
| key | 0 | 0 | 0 |
| prefix | 0 | 0 | 12 |

- whole-utterance and whole-piece fail the budget of zero destructive false commands on
  prose: content said alone ("Delete that." as a chat reply) is indistinguishable from the
  command by text. whole-utterance also misses every command spoken as the second piece of
  one hold.
- prefix misses only a command run on without a pause after content.
- key is zero on both by construction; its cost is the second gesture, which this text
  probe cannot measure.

## Decision: the held command key

A command is spoken while a second shortcut is held; there is no spoken prefix word. Line
breaks and self-corrections inside ordinary dictation stay inferred from the words.

| Piece | Where |
|---|---|
| The key | `ShortcutAction.editCommand`, default ⌃⇧ held (`HotkeyBinding.controlShiftHold`), watched by its own `ActivationMonitor` |
| The route | `DictationController` tags each press with `UtteranceRoute`; `DictationPipeline.route(next:)` sends that one recording to the commands |
| The commands | `EditCommandRegistry` asks each `EditCommand` in order; the first that accepts the words runs on the selection read at key-up |

A command-key utterance is never typed. Words no command accepts end in a notice that keeps
them; a click always dictates. While one key's hold is under way, the other key is ignored.
`Tests/UttrflowPipelineTests/EditCommandRoutingTests.swift` pins all of this.

## Markdown structure

The `lineMark` and `spanMark` rows of `spoken-commands.json` are said under the command key and
planned by `MarkdownCommand` against the selection. They apply only where the document is a
Markdown file (`CaretStructure.isMarkdown`), a capability read from the document, never from the
app; anywhere else the same words are not understood and nothing changes.

| Kind | Rows | What closes it |
|---|---|---|
| line mark | heading one to three, block quote | nothing: the mark goes before each non-empty selected line, only from a line start |
| span mark | bold, italic, inline code | the end of the selection, with the same mark read backwards; spaces stay outside |
| block span | code block | as a span, and the fence needs a line start |

A span mark with nothing selected has no span, so it writes nothing.
`Tests/UttrflowAITests/MarkdownCommandTests.swift` pins each rule and the negative class.
