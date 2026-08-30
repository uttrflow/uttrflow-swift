# Making speech accuracy measurable

A proposal, written after WhisperKit 1.1.0 was declined because nobody could say whether
it was better or worse. This is about the smallest thing that would have answered that.

## The finding

**Almost all of it already exists.** The blocker is fifteen minutes of somebody reading
out loud, not the sixteen hours the operator runbook implies.

| Piece | State |
|---|---|
| The passages to read | **Written.** 18 of them, in `TranscriptionCorpus.swift` |
| A scorer, with `mustKeep` enforcement | **Written.** `TranscriptionScorer` |
| Recording tool that works offline | **Written.** `uttrflow-eval record` |
| Scoring tool that works offline | **Written.** `uttrflow-eval transcribe` |
| A regression gate for CI | **Written.** `--fail-on-regression --tolerance` |
| **The audio** | **Missing. This is the whole gap.** |

## Why the sixteen hours is the wrong number

The runbook says *"about a thousand samples, roughly sixteen hours"*, and that is why this
has never been started. But a thousand samples is **many speakers in many settings** —
statistical power to say *"Uttrflow hears Indian-accented English this well"*, which is a
claim about the product.

Deciding whether a version bump made things worse needs something much weaker: **the same
voice, the same passages, the same room, before and after.** Every source of variance
except the engine is held constant, so a difference is attributable. One reader is not a
weakness there; it is the design.

The repository already computes what that costs. `TranscriptionCorpus.estimatedReadingTime`
uses 120 words a minute plus thirty seconds a passage for settling and retakes:

```
18 passages · 686 words  →  14.7 minutes
```

| Language | Passages | Words |
|---|---|---|
| English | 6 | 302 |
| Hindi | 6 | 201 |
| Hinglish | 6 | 183 |

Five stressors are covered: everyday speech, proper nouns, digits, technical terms, and
false starts. Those are exactly the axes on which recognisers differ — a model that
regresses usually regresses on names and numbers first, and both are already isolated.

**So the minimum viable corpus is the one already written. It needs reading once.**

## It already works without the backend

This was the other assumption worth checking, because it is what stops a contributor
running any of it. Both defaults are already the local ones:

- **`record` writes to disk first.** `--corpus-path` is where recordings go; `--sync` is an
  opt-in extra that offers them to the corpus service afterwards. The comment in
  `RecordCorpus.swift` is explicit that the local write is the commit and uploading is
  layered on top, so a dead connection costs an upload and never a take.
- **`transcribe` reads local recordings by default.** `--from-catalogue` is the flag that
  goes to the backend instead. Nobody needs `CORPUS_BUCKET` or an operator token to measure
  a change.

Nothing has to be built for the offline path. It is the path.

## What it would take

```bash
# once, ~15 minutes
uttrflow-eval record --corpus-path ./corpus --cohort <reader>-quiet \
                     --speaker <label> --setting "quiet room, built-in mic"

# per engine change, unattended
uttrflow-eval transcribe --corpus-path ./corpus --engine whisperKit \
                         --baseline ./baseline.json --save-baseline

# afterwards, to compare
uttrflow-eval transcribe --corpus-path ./corpus --engine whisperKit \
                         --baseline ./baseline.json --fail-on-regression
```

`--fail-on-regression` exits non-zero when any slice has got worse, with `--tolerance` in
percentage points. Results are reported **by language, by stressor and by cohort** and are
never pooled into one number — an engine that improves on English and regresses on Hinglish
has not improved, and `AccuracyBaseline` already refuses to average that away.

## What this would have said about WhisperKit 1.1.0

The decision that could not be made, made:

```
uttrflow-eval transcribe --corpus-path ./corpus --engine whisperKit \
                         --baseline ./baseline-0.18.0.json --fail-on-regression
```

Three outcomes, each with an obvious next step:

- **No slice moves beyond tolerance.** The bump is neutral on accuracy, so it is judged on
  its costs alone — and 1.1.0 has one, a second copy of the Hugging Face download code
  linked into the app as `ArgmaxCore`. Neutral benefit against a real cost is a decline,
  but a decline for a stated reason.
- **Hinglish or proper nouns regress.** Decline, with a number, and a bug report upstream
  worth writing.
- **Something improves materially.** Now the `ArgmaxCore` duplication is a trade rather than
  a pure cost, and the conversation is about whether `Hub` can be dropped.

Today none of those can be reached, so the answer defaults to "no" for every speech-engine
change — which is a decision made by absence rather than on merit.

## Public datasets: later, and only for one axis

Common Voice (CC0) and LibriSpeech (CC BY 4.0) are both permissively licensed and could be
redistributed. They are **not** a shortcut here:

- Neither contains Hinglish, which is a third of this corpus and the part most likely to
  regress.
- Their audio comes with its own reference text, so the `mustKeep` requirements — the names,
  version numbers and technical terms these passages were written around — do not apply.
  A different thing would be measured.
- They answer *"how does this engine do on many voices?"*, not *"did this change break
  anything?"*

They earn their place later, for the accent axis, once there is a baseline to extend. Not
for the first fifteen minutes.

## Committing the audio: a real decision, not a detail

A corpus in the repository is what would let a contributor verify an engine change. Size is
not the obstacle — 686 words is about 5.7 minutes of speech:

| Format | Size |
|---|---|
| 16 kHz mono WAV (what the store writes) | ~11 MB |
| FLAC | ~5.5 MB |
| Opus, 24 kbps | ~1 MB |

**The obstacle is that a voice recording is personal data.** It is biometric, it is
identifiable, and publishing it is irreversible in exactly the way this repository has
already had cause to think carefully about. `Scripts/pii_audit.sh` would not catch it,
because it reads text.

Three options, and this is the operator's call:

1. **Do not commit it.** Contributors record their own fifteen minutes and get a baseline
   for their own voice — which is all a regression check needs, since the comparison is
   always before-and-after on one voice. Costs a contributor fifteen minutes; keeps nobody's
   voice in a public repository.
2. **Commit it, with the reader's informed consent**, understanding it cannot be withdrawn.
   Best reproducibility: everybody measures the same audio.
3. **Commit a public-dataset subset** for English only, and keep the Hindi and Hinglish
   recordings local. Reproducible for part of the corpus, silent on the part that matters
   most.

**Option 1 is the recommendation.** The corpus is fifteen minutes of reading; asking a
contributor who wants to change the speech engine to spend fifteen minutes is proportionate,
and it avoids publishing a voice for a benefit — shared audio — that a regression check does
not actually need.

## What is not proposed

No new tooling. Every command above exists. The gap is a recording session and a decision
about where the audio lives, and inventing a corpus format or a scoring harness to sit
beside the ones already written would be the opposite of the smallest thing that works.

The thousand-sample corpus in `Docs/operator-runbook.md` is still the right ambition for
claiming an accuracy *number*. It is simply not what is needed to catch a regression, and
conflating the two is what has kept both at zero.
