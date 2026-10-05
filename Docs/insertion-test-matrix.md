# Insertion test matrix: what a machine proves, and what a person runs

[compatibility.md](compatibility.md) records what each application did when words were put into
it. This page says which insertion situations must be checked, where each check runs, and which
of them are run before a release is tagged. `make docs-audit` reads the matrix below with
`Scripts/insertion_matrix_audit.py`: a scenario with an empty cell, a test name that does not
exist under `Tests/`, or a procedure that has no section here fails it.

## Where a check runs

| Value | Meaning |
|---|---|
| `Suite.method` in the Automated column | A Swift Testing case under `Tests/`, run by `make verify` on every pull request. It drives the real strategy code against fakes of the focused field, the clipboard and the key poster, so it proves the logic for every class at once and nothing about any one application |
| `harness Hn` | A script in this repository drives a real application without a person; the section `Hn` below says how |
| `manual Mn` | A person runs the steps in the section `Mn` below and attaches the evidence it names |
| `not applicable` | The situation cannot arise in that class of application |

The application classes are the headings of [compatibility.md](compatibility.md). Pick the
application for a manual cell from that class's table there, and add a row to it with what you saw.

## The matrix

| Id | Scenario | Automated | Browser | Bundled engine | Native AppKit | Terminal | Cross-platform toolkit | Office, remote, VM, game | Focus-taking panel |
|---|---|---|---|---|---|---|---|---|---|
| S1 | A dictation into an ordinary text field | `TextInsertionCoordinatorTests.picksFirstWorkingStrategy` | manual M1 | manual M1 | manual M1 | manual M1 | manual M1 | manual M1 | manual M1 |
| S2 | A field accepts the Accessibility write and changes nothing | `SelectionWriterTests.acceptedButUnchangedIsAFailure` | harness H1 | manual M2 | manual M2 | manual M2 | manual M2 | manual M2 | manual M2 |
| S3 | A paste is posted and its arrival is never seen | `PasteConfirmationTests.givesUp` | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 |
| S4 | A paste lands late | `PasteConfirmationTests.landsAfterAWhile` | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 | manual M3 |
| S5 | Focus moves to another application before or during the write | `TextInsertionCoordinatorTests.refusesWhenTargetChangesBeforeWrite` | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 |
| S6 | Typed delivery is under way when the application changes | `TypedInsertionChunkingTests.stopsWhenTheAppChanges` | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 | manual M4 |
| S7 | Uttrflow's own window comes to the front before the write | `TypedInsertionChunkingTests.stopsWhenSelfIsFrontmost` | not applicable | not applicable | manual M5 | not applicable | not applicable | not applicable | not applicable |
| S8 | The focused field is a secure field | `SecureFieldInsertionTests.coordinatorReportsSecure` | manual M6 | manual M6 | manual M6 | manual M6 | manual M6 | manual M6 | manual M6 |
| S9 | The focused element is a control, not a text field | `TypedInsertionFocusKindTests.controlIsRefused` | manual M7 | manual M7 | manual M7 | not applicable | manual M7 | manual M7 | not applicable |
| S10 | The Mac sleeps while a dictation records | `DictationControllerTests.sleepFinishesToggle` | manual M8 | manual M8 | manual M8 | manual M8 | manual M8 | manual M8 | manual M8 |
| S11 | A second dictation is started while the first is still inserting | `DictationPipelineTurnTests.turnIsReleased` | manual M9 | manual M9 | manual M9 | manual M9 | manual M9 | manual M9 | manual M9 |
| S12 | A script-controlled web field keeps its own state | `SelectionWriterTests.acceptedButUnchangedIsAFailure` | harness H1 | manual M10 | not applicable | not applicable | not applicable | not applicable | not applicable |
| S13 | Escape is pressed while the words are still being inserted | `CancelDuringProcessingTests.escapeDuringProcessing` | manual M11 | manual M11 | manual M11 | manual M11 | manual M11 | manual M11 | manual M11 |

## Before a tag

The minimum set is S1, S5, S8, S10 and S11, each in one application from every class whose
[compatibility.md](compatibility.md) table has at least one row, plus S7 once. The person who tags
the release runs it on the build to be tagged, with the build's version and the macOS version
written beside each result, and attaches the results and evidence to the release pull request
before the tag is made. A failed cell is a release blocker unless the release notes name it.

