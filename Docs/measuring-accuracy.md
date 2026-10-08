# Measuring speech accuracy

Speech accuracy is measured by reading a fixed set of passages aloud once, then running every
speech-engine change over the same recordings and comparing word error rates against a stored
baseline. The passages are `TranscriptionCorpus` (`Sources/UttrflowEval/TranscriptionCorpus.swift`),
the scorer is `TranscriptionScorer` and the gate is `AccuracyBaseline` and `PairedBootstrap`
(`Sources/UttrflowEval/`), and the command is `uttrflow-eval` (`Sources/uttrflow-eval/`). How each
measurement decision is made is in [`eval-methodology.md`](eval-methodology.md); the edit distance
itself is in [`core-word-error-rate.md`](core-word-error-rate.md). To pick the command a given
change needs, start at [measure-a-change.md](measure-a-change.md); the targets a measurement is
held to are in [accuracy-targets.md](accuracy-targets.md).

## What exists

| Piece | Where |
|---|---|
| The passages to read | 18, in `TranscriptionCorpus.swift` |
| A scorer that enforces `mustKeep` | `TranscriptionScorer` |
| Recording, offline | `uttrflow-eval record` |
| Scoring, offline | `uttrflow-eval transcribe` |
| A regression gate | `transcribe --baseline … --fail-on-regression` |

No recordings are committed. Each contributor records their own (below).

## The corpus

| Language | Passages | Words |
|---|---|---|
| English | 6 | 302 |
| Hindi | 6 | 201 |
| Hinglish | 6 | 183 |

Five stressors are spread across them: everyday speech, proper nouns, digits, technical terms and
false starts. Recognisers usually regress on names and numbers first, and both are isolated.

`TranscriptionCorpus.estimatedReadingTime` allows 120 words a minute plus thirty seconds a passage
for settling and retakes: 686 words over 18 passages is about 14.7 minutes of reading.
`uttrflow-eval record --list-passages` prints the passages to read through first.

## Why one reader is enough for a regression check

A claim about the product — how well it hears Indian-accented English, say — needs many speakers
in many settings. Deciding whether an engine change made things worse needs much less: the same
voice, passages and room before and after. Every source of variance except the engine is held
constant, so a difference is attributable to the engine. The larger multi-speaker corpus in
[`operator-runbook.md`](operator-runbook.md) is for claiming an accuracy number, not for catching
a regression.

## Running it

Both defaults are local; nobody needs `CORPUS_BUCKET` or an operator token to measure a change.

```bash
# once, about 15 minutes
uttrflow-eval record --corpus-path ./corpus --cohort <reader>-quiet \
                     --speaker <label> --setting "quiet room, built-in mic"

# once, to record the baseline
uttrflow-eval transcribe --corpus-path ./corpus \
                         --baseline ./baseline.json --save-baseline

# after a change, to compare
uttrflow-eval transcribe --corpus-path ./corpus \
                         --baseline ./baseline.json --fail-on-regression
```

- **`record` writes to disk first.** `--upload` offers each take to the corpus service as it is
  accepted, and `--sync` later sends whatever `--upload` could not, recording nothing itself. The
  local write is the commit, so a dead connection costs an upload and never a take.
- **`transcribe` reads local recordings by default.** `--from-catalogue` reads the backend's
  catalogue instead.

## What the gate says

`--fail-on-regression` exits non-zero when any slice's 95% paired-bootstrap interval for the change
in rate lies wholly above zero. Every slice prints its interval and the smallest change its sample
can detect; a slice whose interval holds zero reports "no change detectable". Results are reported by language, by stressor and by cohort and
never pooled: an engine that improves on English and regresses on Hinglish has not improved.

A run the gate cannot judge also exits non-zero, because no verdict is not "no regression": a
different label, no shared samples, a changed recording, or a baseline or run whose normalisation
rules are not recorded. The printed reason names which side needs re-measuring.

The gate checks the exact recording set, not only the case IDs. Every score carries a
`recordingIdentity` — a digest of the WAV bytes for a local take, the catalogue's own key for a
backend sample — and `--save-baseline` stores it per passage. When a shared case ID's identity
has changed, the passage was read again since the baseline, and the gate reports the comparison
as unverifiable rather than as a pass or a regression. A baseline with no identities is reported
the same way against a run that has them.

## The committed baseline

`make accuracy-gate` synthesises the English passages with the `say` voice Samantha, transcribes
them with the installed shipping model and compares with `Scripts/accuracy_baseline.json`. It
needs no recordings, so every Mac with the model can run it; a Mac without the model stops at
"is not installed". The baseline's label names the model variant, and each passage's
`recordingIdentity` pins the synthesised audio, so a macOS release that changes the voice reports
"unverifiable", not a pass. Each slice with at least two shared passages gets an interval; a slice of one
passage reports as too few utterances to judge. Recorded speech is not in this baseline.

Measured on an Apple M5 Pro, 48 GB, macOS 26.5.1, with
`openai_whisper-large-v3-v20240930_turbo_632MB`: 3.6% word error rate over 6 passages, two runs
identical. A baseline is replaced only through `--save-baseline` in the change that moves it.

## The release report

`make accuracy-report VERSION=<version>` renders `Scripts/accuracy_baseline.json` as
`Docs/accuracy-reports/<version>.md` and records the baseline as one line of
`Docs/accuracy-history.json`, so the next release's report compares with it. The report gives the
rate per language, stressor and cohort, never pooled, each with its case count, reference words and
95% interval; a slice under 100 reference words, or of one case, prints as "too small to judge".
It names the recogniser, the normalisation rules, a digest of the exact recordings, and its own
limits. `Scripts/release_notes.sh` links the report for the version it renders. The renderer is
`AccuracyReport` in `Sources/UttrflowEval/AccuracyReport.swift`, which compares releases with the
same paired bootstrap as the gate.

## The recogniser's version is pinned

`Package.swift` pins WhisperKit with `exact:`, as it pins Sparkle, so no dependency update changes
how dictation is decoded without somebody deciding it. `WhisperKitContractTests`
(`Tests/UttrflowSpeechTests/`) asserts what the product relies on from it: the 224-token context
window, the prompt cap `VocabularyPrompt` sizes itself to, the prefill `DecoderPrefill` counts,
the fallback and acceptance thresholds, and every decoding option the product names. Those fail a
build when upstream moves them; whether the words still come out right needs the corpus.

## Public datasets are not the baseline

Permissively licensed speech datasets are not used for the regression check:

- None contains Hinglish, a third of this corpus and the part most likely to regress.
- Their reference text carries no `mustKeep` requirements — the names, versions and terms these
  passages are written around — so they would measure a different thing.
- They answer how an engine does across many voices, not whether a change broke anything.

They fit the accent axis of the larger corpus, not the before-and-after check.

## Why the audio is not committed

Size is not the obstacle — 686 words is about 5.7 minutes of speech, about 11 MB as 16 kHz mono
WAV. **A voice recording is personal data**: biometric, identifiable, and impossible to withdraw
once published, and `Scripts/pii_audit.sh` reads text, so `make audio-audit` refuses one instead. A regression
check compares one voice before and after, so each contributor's own fifteen-minute recording is
all it needs.
