# AI suggestions (tab-to-complete)

AI suggestions finish the line the user is typing in another application: the rest of the line
appears as grey text ahead of the caret, the accept key takes it, and typing on ignores it. The
docs call the feature tab-to-complete. A candidate comes from one of three places, asked in this
order: what this Mac has entered in that field before (the corpus), what is on this Mac right now
(a branch name, a program on `PATH`, a file in the working directory), and, when neither has
anything, a line the local model writes for the situation. The pure decision code is
`Sources/UttrflowPredict`, the corpus `Sources/UttrflowPredictStore`, capture
`Sources/UttrflowPredictCapture`, the model `Sources/UttrflowLocalModel`, the field reader
`Sources/UttrflowContext`, the key tap and insertion `Sources/UttrflowInput`, and the loop that
joins them `Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift`.

The corpus and typed text stay on this Mac and are never sent. The model runs here too; its weights
are downloaded when needed ([predict-llm.md](predict-llm.md)). Other network access, including
sign-in, model downloads, updates and opt-in crash reports, is described in [offline.md](offline.md).

Related pages: [predict-accept.md](predict-accept.md) (keys and insertion),
[predict-context.md](predict-context.md) (what the model is shown),
[predict-precision.md](predict-precision.md) (when a line is withheld),
[predict-agent.md](predict-agent.md) and [predict-terminal-paths.md](predict-terminal-paths.md)
(terminals), [predict-ime.md](predict-ime.md) (input methods),
[predict-reliability.md](predict-reliability.md) (how it is tested),
[predict-probe.md](predict-probe.md) (the probes and their measurements).

## Turning it on

Settings → AI suggestions → **Turn on AI suggestions**. It is off until the user turns it on, and
the app builds the loop the moment the switch is thrown and takes it away when it goes off. The
switch writes `suggestions.isEnabled` in the settings (`SuggestionPreferences`), the one answer to
"is this on". The corpus is opened and migrated off the main actor; the loop attaches when that
work is ready. The regression suite builds a 20,000-entry encrypted legacy corpus and verifies its
migration finishes within two seconds while a synthetic main-actor heartbeat continues to run. A
separate launch test verifies the launch handler returns within two seconds after updating the
initial menu-bar model with that same corpus present; it snapshots the menu immediately after the
handler returns. These synthetic limits do not claim a host-specific launch time.
Accessibility must be granted: the loop reads the focused field, watches the keyboard and writes the
completion into the field.
Trust is checked again whenever Uttrflow returns to the foreground. If Accessibility is missing,
the menu and Settings name it; granting access and returning restarts suggestions.

The menu-bar **AI Suggestions** tick reads whether suggestions run in the last application used,
pause and per-application choice included (`MenuBarFeatures`). With the switch on and the tick off,
the item names the reason (`SuggestionHold`) and choosing it makes the same edits Settings would:
it lifts the pause, turns suggestions back on in an application the user turned off, or both. An
application that ships off opens this screen instead, so one click never opts in a private
application or an editor with suggestions of its own. With the switch off, the item turns it on.

The rest of the screen (`SettingsPresenter.suggestions`):

| Control | What it does |
|---|---|
| **Only suggest when it is sure** | Draws a single completion and never a list (`SuggestionPreferences.isQuiet`) |
| **Pause for a while** → **Pause 30 min** | Stops suggestions everywhere for `SuggestionPreferences.pause`, 30 minutes, then lifts itself |
| **Not used in these apps** | Every application suggestions are off in; user-added opt-outs have **Remove**, and shipped opt-outs have **Turn on**; **Add an app to leave alone** adds one |
| **Used in these apps** | Every application suggestions run in that has a choice or a corpus to show, with **Leave Alone** and **Accept with** |
| **Forget what it learned here** | Beside an application that has taught at least one line; deletes that application's lines |

The focused-field observer follows the same per-application setting: only an enabled front
application is handed to it, and a click, an application switch or a settings change in an
application that is off hands it nothing, which tears its observation down. Observer registration,
focused-element reads, full-tree cleanup and teardown run on serial background queues, so a click
or switch never waits on a slow application; value and native-menu notifications still reach the
suggestion loop on the main actor.

Editors with their own inline completions ship switched off for AI suggestions
(`DestinationRules.inlineCompletionEditors`). The same table supplies the destination classifier
and the names shown in Settings. These editors are always listed, so a switch that ships off can
be found and turned on. The accept-key explanation follows the app's destination kind, including
the native action Tab keeps or replaces and, for Right arrow, that Escape no longer dismisses
suggestions.

Password managers, remote-desktop clients and virtual machines also ship switched off, because
their ordinary fields hold private information (`SuggestionApplications.privateByDefault`:
1Password, Bitwarden, KeePassXC, Keychain Access, Passwords, Screen Sharing, Windows App,
Parallels Desktop, VMware Fusion and UTM). They are listed the same way and turned on the same way.

## The pieces

| Piece | Where | What it owns |
|---|---|---|
| Engine | `Sources/UttrflowPredict` | Whether to speak, about one candidate or several, and about which |
| Store | `Sources/UttrflowPredictStore` | The corpus on disk, the prefix range scan, fuzzy fallback, forgetting |
| Capture | `Sources/UttrflowPredictCapture` | Noticing that a field was committed, and recording what went into it |
| Accept | `Sources/UttrflowInput` | Swallowing the accept key, inserting the completion, recording that it was taken |
| Surface | `Sources/Uttrflow/Suggestion` | Drawing the ghost at the caret, and drawing nothing |
| Verify | `Verifier`, `Verification` in `Sources/UttrflowPredict` | Whether a candidate is correct, which is not what the ranking measures |
| Generate | `CandidateGeneration.swift` in `UttrflowPredict`, `MLXCandidateScorer` in `UttrflowLocalModel` | Writing a continuation when the corpus and the machine have none |
| Loop | `SuggestionSession`, `SuggestionCoordinator` | Sequencing all of the above, once per keystroke |

