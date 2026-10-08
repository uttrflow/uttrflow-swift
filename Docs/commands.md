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
`MarkdownEditCommand` runs them from the command key, writing the planned edit over the focused
field's selection; where no edit is planned, or the field is secure, it refuses and writes nothing.
`Tests/UttrflowTests/MarkdownEditCommandTests.swift` pins the write and each refusal.
`Tests/UttrflowAITests/MarkdownCommandTests.swift` pins each rule and the negative class.

## Edits on the last dictation

"delete that", "select that" and "undo that", said whole under the command key, are read by
`RecordedEdit` and carried out by `RecordedEditor` against `InsertionLedger`, over
`CommandScope.default`. They only remove or select what Uttrflow wrote; no word is rewritten.
"undo that" undoes the newest spoken edit held in `EditHistory`, and with none held it takes the
last dictation out. Every edit refuses, changing nothing, when another field is in front or the
dictation is no longer exactly where it was written (`Docs/insertion.md`). A delete of a dictation
that runs over more than one line is refused rather than run.
`Tests/UttrflowInputTests/RecordedEditTests.swift` pins each edit and the refusals.

"replace X with Y" under the command key is planned by `ReplaceCommand` (X found as a word
sequence by `WordForms`, the match nearest the end) and written by `RecordedEditor.rewrite` over
the same span, so "undo that" puts the dictation back. When X is not in the last dictation the
command refuses and nothing is written. Command words go through the dictionary before any
command reads them, so Y is written in the spelling the user filed.

## Key presses

The `key` rows of `spoken-commands.json` ("press enter", "press tab", "press escape", "go to the
end", "go to the start") are said whole under the command key and planned by `KeyCommand`. A key
press never carries text. Each row's `destinations` say where it may post: enter and tab in prose,
chat and email; escape and the document start and end there and in a code editor; none in a
terminal or SQL editor, where enter runs what is on the line. A secure field refuses every key.
The stroke is a `KeyStroke`, posted by `SystemKeyStrokePoster` tagged with `SyntheticEvent`.
`KeyEditCommand` runs them from the command key, deciding the destination at key-up from
`DestinationClassifier`; a refusal posts nothing.
`Tests/UttrflowInputTests/KeyCommandTests.swift` pins each stroke and each refusal.

## Evaluation

`EvaluationCorpus.commandCases` (`Sources/UttrflowEval/CommandCorpus.swift`) holds 20 cases per
Markdown command, all said under the command key: 10 that must run (the phrase alone, in five
written forms, in two Markdown documents) and 10 that must not (the phrase inside a longer
utterance, and the phrase alone in five documents that are not Markdown). `CommandReport` gives
recall per command, every false execution, and false executions by document.

| Gate | Limit |
|---|---|
| false executions | 0, since every command rewrites the selection |
| recall per command | 100% over the corpus's written forms |

`Tests/UttrflowEvalTests/CommandCorpusTests.swift` holds the shipped reader to the gate and shows
that a reader matching the phrase anywhere in the utterance, or one that ignores the document,
fails it.

### Mentions in dictated prose

`EvaluationCorpus.commandMentions`
(`Sources/UttrflowEval/Resources/Corpus/notARequest.commandMention.json`) holds 10 sentences per
Markdown command that name the phrase as content ("the bold button is greyed out today"), dictated
without the command key into `notes.md`. Each case's `mustNotAdd` is the
command's mark, so a clean-up that writes it has run the command on prose. `CommandReport` counts
these per command, and the gate's budget for them is 0. The rules clean-up writes none;
`CommandCorpusTests` shows that a dictation that obeys the phrase fails the gate.

### Recognition on audio

`uttrflow-eval command-recall` scores the corpus with the shipped reader and the shipped router,
then has `say` read every Markdown phrase to a file in six voices (US, UK, Australian, Indian,
Irish and South African English), clean and with white noise at 20 and 10 dB, and decodes each take
with the shipping recogniser. A take hits when `MarkdownCommand` makes the same edit from what the
recogniser wrote as from the phrase; a take that makes a different edit is a misfire.
`--record` writes every take; `Tests/UttrflowEvalTests/Golden/command-audio.tsv` is the last run,
and `CommandAudioRecallTests` holds the reader to it.

Host: Apple M5 Pro. Command: `uttrflow-eval command-recall --record <file>`, whisperKit large-v3
turbo, 216 takes.

| Condition | Recall |
|---|---|
| clean | 77.8% |
| 20 dB | 51.4% |
| 10 dB | 33.3% |
| US, UK voices | 69.4%, 66.7% |
| Australian, Indian, Irish, South African voices | 36.1%, 41.7%, 47.2%, 63.9% |
| all | 54.2% (117 of 216), 0 misfires |

| Command | Recall | Most frequent miss |
|---|---|---|
| heading one, heading 1 | 83.3% | "having won" in noise |
| heading two, heading 2 | 22.2% | "Heading to." in every voice, clean included |
| heading three, heading 3 | 61.1% | "Hitting 3", "Heading free." |
| block quote | 22.2% | "block code", "love quote" |
| bold | 27.8% | "Oh", "those" |
| italic, italics | 61.1%, 72.2% | "Italy", nothing heard |
| inline code | 100% | none |
| code block | 33.3% | nothing heard, "cold block" |

No take ran a different command. The gate (`CommandAudioReport.passesGate`) is held at this run:
recall at least 117 of 216, 0 misfires. Synthetic voices read cleanly, so a real speaker's recall
is lower than this, not higher; a recorded set replaces the table.