The other rows are run when a change touches the code their automated test covers.

## Harnesses

### H1

`Scripts/web_field_probe/probe.sh`, from a terminal that has Accessibility. It opens a
script-controlled input and two kinds of `contenteditable` in Google Chrome and in a `WKWebView`,
writes into each through Accessibility, and reports whether the page's own state changed. The
expected result and how to read it are in [insertion.md](insertion.md), "A web field's own state".
Attach the printed report.

An insertion fixture application, with fields that misbehave on purpose, is planned to replace
most manual cells here; it is not in the tree yet, and this page names no test from it until it is.

## Manual procedures

Every procedure starts from a build of the commit under test with Accessibility and the microphone
granted to it, and the target application's version written down. `uttrflow-dev` commands are run
as `swift run uttrflow-dev …` from a terminal that has Accessibility. The evidence for every
procedure is a screen recording of the field from before the shortcut is pressed until the words
settle, plus any printout the steps name.

### M1

1. Click into the field and dictate "one two three".
2. Expected: `one two three`, with the casing and punctuation the clean-up gives it, appears once
   at the caret, and nothing else in the field changes.
3. Run `uttrflow-dev insert "seven eight nine"` and click into the same field during the countdown.
   Expected: `Inserted via accessibility, confirmed.` or another strategy and arrival, then
   `destination:` naming the application and `secure: false`. Attach the printout.

### M2

1. Run `uttrflow-dev insert --via accessibility "one two three"` and click into the field during the
   countdown.
2. Expected: either the words appear and the printout says `Inserted via accessibility`, or the
   words do not appear and the printout is "The app hasn't confirmed whether the text was inserted"
   or "The text couldn't be inserted here". A printout of success with no words on screen is the
   defect this row exists for.

### M3

1. Run `uttrflow-dev insert --via paste "four five six"` and click into the field during the
   countdown.
2. Expected: the words appear once, and the printout's arrival is `confirmed`, `notReported` or
   `unconfirmed`. `confirmed` with no words on screen, or words on screen twice, fails. For S4,
   note the `took` time in the printout.

### M4

1. Open a second application with a text field beside the target.
2. Start a hands-free dictation in the target, say a sentence of about thirty words, stop it, and
   switch to the second application with ⌘Tab before the words appear.
3. Expected: no words arrive in the second application. The words either finish arriving in the
   target or stop with a failure shown, and the record names the application the words reached
   ([insertion.md](insertion.md), "Which application the record names").

### M5

1. Click into a text field in any other application and start a hands-free dictation.
2. Click Uttrflow's main window, then stop the dictation.
3. Expected: nothing is typed or pasted into Uttrflow's window, and a failure is shown
   ([insertion.md](insertion.md), "Never into Uttrflow itself").

### M6

1. Click into the application's password or other secure field and dictate "one two three".
2. Expected: the words arrive in the field, and no history row, clip or last transcript holds
   them; see [insertion.md](insertion.md), "Dictating into a
   field that hides what is typed".
3. Run `uttrflow-dev insert "one two three"` with the field focused. Expected: `secure: true`.

### M7

1. Click a button, a list or a page body so that nothing editable is focused, and dictate
   "one two three".
2. Expected: no keys reach the application, so no shortcut fires, and a failure is shown with
   Copy as the recovery ([insertion.md](insertion.md), "Which route each insertion takes").

### M8

1. Click into the field and start a hands-free dictation.
2. Say a few words, then choose Sleep from the Apple menu while it is still recording.
3. Wake the Mac. Expected: the dictation was finished before sleep, so the words said before sleep
   were inserted or kept, and the microphone indicator is off after wake.

### M9

1. Click into the field and dictate a sentence of about thirty words.
2. Press the dictation shortcut again while those words are still arriving.
3. Expected: the first dictation's words arrive whole and are not interleaved with anything; the
   second dictation starts only after the first finishes.

### M10

1. In the application, open a page or composer whose field is driven by its own script (a chat
   composer or a rich editor).
2. Dictate "one two three", then type one more letter by hand.
3. Expected: the dictated words stay after the typed letter, and the application's send or save
   includes them.

### M11

1. Click into the field and dictate a sentence of about thirty words.
2. Press Escape after letting go of the shortcut, before the words appear.
3. Expected: the floating button returns to rest without a failure, no words that had not already
   started arriving appear afterwards, and the History page lists the recording with Retry.