The path is one direction per keystroke. Capture writes what the user finished entering into the
store, keyed by `Surface`: bundle identifier, Accessibility role, whatever locator the field
publishes, a scope (below) and the window. Retrieval asks the store for candidates matching the
line typed so far, and the store answers from every scope of the same field in the same
application: the same text learned in two folders is one candidate with its counts summed
(`PredictStore.candidates`). Taking or typing past a line counts once, against this scope's own
entry or else the scope that supplied it. When the corpus has nothing the machine is asked
(`EnvironmentSource`); when the machine has nothing the model generates. The engine scores
remembered candidates and answers with one `Suggestion` — `.silent`, `.certain`, `.choice` or
`.minimised`; generated lines are drawn in the model's own order. The surface draws that and is
handed text, not a decision. Accepting tells the store, which counts the use at a discount.

`PredictionStore` is a protocol in the pure module, so the engine is tested against candidates in
an array rather than a database.

## The unit of a completion is the line

**A completion continues the line the caret is on — not the field, not the sentence, not the
word.** `FocusedFieldSnapshot.currentLine` derives it: the text from the newline before the caret
up to the caret, with the caret offset read as UTF-16 (what Accessibility publishes) and moved
back onto a character boundary so a split emoji or a combining mark is never cut. `caretAtLineEnd`
asks whether the caret ends that line, so text on the lines below does not silence the feature. In
prose too long to complete whole (past `TypedLine.maximumLength`, 256 characters) the
line starts at the earliest sentence start within reach of the caret
(`FocusedFieldSnapshot.lineStart`).

**Both ends use the same unit, or the corpus fills with values nothing can find.**
`SuggestionCoordinator` derives the line once and hands it to prediction and to capture, so
`CaptureEvent.keystroke` carries the line and `CommitDetector` commits the line.
`Acceptance.edit(accepting:after:)` is given the same string, so what a replacement can destroy is
bounded by the current line.

Capture matches accessibility reads against the printable keys observed since the prior read.
A value change with no key-down in the last 100 ms counts as an insertion only when no typed key
still awaits its echo, so a slow remote shell's late echo is judged by its text, not its timing.
If a read is only a prefix of the expected echo, the unmatched suffix stays pending until the field
catches up. A line that cannot be explained by typed keys is not learned; Diagnostics counts its
closed skip reason without keeping the line.

**What is drawn is the tail, not the whole candidate.** The surface is given the line as well as
the candidate and draws only what the accept key will add.

**A terminal publishes the prose role and is not prose.** `AXTextArea` is what a document and a
shell both publish. `TerminalApplications` in `UttrflowCore` names the terminals by bundle
identifier (read from the terminal rows of `DestinationRules.standard`), which is the only signal
that separates them, so a shell is not held to the prose pause. An editor's terminal pane cannot
be told from its editor by bundle identifier and is read as prose.

## Continuation length by field kind

With no typical line here, `Register.registerContinuationLimit` caps what a continuation adds; with
one, the cap still bounds `lengthMultiple` times it. The first matching row decides:

| Field kind | How it is known | Cap |
|---|---|---:|
| Terminal command line | `TerminalApplications` names the application | 120 |
| Web address, search box or single-line field | Typed or remembered addresses; role `AXSearchField`, `AXTextField` or `AXComboBox` | 80 |
| Code or query | A SQL or code editor destination, or symbolic text | 120 |
| Reply in a conversation | `isConversational` | 80 |
| Document or any other multi-line field | None of the above | 160 |

A field's role and a terminal's identity are structural, so a Subject line with no history is never
given a paragraph's room and a shell line that opens with plain words is still a command.
`SuggestionMomentTests` asserts each row.

## What a field's scope is

`FieldReading.scope` decides which lines share a corpus and a set of recent lines:

| The field | Scope |
|---|---|
| A web page | The host, lowercased, without `www.` |
| A document with a file path | The directory containing it, so every file of one project shares one corpus |
| A terminal | Its working directory (`AXDocument`); a remote or unidentified session gets `RemoteSession.scope` or `RemoteSession.unknownScope` ([predict-terminal-paths.md](predict-terminal-paths.md)) |
| A field that owns no document | The window title, with unread counts and edit marks (`Priya (3)`, `Draft •`) removed, so two conversations are two corpora |

A title longer than `FieldReading.conversationCap` (120 characters) is a document's first line
rather than a name, and a title equal to the application's own name names no thread; both give no
scope.

## A suggestion is written in English, in the Latin alphabet

**Everything Uttrflow writes is English in the Latin alphabet.** Hindi is written romanised, the
way people type it ("haan theek hai"), and never in Devanagari. Uttrflow is not a translator, and
no suggestion puts another script into a field. Dictation holds to the same rule
([latin-output.md](latin-output.md)).

`LatinScript.writesOnlyLatin` in `UttrflowCore` is the one question asked of a piece of text:
does any letter, combining mark or digit in it belong to a script other than Latin? Accents,
fullwidth and styled Latin, emoji with their selectors, skin tones, flags and keycaps, symbols
such as ™, ₹ and ½, and punctuation of any script never count. Devanagari, Arabic, Cyrillic,
Greek, Han, kana and the digits of those scripts do.

