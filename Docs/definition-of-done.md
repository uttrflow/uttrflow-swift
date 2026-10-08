# Definition of done

This page lists the product requirements Uttrflow was built against and says how each one is
held in code: by which type, which test, or which command. The original requirements document
is not in this repository, so the list is **reconstructed, not quoted**. Each `§` number is
the section of that document a requirement came from. §15, §16, §19 and §20 are still cited
in source comments (`DictationState`, the engine-name tests, `FallbackRunner`, `uttrflow-dev
transcribe`); the others are recorded only here. The wording is the implementer's, not the
original's.

That limit cuts one way: **this page can only check promises somebody wrote down.** A
requirement nobody implemented left no trace, so it cannot appear here. Read it as an audit of
the product against its own claims, not as proof of coverage.

The verdicts come from running the check named beside each promise. *Enforced* means held in
code and covered by tests; *Deviation* means a deliberate, current departure from the promise,
explained under Deviations; *Measured* means a number exists and the page holding it is named.

## The promises

| § | The promise | How it is held | Verdict |
|---|---|---|---|
| 9 | Meaning must not change | `MeaningPreservationGuard` (`Sources/UttrflowAI/MeaningPreservationGuard.swift`) refuses a tidy-up that drops or invents content; English and Hindi number words are equated, so "बीस" written as "20" does not read as invention | Enforced |
| 14 | Never overwrite what the user did not select | `FocusedTextField` exposes exactly two mutating operations: `replaceSelection(with:)`, and `replaceSelection(replacing:with:)` for a completion, which `SelectionWriter` implements by moving the selection backward over the preceding text only after confirming that text is there, then replacing it in one write | Enforced: `Tests/UttrflowInputTests/SelectionWriterTests.swift` covers both operations, including the refusal to move over text that does not match |
| 15 | The interface draws the dictation's state | `DictationState` in `Sources/UttrflowPipeline/DictationState.swift`: `idle`, `recording`, `transcribing`, `tidying`, `inserting`, `inserted`, plus `failed` as a way of leaving rather than another kind of progress | Enforced |
| 16 | The user never learns which engine ran | Seven test files scan every string on every pane, page, menu and error for engine, model and vendor names; Diagnostics names capabilities ("Downloaded speech model"), never a product | Enforced |
| 19 | Whatever fails, the user's words stay reachable | `FallbackRunner` under insertion; a failed tidy-up inserts the raw transcript; a failed insertion keeps the text in history and points the user to Recent | Enforced |
| 20 | Report idle memory, memory with the speech model loaded, and the language model's cost | `uttrflow-dev transcribe` prints idle, ready and peak memory for each run; `uttrflow-bakeoff profile` measures memory, peak, latency by length and a leak check | Measured: `Docs/performance.md` holds the speech-model and suggestion-model figures |
| 22 | The numbers are for reading on this Mac, never sent | Diagnostics is in memory and bounded; nothing serialises or uploads it | Enforced; `Docs/offline.md` has the network audit |
| 29 | No audio saved | See Deviations | Deviation; the privacy copy says what is true, held by `SettingsPrivacyCopyTests` |
| 31 | No small fallback language model | No build assembles the local model: `TransformerKind.selectable` (`Sources/UttrflowCore/Models/EngineKinds.swift`) never offers `.localModel`. `Docs/core-engine-kinds.md` | Enforced |
| 32 | The requirements' own worked example | Corpus case `late-to-meeting` | Enforced, and checked live below |

## §32, checked against the running product

```bash
uttrflow-dev clean "hey john um i'll probably be about 20 minutes late to the meeting because the deployment is still running"
```

```
raw    hey john um i'll probably be about 20 minutes late to the meeting because the deployment is still running
clean  Hey John, I'll probably be about 20 minutes late to the meeting because the deployment is still running.
by     foundationModels in 2.25s
```

That is the required output exactly: the filler is gone, the comma after the name is there,
nothing else moved. The time is one run on one Mac; `Docs/performance.md` has the measured
latencies.

## Deviations

Each deviation is deliberate and current. The page named beside it holds the measurement.

- **§15 recording panel.** The floating button *is* the recorder: it changes into its
  listening form while a dictation runs, so one thing moves on screen rather than two.
  `Docs/app-dock.md` has the forms.
- **Context does not turn speech into SQL.** The largest deviation, and the one that
  narrows the product most. Every prompt wording strong enough to produce SQL also
  invented content the speaker never said, and wordings with SQL examples leaked SQL into
  dictations with no context at all. Context therefore does spelling only. The corpus case
  `sql-editor-totals` still expects SQL and still fails; that score is this decision, not a
  defect. `Docs/bakeoff.md`, "The PRD says a sentence may become SQL. It does not,
  deliberately."
- **§29 no audio saved.** Each dictation's audio is written beside the live buffer and
  deleted the moment its words land; it is kept for a day only when some of the words were
  lost, including a piece of speech left out of words that did land, so the dictation can be
  retried. Nothing leaves the Mac. `Docs/recordings.md`.
- **§31 no small fallback model.** A local open-weight model ships, because Hindi clean-up must
  run on the Mac. `Docs/bakeoff.md`.

§31 is not a deviation: no build assembles the local model (see the table above).

## What this page cannot tell you

- Whether a requirement exists that nobody implemented. No trace, no row.
- Whether the wording above matches the original document's. It is a paraphrase written by
  whoever satisfied the requirement.
- Anything about §1–8, §10–13, §17–18, §21, §23–28 or §30. Nothing in the code or on this
  page cites them; they may have been satisfied without comment, or may not have existed.
