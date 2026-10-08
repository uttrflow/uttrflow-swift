# Explaining one dictation, stage by stage

`uttrflow-dev explain <clip>` replays a recorded clip through the recogniser and the clean-up
router and prints what each stage took in, gave out and decided. It is how a wrong dictation is
traced to the stage that caused it, instead of guessed at.

```bash
uttrflow-dev record --seconds 6 --output clip.wav   # or any clip kept outside the repository
uttrflow-dev explain clip.wav
```

## What it prints

One labelled line per fact, in the order the stages ran. `DictationExplanation` in
`UttrflowAI` builds the lines; the command only transcribes and prints them.

| Label | Stage | What the line says |
|---|---|---|
| `heard` | recogniser | the transcript exactly as recognised |
| `words` | recogniser | every word with its confidence, or that the recogniser gave none that spell the text |
| `doubtful` | candidate sources | each half-heard run, its lowest confidence and the readings offered for it |
| `for model` | passes before the model | the words a model is given, after fillers, stammers and self-corrections |
| `skipped` | router | an engine passed over as unavailable, and why |
| `failed` | router | an engine that ran and gave no answer, and why |
| `refused` | meaning and script guards | an answer thrown away, and the guard's reason |
| `model said` | the kept model | its answer word for word, before it was unwrapped and finished |
| `step` | clean-up passes, before and after the model | what one step removed, rewrote and added, quoting up to `CleaningRecord.wordLimit` words |
| `off` | clean-up passes | a step that was not in the pipeline that ran |
| `tidied by` | router | the engine whose answer was kept |
| `result` | output | the text that would be inserted, line breaks shown as `⏎` |

The `step`, `skipped`, `failed`, `refused` and `off` lines are read off the same
`CleaningRecord` the Diagnostics page draws, so the trace and the page cannot disagree. A
step's wording comes from `CleaningRecord.Change.summary(quoting:)`, which both use.

A missing score is said, not shown as a number: a transcript whose timed words do not spell its
text is read as `not scored`, never as every word at 1.00.

## Pieces and the join

`uttrflow-dev explain --pieces <clip>` cuts the clip where `SpeechWindowing.standard` cuts a
finished recording, recognises each piece, and hands the pieces to `DictationPipeline.trace`,
which tidies and joins them with the functions a dictation's pieces go through, with no
personal dictionary. `PieceTrace` lays out what each stage made of the words:

| Label | Stage | What the line says |
|---|---|---|
| `piece N` | recogniser | the piece exactly as recognised |
| `dictionary` | dictionary | the piece after the user's spellings, when they changed it |
| `step`, `skipped`, `failed`, `refused`, `model said`, `off` | tidier | as above, for this piece |
| `tidied by`, `tidied` | tidier | the engine kept for this piece, and what it wrote |
| `rejoined` | units | each piece after a number, time or address cut by a pause was tidied again whole, when one was |
| `joined` | `PieceJoiner` | the pieces laid end to end, with the seam stops and casing the joiner wrote |
| `at seams` | dictionary | the joined text after corrections across a seam, when there were any |
| `message` | message passes | the joined text finished once as one message |
| `result` | output | the text that would be inserted, or `nothing writable` |

A seam defect shows as the first line where the joined text differs from what the pieces
said; `PieceTraceTests` replays a recorded seam cut (`Docs/piece-seams.md`) this way. The
pieces are recognised one by one after the clip ends, so a piece can be heard differently
from a live dictation, which recognises while the key is held.

## Where the words go

Nowhere but the terminal. The command writes no log line and no file; redirecting its output is
the only way the text reaches the disk, and that is the person's choice. `make log-audit` and
`make offline-audit` hold the rest of the app to the same promise.

## What it does not show yet

- **A refused model's raw answer.** `model said` is the answer that was kept; a refused answer
  reaches the trace as its reason only. `uttrflow-dev clean --explain` asks the model
  separately and prints every guard check's verdict on its answer
  ([ai-model-output.md](ai-model-output.md#the-checks-are-one-ordered-list)).
- **An in-app view.** The trace is a developer command; there is no switch for it in the app.
- **The personal dictionary.** Doubtful runs are read with the standard sources only, so a
  reading the user's own dictionary would offer is not listed.