| Where | What is refused |
|---|---|
| `SuggestionSession.turn` | A line containing another script gets no turn: it settles as `Quieting.Reason.nonLatinLine`, and neither the store nor the model is asked |
| `SuggestionSession.resolve` | A remembered or machine candidate containing another script is never ranked or drawn, though capture keeps it |
| `CompletionText.finished`, `SuggestionSession.drawable` | A generated line containing another script is dropped where the reply is parsed, so the bake-off sees it too, and again before anything is drawn |
| `SuggestionLanguage.continues`, in `SuggestionSession.resolve` and `SuggestionSession.drawable` | A candidate whose continuation the system language identifier is at least 0.9 sure is a different language from a typed line it is at least 0.8 sure of: German, French or Spanish after English. Either side under three words is not judged, and a continuation holding a word from `hindi-words.json` always continues, since the identifier cannot name romanised Hindi |
| `LatinOnlyInstruction.text`, `GenerationSituation.recentLines` | Where the screen, the window title or the text before the line holds another script, the model is told to write English, or romanised Hinglish where the person writes that, in Latin letters only. The person's earlier lines in other scripts are left out of the prompt |

**A non-Latin line is silent, not completed in Latin.** A completion in that script breaks the
rule, and a Latin one glues a romanised tail onto a Devanagari word, which is text nobody types.
The decision is per line, so the next line in the same field, typed in Latin letters, is completed
as usual.

**The instruction is given only where another script is in view**
(`GenerationSituation.readsOnlyLatin`). Given on every pass, the same sentence changed the model's
first line on 296 of 1,154 bake-off fixtures and cost three English hits, while no fixture answered
in another script without it (`uttrflow-bakeoff complete --fixtures`).

Capture still records a line typed in Devanagari, since it is the person's text; it is never
offered back. Screen text in another script is still shown to the model as context, because a
romanised Hinglish reply to a Devanagari message is a legitimate line.

## Where suggestions run and learn

Where suggestions may be offered is where typing may be learned from: one decision, made on the
AI suggestions screen. The answer is kept in
`~/Library/Application Support/Uttrflow/predict-consent.v1.json` (`CapturePreferencesFile`, written
through `PrivateFile`), written the first time the loop meets an application the screen allows and
rewritten when a switch there moves. An application the loop has met is listed whether or not it
has taught anything. Importing a shell's history (`ShellHistory`) asks the same question of the
terminal it seeds: an application not yet allowed, or declined, gets nothing, and the one-time
import stays unspent until it is allowed.

Dictation asks the same file before it learns (`LearningConsent` in `UttrflowCore`): the dictionary
learner and the usage counts write nothing about an application the user declined. An application
never asked about is learned from, because everything dictation learns stays on this Mac; that
default is `ConsentState.dictationMayLearn` and lives nowhere else. **Learn from my dictation**,
turned off on the Dictation tab of Settings, declines every application before dictation learns
anything (`SwitchedLearningConsent`); it leaves typing capture to its own switch. A secure field
teaches nothing whatever the answer. One reset removes the file, so it forgets the answers for both features.

The importer reads history from the end in 64 KiB chunks, keeps the newest 5,000 distinct
commands in chronological order, and skips Bash's epoch timestamp lines.

Both sides file an application under `ApplicationKey`, its bundle identifier lowercased, because
macOS is not consistent about case and the switch and the field reading see the identifier from
different places. A consent file holding both spellings of one application is read as the refusal,
because consent fails closed.

`Uttrflow` in that path is the folder this build writes under; a development build writes under
its own ([development-build.md](development-build.md)).

`CaptureGate` refuses to record, before anything reaches the corpus:

- anything from a secure field;
- anything from an application not yet allowed, or declined;
- a value shaped like a credential, by the rules the clipboard uses, applied to the whole value
  and to each of its lines, so a continued command is judged as its one-line form; lines learned
  before a rule widened are swept once per `CaptureGate.secretRulesVersion`;
- a code-shaped digit value outside a terminal, grouped by whitespace or `- . / : _ ,`, with
  trailing punctuation and paired parentheses ignored, except a compact decimal (one to four whole
  digits and one or two fractional digits), a valid `YYYY-MM-DD` date, or two two-digit values
  separated by whitespace; ungrouped codes and longer grouped account/card patterns remain refused;
- a destructive command (`DestructiveCommand`);
- a value shorter than `CaptureGate.minimumLength` (2).

A keyed edit inside an accepted line, when committed, records the final text as typed and removes
the original acceptance and self-sourced count. An unchanged accepted line keeps its acceptance.
If retracting an acceptance fails, capture holds the retraction and retries it before the next
event or acceptance.

## The corpus on disk, and forgetting

The working database is SQLite held in memory. Each committed change is sealed with AES-GCM
(`EncryptedStore`, key in the Keychain, this device only) and written atomically to
`predict.v1.sqlite`; no plaintext `-wal` or `-shm` files exist beside it. The snapshot and the
consent file are excluded from backup (`PrivateFile`). A legacy plaintext file is copied in through
SQLite, committed WAL frames included, before the first sealed snapshot replaces it, and its
sidecars are removed. A snapshot that cannot be sealed or written fails the change rather than
claiming it is durable.

Settings reaches the corpus through `PredictCorpus`, which opens it only for the question asked and
never creates it, so forgetting works whether or not the loop is running.

