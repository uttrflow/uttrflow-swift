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

## Where the words go

Nowhere but the terminal. The command writes no log line and no file; redirecting its output is
the only way the text reaches the disk, and that is the person's choice. `make log-audit` and
`make offline-audit` hold the rest of the app to the same promise.

## What it does not show yet

- **Pieces.** The app tidies a long dictation in pieces and joins them; `explain` tidies the
  whole clip as one message, so a defect in how pieces join is not reproduced here.
  `uttrflow-dev dictate` plays a clip through the piece path.
- **A refused model's raw answer.** `model said` is the answer that was kept; a refused answer
  reaches the trace as its reason only. `uttrflow-dev clean --explain` asks the model
  separately and prints every guard check's verdict on its answer
  ([ai-model-output.md](ai-model-output.md#the-checks-are-one-ordered-list)).
- **An in-app view.** The trace is a developer command; there is no switch for it in the app.
- **The personal dictionary.** Doubtful runs are read with the standard sources only, so a
  reading the user's own dictionary would offer is not listed.