- **Forget what it learned here** deletes that application's surfaces and every entry and
  succession in them. Other applications keep theirs.
- **Reset personalisation** (Settings → Privacy) deletes the dictionary, history, clipboard,
  snippets, learned completions and the applications they may learn from, recordings kept for a
  retry, every preference on that screen, every surface in the corpus and its consent file. The
  [reset row](../Sources/UttrflowUX/SettingsPresenter.swift#L1190-L1203) owns this scope.
- **Switching an application off** stops learning there and keeps what was learned. Turning the
  feature off everywhere keeps the corpus the same way.

`PRAGMA secure_delete = ON` zeroes the cells a forgotten row held. When deletes leave at least
`PredictStore.compactionThresholdPages` (64) free pages, the store runs `VACUUM` after the write.

## The loop, once per keystroke

`SuggestionSession` in `UttrflowPredict` is the whole sequence as pure code: the field, what is
drawn, where the highlight sits, how many suggestions were typed past and how far the escape ladder
has been walked. It answers a moment with what to draw or a question for the store, and stamps
every question with a generation so an answer that arrives after the user typed on is dropped.

The store's answer is not drawn directly. `resolve` ranks it, and a turn with anything on offer
comes back as `.verify` carrying the head of the ranking — `SuggestionSession.verifiedDepth`
candidates, every one that could be drawn. Those go through `Verifier`, and the second `resolve`
draws what the gates left. A turn with nothing on offer settles without the gates.

`SuggestionCoordinator` is the part that cannot be tested headlessly: a global key monitor, the
Accessibility read on a queue of its own, the event tap, the panel and the corpus. Its one-second
tick runs for the activity window of an enabled frontmost app, then slows to five seconds while a
ghost remains visible and stops when the ghost disappears or a disabled app becomes frontmost
([tick intervals](../Sources/Uttrflow/Suggestion/SuggestionTicking.swift#L8-L13)). Disabled or unknown
apps do not schedule turns from key, click, accessibility, menu, activation or timer activity.

| Constant | Value | What it bounds |
|---|---|---|
| `SuggestionCoordinator.fieldReadDebounceInMilliseconds` | 180 ms | Typing pause before the field is read; each key withdraws the ghost and restarts it |
| `SuggestionCoordinator.generationDebounceInMilliseconds` | 120 ms | Pause before a model pass, from the latest key |
| `CaptureTypingRouter.maximumKeys` / `maximumCharacters` | 256 keys / 4,096 UTF-16 units | Keystrokes held between field reads; overflow drops the batch and prevents it from being learned |
| `AcceptanceQueue.maximumPendingWrites` / `maximumPendingBytes` / `maximumWriteBytes` | 128 writes / 512 KiB / 64 KiB per write | Corpus work held behind a slow write; overflow drops later work, drains admitted writes, resets incomplete field state, and waits for an empty-field baseline before capture resumes |
| `SuggestionTicking.interval` / `SuggestionTicking.ghostInterval` | 1 s / 5 s | Field observation after activity, then while a ghost remains visible |
| `SuggestionTicking.activeSelectionInterval` / `SuggestionTicking.ghostInterval` | 200 ms / 5 s | Caret checks of an armed ghost while the person is active, then once the visible ghost is idle |
| `Quieting.proseHesitationInMilliseconds` | 400 ms | Pause a prose writer must make before anything is drawn |
| `SuggestionSession.turnBudgetInMilliseconds` | 8,000 ms | A whole turn, timed from after the field read; a later answer draws nothing |
| `Verification.budgetInMilliseconds` | 7,000 ms | The model's share of one keystroke's verification |
| `TurnGate.stallSeconds` | 10 s | A turn left behind so the next one can run |
| `FocusedFieldReader.elementTimeoutInSeconds` | 50 ms | One Accessibility message |
| `FieldReadBudget.allowance` | 40 ms | One whole field read |
| `SlowFields.firstRest` … `longestRest` | 10 s doubling to 5 min | How long a field that overran is left alone |
| `CommitDetector.idleInterval` | 8 s | Idle time that commits a line |

Return, focus changes and other non-typing wakes read the field at once. A delayed wake is checked
against the generation after cancellation, and a read in progress stops after its current
Accessibility message when a newer key invalidates it.

**Per-keystroke message budget: at most 3 in a steady burst of 10 keys a second.** One ordinary
field snapshot costs 24 Accessibility messages; eight keys 100 ms apart keep resetting the 180 ms
deadline, so the burst produces one snapshot, 3 messages per key (`SuggestionDebounceTests`). A
single isolated key still causes one full snapshot.

**A field's answers are cached for its element and window.** The five field identity attributes
are requested in one `AXUIElementCopyMultipleAttributeValues` call, with a per-attribute fallback
where the batch is unsupported. The result, document, window title and frames are held for one
process, focused element and window; a change of any of the three replaces it. A focus move, any
other key and a scroll while a suggestion shows all clear it, because a key can move a caret-sized
input, grow a composer or move a window without a click. A read that began before a clear does not
keep its answers.

**A slow field is left alone.** A snapshot stops at the next question once the 40 ms allowance has
passed. A field's first overrun is forgiven as a cold start (about 60 ms in a browser once its full
tree is on); a second rests the field for 10 s, doubling on each further overrun up to 5 minutes,
and a read within budget ends the rest. While a field rests, its whole application is sent no
message at all (`SlowFields.isQuiet`), because asking which element has focus can itself be the
slow part (about 100 ms in a browser holding a 200 KB text area). A click, an application switch,
Tab, Escape or any ⌘ shortcut may have moved focus, so each ends the quiet.

**One turn runs at a time.** `TurnGate` admits a turn, holds the next while it runs, and after
10 s leaves the running one behind and admits the next; a turn left behind asks `isCurrent` before
touching anything, so a read into an unresponsive application cannot end the loop. A Return or an
application switch that arrives during a turn is kept and run afterwards.

### One ghost, and only while it is true

- **One panel for the process** (`SuggestionPanelController.shared`): a loop rebuilt when the
  feature is switched off and on draws in the same window, and a stopped loop draws nothing. A new
  suggestion replaces the old one whole, measured before the panel is placed.
- **A key that types the ghost's next letters keeps it.** On a plain append,
  `SuggestionSession.typedThrough` carries the offer past the key and the panel moves the rest of
  the ghost by the width the typed letters took off it, without hiding it.
- **A ghost is drawn whole or not at all.** The panel refuses a ghost wider than the room to the
  field's edge, and a ghost that is not on screen whole claims no key.
- **Any other key withdraws the ghost**, as does anything that may move the caret: a click, a
  scroll, a change of front application, a Space change or the display sleeping. Each hides the
  panel, disarms the keys and calls `SuggestionSession.invalidate`, so `resolve`,
  `resolveGenerated` and `expandGenerated` return nothing for a turn whose read began before it,
  and the coordinator draws only while `SuggestionSession.isCurrent`.
- **Accessibility may report the previous caret briefly after a ghost-typed character.** The guard
  accepts only that immediately previous position for 500 ms, then requires the advanced caret.
  This covers the reported 300 ms terminal echo plus one 200 ms selection-poll interval; any other
  caret position still withdraws the ghost.
- **A continuation does not repeat the word at its join.** `SuggestionSession.resolve` removes
  repeated join words from remembered candidates before ranking and after verification corrections;
  `SuggestionSession.drawable` applies the same rule to generated candidates and alternatives.
  Words are split at whitespace and compared ignoring case, so `-m` after `m` is still drawn.
- **A timed-out selection read keeps the offer armed** for its next poll. A completed read that
  cannot identify a focused selection still withdraws it.
- **A model line keeps the typed case**, so the ghost only adds to the line and Tab never re-cases
  what the user wrote.

### What counts as a value the user finished

A field's life ends four ways — Return, the focus leaving it, the application going to the
background, and the line idling for 8 s — and `CommitPolicy` decides which of those finish a value
in that application. Where the words stay where they were typed, all four do. Where the words are
sent rather than kept — a terminal, a chat composer — only Return does
(`CommitPolicy.whereReturnSends`): a shell rewrites its line on the way out, and a line abandoned
in a composer was never a message. Which applications are conversations is the destination table's
answer (`DestinationClassifier`), not a second list. A composer is not told from a document by the
Accessibility tree: both are a text area whose contents change, and no heuristic over the tree
separates them reliably.

Return and the focus leaving the field finish a line (`LineOrigin.finished`); an idle or the
application going to the background leaves only a draft. A longer line retires the shorter drafts
it grew out of, and a draft is not stored when a longer line already starts with it, but a finished
line is never retired that way: `ls` run on its own keeps its own count beside `ls -la`. Lines
stored before the corpus kept this mark are treated as drafts.

### The model path

When the corpus and the machine both have nothing for the line and the generator reports
`isReady`, the turn takes `SuggestionCoordinator.generate` instead of `resolve`:

- **Reuse first, only while typing on.** The last answer is kept with its line and the text before
  that line. While the user types forward from that line in the same field, it is drawn again with
  no pass, after it meets the machine's gate again. A deletion, a move to another line or a change
  to the text before forgets it. An empty answer is remembered against its exact line and place,
  so a tick does not ask again.
- **Debounced.** A pass sleeps what is left of the 120 ms since the key; the next key cancels it,
  so a burst costs one pass for its last prefix.
- **Context is read once a pass is certain**: the window title and surrounding text, the person's
  `SuggestionMoment.recentLinesShown` (6) most recent lines here and the
  `SuggestionMoment.precedingContextLength` (400) characters before the line
  ([predict-context.md](predict-context.md)).
- **One line first.** The pass asks for the single most likely completion and stops at its
  newline; `resolveGenerated` draws it as `.certain`. The alternatives are fetched in a second pass
  once that line is on screen, and `expandGenerated` turns it into a `.choice`, so ⌥↓ opens a list
  nobody waited for. Quiet mode never expands.
- **Drawn against the field as it is now.** A late answer is drawn only after a fresh read finds
  the same field and line (`drawFresh`).
- **Scored by its own pass.** A generated line is drawn only when the pass that wrote it scored it
  over `Verification.certainFloor`, or `choiceFloor` in a list
  ([predict-precision.md](predict-precision.md)); in a terminal every word it adds is checked
  against the machine ([predict-agent.md](predict-agent.md)). A generated line typed past does not
  count towards the field's rejections.

## Correctness above habit

Frequency says what the user does, not what is right. Somebody who has typed `git comit` a hundred
times has an entry with a hundred uses, and `Ranking`, which measures evidence only, puts it first.
`Verifier` stops that entry being offered, before anything is drawn. Before the gates, a line that
`DestructiveCommand` matches, or that a terminal's path check refuses
([predict-terminal-paths.md](predict-terminal-paths.md)), or a candidate marked `isIrreversible`,
is dropped.

**1. Existence, first and unconditionally.** If the machine says the word exists — a program on
`PATH`, a subcommand this machine's `git` accepts, a name the user's shell or git configuration
binds — the verdict is `.attested` and nothing below may touch it. Half of what looks like a typo is
a real alias: somebody who has bound `cm` to `commit` gets `git cm` offered. The model is not asked.

**2. Plausibility.** The local model scores the candidate's mean log-likelihood per token in
context — one forward pass, no generation — against `Verification.plausibilityFloor`. A model with
no opinion, and a model that is not loaded, are both no objection.

**3. The nearest correct neighbour.** A word the machine has denied — it answered, and this word is
not in its answer — is looked up against everything it does know. A neighbour is offered only when
one slip no dearer than `TypoModel.indelCost` (3.2) explains the difference: a transposition, a
doubled letter or a neighbouring key, never a distant substitution or anything in the first
character. `FuzzyMatch`'s character mask is the prefilter, and
`FuzzyMatch.budget(forQueryOfLength:)` is why nothing under three characters is corrected. The
corrected form is offered silently.

**Silence is not a denial.** A machine that has not answered yet — a cold `EnvironmentIndex`, a
kind still refreshing, or a field with no working directory — knows nothing, so nothing is
corrected or rejected and the verdict is not cached.

**4. Superseding.** A correction or refusal is written to the corpus only when the machine answered
and the word's kind is a closed vocabulary (`Verification.isClosedVocabulary(for:)`): the entry
then stops accruing weight and is never proposed again. A file or branch the machine does not know
today may exist tomorrow, so those are refused for this turn only, as is a refusal by the model
alone. A write that fails is retried and the line held back for the session meanwhile.

**The budget belongs to the keystroke.** `Verifier.verified` shares one 7,000 ms deadline across
the whole set; the model is raced against it, and a candidate it does not judge in time is
rejected and not cached, so the next keystroke may ask again. An attested candidate never reaches
the race.

**The cache.** `VerdictCache` is keyed by candidate and context (surface plus typed text): 64
verdicts (`VerdictCache.capacity`), oldest dropped first, each believed for 5 s
(`VerdictCache.lifetimeInSeconds`) — the lifetime `EnvironmentIndex` gives an answer about a
directory, so an alias defined a moment ago can win. Program and verb listings are believed for
60 s (`EnvironmentIndex.programLifetimeInSeconds`). These expiries, retry backoffs, remote-volume
cooldowns, turn stalls, activity windows and the 8,000 ms suggestion turn budget use monotonic time,
so a wall-clock correction does not extend them.

### A correction, from the keystroke to the field

The user has typed `git comi`. The store offers `git comit`, entered a hundred times, and the
ranking puts it first. The machine's `git` denies `comit` and knows `commit`, so the verdict is
`.corrected("git commit")` and `git comit` is superseded on the way past. The engine draws
`.certain("git commit")`. Tab asks `Acceptance.edit(accepting:after:)` what that costs: `git comi`
and `git commit` agree on `git com`, so the edit replaces `i` with `mit`, and `CompletionRoute`
writes it with one backspace before the insertion.

### The scorer

`UttrflowApp` builds one `MLXCandidateScorer(model: .gemma3)` inside an `IdleReleasingModel` and
hands it to `AppDelegate` as both scorer and generator, each wrapped so it runs only when
`EnergyConditions.current().allowsDiscretionaryWork` and no dictation is in progress
(`DiscretionaryModel`, `DiscretionaryGenerator`). Until the model reports `isReady`, gate 2 is
silent and the statistical gates answer alone; a keystroke never waits on a loading model.

**`plausibilityFloor` is −6.0**, measured with `uttrflow-bakeoff score` on gemma-3-4b-it-qat-4bit
(mean log-probability per judged token, Float32 softmax):

| Line (typed → candidate) | Score |
|---|--:|
| `ls` → `ls -l` | −0.18 |
| `git c` → `git commit -m` | −0.35 |
| `ls` → `ls -la` | −1.24 |
| `SELECT * FROM u` → `… users` | −1.64 |
| `Deploy the re` → `Deploy the release candidate to production` | −3.26 |
| `git c` → `git checkout main` | −4.65 |
| `git comit -m` (a typo) | −5.76 |
| `gizmo --frobnicate` (nonsense) | −7.29 |
| `ls --zzqx-bogus` | −9.15 |
| `Deploy the rezzq flombat` | −10.62 |
| `SELECT * FROM uzqx WHERE` | −11.77 |
| `git cxq` | −13.60 |

The floor sits between the weakest real line and the nearest nonsense. A plain typo passes this
gate and is left to the nearest-neighbour gate, where a typo belongs.

**The candidate is scored as the whole line it is.** `Verifier` hands the scorer the stored line
and what is typed; the scorer tokenises the line, takes the typed opening from the line's own
spelling and judges only the tokens past where it ends, read back from the line's own tokens.
Tokenising `typed + line` would judge `lsls -l` and reject every remembered line. Two measured
traps shape it:

- Gemma 3 4B predicts nonsense from the first two positions after `<bos>` (`" git"` after
  `<bos>$` scored −27), so the scorer puts a two-token lead-in (`"...\n"`) before every line.
  `"\n\n\n"` is one token and does not help; a chat-template frame puts the instruction-tuned
  model into peaked answer mode (`" commit"` −0.00, `" checkout"` −19.5) and is worse.
- When the typed text ends inside a token (`gi` → `git status`), the first judged token would read
  the cold prior for a line's first word, about −10. `ScoredSpan` finds the typed bytes that token
  still owes and reads it as P(token | typed remainder) = P(token) / Σ P(every token that writes
  the remainder first). Measured with `uttrflow-bakeoff score`: `gi` → `git status` −8.01 → −2.85,
  `gi` → `git checkout main` −6.54 → −3.10, `l` → `ls -la` −6.63 → −4.01, `git sta` →
  `git stash pop` −6.61 → −3.89. The cost is the nonsense margin for a prefix cut mid-word: `gi` →
  `gizmo --frobnicate` rises to −5.80, allowed, and `SELE` → `SELECT * FROM uzqx WHERE` to
  −6.09; nonsense past more of the line stays far below (`git cxq` −13.24). Attested candidates
  never reach the model.

**A stale model pass yields the serialized model slot between bounded chunks.** Prompt prefill and
candidate scoring each make one `ModelContainer.perform` call per chunk, with at most 128 input
tokens in a call. Cancellation is checked between calls. If cancellation arrives during a
synchronous model operation, that operation may finish; the next pass can take the slot as soon as
that one operation returns, without waiting for the rest of the stale prompt or candidate. This is
a token-count bound, not a wall-clock promise: the duration of one model operation depends on the
device and model. `CancellableModelChunksTests` uses a controllable slow chunk to assert that a
waiting pass starts after the current chunk and before any later stale chunks begin.

Per-call cost is 55–90 ms warm and about 250–340 ms cold on the 4B model
([performance.md](performance.md)), so the four sequential passes `verifiedDepth` allows fit well
inside the 7,000 ms budget.

## The engine decides three things

`Frecency.score` is evidence, never correctness:

| Term | Constant | Effect |
|---|---|---|
| Uses | — | `log(1 + uses)`, with uses that came from accepting a suggestion counted at `Frecency.selfSourcedWeight` (0.25) |
| Age | `Frecency.halfLifeInDays` (21) | Halves the weight every 21 days since the last use |
| Offers | `Frecency.acceptanceLift` (0.6) | `1 + 0.6 × (accepted − rejected) / offered`, so between 0.4 and 1.6 once offered |
| Refusals | `Frecency.retiringRefusals` (3) | A line typed past at least 3 × (accepted + 1) times is retired until typed by hand again |
| Distance | — | Divided by `1 + 2 × editDistance`, so a fuzzy match is worth less than an exact one |
| Machine candidate | `Frecency.environmentWeight` (1.0) | A value from the machine with no corpus evidence |

**Whether to speak at all** is `Ranking.support`, the leader's score, against
`PredictionEngine.supportFloor` (0.15); below it the turn is quiet for `evidenceTooThin`.

**Whether to speak of one candidate or several** is `Ranking.separation`, the leader's share of
the total score minus the runner-up's, against `PredictionEngine.separationThreshold` (0.20). Below
it the answer is a `.choice` of at most `PredictionEngine.maximumChoices` (4).

Case-only spellings of a line are grouped before support and shares are calculated. Their scores
are added, and the spelling with the strongest individual score represents the group; ties use
text order.

**Whether a candidate may be offered at all.** An irreversible leader is never offered and never
stepped past to promote a rival it outranked; irreversible rivals never appear in a `.choice`
(`irreversibleNotCertain`).

## Why nothing is drawn

`Quieting.reason` runs its predicates in order and returns the first that fires, so the log can
say why nothing was drawn:

| Order | Reason | When |
|---|---|---|
| 1 | `turnedOffHere` | Off in this field (⎋⎋, ⌥⎋ or the preferences) |
| 2 | `secureField` | The field hides what is typed |
| 3 | `composing` | The field reports marked text ([predict-ime.md](predict-ime.md)) |
| 4 | `unknownWritingDirection` | The glyph bounds do not say which side the continuation belongs on |
| 5 | `nowhereToDraw` | The field reports no caret |
| 6 | `textSelected` | Text is selected |
| 7 | `caretInsideText` | The caret is not at the end of its line |
| 8 | `applicationPicker` | The field says its own list is open (`AXExpanded`), or trigger text opens a known picker application's mention, emoji, channel or slash-command picker (`AppPicker`; ordinary applications and terminal command lines are not inferred to have one) |
| 9 | `rejectedTooOften` | `Quieting.rejectionsBeforeSilence` (3) suggestions typed past in this field |
| 10 | `writingFluently` | A prose writer has not paused for 400 ms |

Every later silence carries its reason too: `SuggestionUpdate.silence` is set wherever the session
or the engine settles on nothing — `nothingFocused`, `emptyLine`, `listMarkerOnly` (`ListMarker`),
`lineTooLong`, `nonLatinLine`, `minimised`, `nothingOffered`, `notOnThisMachine`,
`evidenceTooThin`, `modelUnsure`, `irreversibleNotCertain`, `overBudget`, `quietModeChoice` — and
the coordinator logs that reason, never one recomputed from outside.

## The store

`Schema` holds one row per surface, one per entry and one per succession pair, and two indexes on
`entry`, each for one query: `entry_prefix` on `(surface_id, text_lower)` for the prefix range scan
run on every keystroke, over lowercased text so matching ignores case and keeps the index, and
`entry_recent` on `(surface_id, last_used)` for the recent lines the model is shown. Lowercasing
uses Swift's `lowercased()` on write and query alike, since SQLite's `lower` folds ASCII only.
`Schema.version` is 8; an older file is migrated when opened and a file from a newer build is
refused rather than written to.

| Limit | Constant | Value |
|---|---|---|
| Entries per surface, evicted by fragment status, acceptance, uses and age | `PredictStore.entriesPerSurface` | 2,000 |
| Scopes kept per field, least recently used evicted | `PredictStore.surfacesPerField` | 64 |
| Most recent scopes a lookup reads | `PredictStore.scopeLimit` | 8 |
| Candidates a lookup returns | `PredictStore.candidateLimit` | 16 |

An entry carries `count`, `accepted`, `rejected`, `self_sourced`, `finished` and `last_used`. A
`superseded_by` value marks text the gates replaced or refused, and a superseded entry is never
proposed again. Forgetting works at three sizes: one entry, one application, everything.

A write protects its new entry and succession pair from its own eviction. Later pressure removes
fragments first, then entries with fewer acceptances, fewer uses and older `last_used` values;
retired entries remain last.

## Two measurements behind the store's shape

Re-run both with `uttrflow-dev probe retrieval`; the numbers are in
[predict-probe.md](predict-probe.md).

**`LIKE` is a full surface scan, not a full table scan.** Asking SQLite for the plan:

```
RANGE: SEARCH entry USING INDEX entry_prefix (surface_id=? AND text_lower>? AND text_lower<?)
LIKE : SEARCH entry USING INDEX entry_prefix (surface_id=?)
```

Only the range constrains `text_lower`; `LIKE 'git c%'` filters every row of that field one by one,
so its penalty grows with how much one field holds. The test suite asserts the query plan rather
than a wall-clock bound, because a threshold calibrated on one Mac measures whichever machine runs
the tests (a 200 µs bound measured 495 µs on a shared runner), while the plan fails exactly when
the query is rewritten as a `LIKE`.

**The prefilter's mask is as wide as the query plus its edit budget.** The fuzzy fallback rejects
candidates with a 64-bit character mask before computing any edit distance. A mask over the first
*n + k* units (query length plus edit budget) measured **14.9×** faster than no prefilter; a fixed
twelve-unit window measured **4.0×** (on ASCII). Both are sound, so a fixed width loses most of the
gain silently. `FuzzyMatch.maskWidth(forQueryOfLength:within:)` is the one place the width is
decided. The unit is the Unicode scalar for the budget, the mask and the distance alike; counted in
UTF-8 bytes, one Devanagari letter would be three units and earn edits meant for longer queries.

## Running it in development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --filter UttrflowPredict     # the decision layer, no database and no clock
swift run uttrflow-dev probe retrieval  # the retrieval numbers, on this machine
```

The probes that read other applications need Accessibility, which is attributed to the responsible
process: `uttrflow-dev` launched from a terminal that holds the grant inherits it
([predict-probe.md](predict-probe.md)). `uttrflow-dev context --bundle <id> --surroundings` prints
what the model would be shown around the focused field, and
`uttrflow-dev machine --directory <dir> --under <path>` prints what the machine index lists there.

## Suggestion counts in Insights

When suggestions are on, Insights shows the suggestion corpus' stored lines, recorded uses,
accepted offers, offers typed past and self-sourced entries. They are lifetime totals for the
current corpus, across fields; they do not follow the dictation chart's selected range. Turning
suggestions off removes this group from the page.

`recorded uses` sums `count`; `accepted` and `rejected` count offers that the user accepted or
typed past; `self-sourced` counts entries written because a suggestion was accepted. The corpus
does not count offers that received no recorded response, so these totals do not form an acceptance
rate. Quieting reasons such as `secureField`, `writingFluently` and `rejectedTooOften` are logged
when they occur, but are not stored as totals for Insights. Read acceptance and typed-past counts
beside the corpus size: a high acceptance count alone can hide that few offers were made. Corpus
size is not quality; 2,000 entries in one field is the eviction cap.

## The rules that do not bend

1. **Fuzzy is a fallback, never a parallel path.** It runs only when the exact prefix scan comes
   back empty. On 50,000 entries `git p` matches 925 exactly and 2,776 within one edit, `git commit`
   among them; a blended matcher would offer `git commit` to somebody typing `git push` correctly. Queries
   under three characters are never corrected.
2. **Return is taken only after ⌥↓.** The accept key is Tab, → or ⌥⇥ by kind of application
   ([predict-accept.md](predict-accept.md)). Return sends the message, runs the command or submits
   the form, so it is taken only once the user has opened the list of a `.choice`.
3. **Nothing goes through the clipboard.** The completion is written into the field; the clipboard
   is not borrowed, cleared or restored. A clipboard round trip races the user's own copy, and this
   feature fires on a keystroke ([insertion.md](insertion.md)).
4. **A secure field draws nothing and learns nothing.** `Quieting` refuses it before any candidate
   is scored, and capture never records from it. `SecureField` treats a field as secure when its
   role, subrole, name, placeholder or description says password, passcode, one-time code, PIN,
   card number, card security code, social security number, account or routing number, date of
   birth or security answer, or when its value is mask characters alone. A terminal prompt label
   naming a password, passphrase, PIN, code or token is secure too. Short code-shaped values,
   including expiry dates, times and parenthesised or punctuated codes, are never learned outside
   a terminal, except compact decimals, valid `YYYY-MM-DD` dates, and two two-digit values
   separated by whitespace. Ungrouped codes and longer grouped account/card
   patterns remain refused.
5. **Self-sourced evidence is discounted.** A use that came from accepting a suggestion counts a
   quarter of one typed. Without it, offering a candidate makes it likelier to be offered, and the
   set of things the feature knows narrows to what it already said while the acceptance rate
   climbs.
   Positive acceptance lift is scaled by the share of the entry's evidence that was typed by hand;
   refusals retain their full penalty.
