# Dictation quality: the layers, and where each one lives

Dictation accuracy is not one component. It is seven layers, each with one job, one home in the
tree, a time budget and a metric from [accuracy-targets.md](accuracy-targets.md). Work on accuracy
names the layer it changes, stays inside that layer's home, and reports that layer's metric before
and after. The order the stages run in, and why, is [pipeline.md](pipeline.md); this page is the
map from a layer to its code, its limit and its number.

## The layers

| Layer | Its one job | Where it lives | Budget | Metric | Detail |
|---|---|---|---|---|---|
| Recogniser bias | condition the recogniser on the user's own words before it decodes | `Sources/UttrflowSpeech/VocabularyPrompt.swift`, `Sources/UttrflowDictionary/WorkingSet.swift`, `Sources/UttrflowSpeech/VocabularySource.swift` | inside `StageTimeout.transcription` | `wer-biased`, `wer-unbiased` | [speech-vocabulary-prompt.md](speech-vocabulary-prompt.md) |
| Evidence capture | record what the recogniser can say about a doubtful word | `Sources/UttrflowSpeech/`; the probe is `Tests/UttrflowSpeechTests/DecoderEvidenceProbeTests.swift` | inside `StageTimeout.transcription` | `wer` | [decoder-evidence.md](decoder-evidence.md) |
| Candidate generation | propose the words a doubtful run might have been | `Sources/UttrflowAI/Candidates/` (`CandidateSource` and its sources), over the phonetic index in `Sources/UttrflowDictionary/` | inside `StageTimeout.quick` | `entity-loss` | [app-dictionary.md](app-dictionary.md) |
| Scoring | score the heard reading against each candidate reading | `Sources/UttrflowAI/CorrectionEvidence.swift` | inside `StageTimeout.quick` | `override-error` | [ai-correction-thresholds.md](ai-correction-thresholds.md) |
| Override gate | let a word move only when every condition holds; otherwise do nothing | `WordCorrectionEngine` in `Sources/UttrflowAI/CorrectionEngine.swift`; for the tidier, `Sources/UttrflowAI/MeaningPreservationGuard.swift` | `StageTimeout.quick` (correct), `StageTimeout.transformation` (tidy) | `override-error`, `meaning-change` | [ai-correction-thresholds.md](ai-correction-thresholds.md), [mutation-guard.md](mutation-guard.md) |
| Formatting | add the punctuation, case and layout speech leaves implicit, for the destination | `Sources/UttrflowAI/Passes/`, `Sources/UttrflowCore/Cleaning/`, `Sources/UttrflowCore/Models/DestinationFormatter.swift`, `Sources/UttrflowPipeline/PieceJoiner.swift` | `StageTimeout.transformation` | `formatting`, `seam-artefact`, `cosmetic` | [cleanup.md](cleanup.md), [cleanup-design.md](cleanup-design.md), [adapters.md](adapters.md) |
| Fallback | when a layer fails or times out, keep what was said | `Sources/UttrflowPipeline/DictationPipeline+Cleaning.swift`, `Sources/UttrflowAI/TransformerRouter.swift`, `Sources/UttrflowCore/Script/LatinScript.swift` | every `StageTimeout` | `meaning-change`, `latin-output`, `silence-insertion` | [pipeline.md](pipeline.md), [latin-output.md](latin-output.md), [silence.md](silence.md) |

The budgets are the values of `StageTimeout`, listed per stage in [pipeline.md](pipeline.md); the
end-to-end limit is `tail-latency`, set in [performance.md](performance.md). A layer that cannot
meet its budget is cancelled and the fallback answers; no layer extends another's budget.

## Turning a layer on and off

Each switchable layer is a case of `QualityLayer` in
`Sources/UttrflowCore/Support/QualityLayer.swift`, with its default state, the stage budget it runs
inside and a one-line summary. `QualityLayers` resolves which are on from those defaults, overridden
only by the local defaults key `QualityLayer.<name>` (`-QualityLayer.<name> NO` for one launch),
never from a network source. `QualityLayers.ablation(only:without:)` builds the set a bake-off or
eval run asks for, and refuses an unknown name. A new layer is added as a case with `defaultOn`
false, measured, then turned on in a reviewed pull request. `persona-vocabulary` is such a case inside
recogniser bias: it ranks the prompt's words by the persona projection in
[learned-state.md](learned-state.md#the-persona-projection).

`DictationPipeline` takes the set as `layers` and a layer that is off leaves its stage's input as it
came: recogniser bias off sends the recogniser no vocabulary; evidence capture, candidate
generation, scoring or the override gate off stops the dictionary moving any word; formatting off
leaves each piece untidied. `uttrflow-bakeoff --layers a,b` runs only those layers and
`--without a` drops one; the run header names the layers it had on, results of a non-default set are
stored apart, and `--against` refuses a baseline run with other layers unless
`--allow-difference layers`. Each layer's latency budget is the p95-plus-headroom row of the stage it
runs in, mapped in `LAYER_STAGES` in `Scripts/perf_budget_audit.py`; the audit fails a layer with no
stage or a stage with no row, and prints each layer still awaiting a measurement with its reason.
`QualityLayer.inputs` names the layers each one reads; every default-on layer off alone, and with
each layer it reads, must keep the corpus above the floor, as
[degraded-path-matrix.md](degraded-path-matrix.md) reports.

Each of those paths is also paired against the default set (`LayerContribution`,
`Sources/UttrflowEval/LayerContribution.swift`): the change in failed-case rate and in invented,
deleted and lost words with the layers off, each with its paired-bootstrap interval and minimum
detectable change, the false overrides the layers make and the latency they add. A layer is kept
only when an improvement's interval excludes zero and no measure's interval lies wholly below it;
the override gate, which exists to prevent harm, is judged by the meaning-changing errors it
prevents alone. Any other layer is listed for removal. The table without latency is generated into
[degraded-path-matrix.md](degraded-path-matrix.md#each-layers-marginal-contribution); with latency,
`make release-quality` adds it to `dist/release-quality.md`.

## Rules that hold across every layer

1. **Doing nothing is the default.** A layer that is unsure leaves the words as heard. Only the
   override gate may move a word, and only the formatting layer may add marks or layout.
2. **One home per layer.** A second implementation of a layer's job elsewhere in the tree is a
   defect; the change that finds one deletes it
   ([code-quality.md](agents/code-quality.md#fixing-a-defect)).
3. **No case keyed to a phrase, an app or a fixture.** A layer's behaviour comes from its evidence
   and the destination's rules, never from matching a known input.
4. **Each layer is measured by its own metric.** A change reports that metric before and after with
   the command from [measure-a-change.md](measure-a-change.md). A metric marked "not measured" in
   [accuracy-targets.md](accuracy-targets.md) is reported as not measured, never as zero.

## Adding a pass

A new cleaning is a new pass, not a new branch in the pipeline.

1. Name the layer it belongs to from the table above. If it fits none, it is not a pass; raise it
   in an issue first.
2. Write the failing case first, in the tests for that layer's home.
3. Add the pass as a `CleaningPass` with its own `PassID` in `Sources/UttrflowAI/Passes/`
   ([cleanup-design.md](cleanup-design.md)); a destination-specific rule goes in the destination's
   adapter ([adapters.md](adapters.md)).
4. Run `make bakeoff`, then `make bakeoff ARGS="--against <saved-result.json>"`, and put the
   layer's metric before and after in the pull request.

## Where each new component lives

A component's module is decided here before its first file lands, because the first file's imports
become the module's dependencies. Each row names the module, the protocol lower modules read it
through, and who may import the module. A type that a change creates names its module from this
table; a component not listed is added here first.

| Component | Module | Read through | Who may import the module |
|---|---|---|---|
| Clause analyser | `UttrflowCore` (`Sources/UttrflowCore/Cleaning/`) | its own types | any module |
| Destination adapter registry | `UttrflowCore` (`Sources/UttrflowCore/Adapters/`) | its own types | any module |
| N-gram data reader | `UttrflowCore` | its own types | any module |
| Persona store | a new leaf `UttrflowPersona`, depending on `UttrflowCore` only | a read-only `PersonaReading` protocol in `UttrflowCore` | the app target and `UttrflowSettings`; never `UttrflowSpeech` or `UttrflowAI` |
| Hypothesis reranker, candidate scorer, language model | `UttrflowAI` | its own types | `UttrflowPipeline` and above |
| Override gate | `UttrflowAI` (beside `WordCorrectionEngine`) | its own types | `UttrflowPipeline` and above |
| Seam decider | `UttrflowPipeline` (beside `PieceJoiner`) | its own types | the app target |

The dependency rules these placements keep:

1. `UttrflowSpeech` imports `UttrflowCore` and `UttrflowDictionary` only; never `UttrflowAI`.
2. No dictation module (`UttrflowSpeech`, `UttrflowDictionary`, `UttrflowAI`, `UttrflowPipeline`)
   imports `UttrflowPredict` or anything that depends on it, so `UttrflowSettings`,
   `UttrflowContext` and `UttrflowInput` are never their dependencies.
3. No dictation module imports `UttrflowLocalModel`; a scorer or language model on the dictation
   path is not MLX-backed ([offline.md](offline.md)).
4. A lower module that needs data owned higher up reads it through a protocol in `UttrflowCore`,
   and the app target injects the implementation.

The dependency graph is `Package.swift`; `make layering-audit` checks UI imports and platform
dependencies, not these rules.

## Where fitting lives

Every fitted parameter a layer ships (reranker weights, the doubt detector, the override-gate
margin, n-gram counts) is fitted in Swift, in `UttrflowEval` (`Sources/UttrflowEval/Fitting.swift`),
and run through `uttrflow-eval`. A fit reads the same `TextNormaliser`, `WordErrorRate` alignment,
phonetic keys and feature code the app ships; no second normaliser, aligner or feature extractor
exists for fitting, in Swift or in `Scripts/`.

| Model family | Fit | Home |
|---|---|---|
| Linear scorer over fewer than 20 features | L2-regularised logistic regression | `LinearScorer.fit` |
| Monotone calibration map | pool-adjacent-violators | `MonotoneCalibration.fit` |
| Count table | a dictionary of counts | the layer's own reader format |

A fit is bit-reproducible: the same rows give the same artifact digest in any process, on any
thread count and on any Apple silicon Mac. Rows are read in the caller's array order, never by
iterating a `Dictionary` or `Set`; sums run on one thread in that order; ties sort by a stated key
(`MonotoneCalibration.fit` puts wrong before right at an equal score); a fit draws no randomness,
and one that must draws from a seed it stores in its record. Stored floats keep 12 significant
digits (`FitArtifact.stored`) and `digest` hashes that form, so a last-bit difference cannot change
it. `FittingTests` pins the fixture's digest and refits on eight threads at once; it runs without
`SWIFT_DETERMINISTIC_HASHING`.

Fitting adds no dependency. A step that cannot be done in Swift (for example a one-off model
conversion) names itself in its issue, pins every package by hash, and states how dependency
scanning covers it, because `osv-scanner` and dependency review read only `Package.resolved`.

Measured on an Apple M5 Pro with 48 GB, under full CPU load from other builds, `swiftc -O`, one
thread, synthetic rows of 20 features:

| Fit | Rows | Time |
|---|---|---|
| `LinearScorer.fit`, 200 iterations | 100,000 | 7.7 s |
| `LinearScorer.fit`, 200 iterations | 1,000,000 | 40.2 s |
| `MonotoneCalibration.fit` | 1,000,000 | 0.17 s |
| Bigram-shaped count table | 5,000,000 increments | 1.3 s |

The largest fit is under one minute, against a ten-minute limit on a 16 GB Mac.

## Training labels

A passage read aloud is the label only where the reader said it. `TrainingLabels.label`
(`Sources/UttrflowEval/TrainingLabels.swift`) labels each span of the `WordErrorRate` alignment
`correct`, `substituted` (with the passage word), `dropped` or `inserted`, and marks an error
unreliable when an independent decoding of the same speech (another engine, or another take by the
same cohort) makes the same error at the same passage word: two decoders agreeing against the passage
is a skipped, repeated or swapped word, not a recognition error. Unreliable spans never reach a fit
row; the table records how many were kept out (`excludedSpans`) and `uttrflow-eval fit` prints it.
Spelling variants are handled by the `TextNormaliser` the scorer uses, not by the labeller.

## Fit tables

The recordings are personal data and are not committed, so a fit is reproduced from a
text-free table instead (`Sources/UttrflowEval/FitTable.swift`). A row holds a salted ordinal,
the split, the language, a closed label class and the feature vector; the table names the
feature spec version. `FitTable.read` refuses any field outside that schema, any string outside
its closed set, rows of different widths, and any table over 5 MB. Only development rows are
fitted.

```bash
uttrflow-eval fit --from-table <table.json> --expect <digest>   # exits 1 when the digest differs
```

`Tests/UttrflowEvalTests/FitTables/invented-linear.json` is an invented 240-row table
(25,269 bytes) whose fit `FitTableTests` pins to a weights digest.

Before committing a table, the reviewer checks:

1. It reads with `FitTable.read` and its fit matches the digest committed beside the artifact.
2. Rows per split, language and label group are stated in the pull request; 0 groups have
   fewer than 5 rows, so no rare combination singles out a speaker.
3. Ordinals were salted at reduction time and map to no recording or passage identifier.
4. `make pii-audit` and `make disclosure-audit` pass with the table staged.

## How much data a fit needs

A fit below its data floor still prints numbers that look like results, so every fitted layer
states its floor in `FittedLayer.floor` (`Sources/UttrflowEval/FitFloor.swift`). No fitted
artifact is shipped below its floor; until it is met the layer ships dark, off by default (see
"Turning a layer on and off"). A cell is one split
(`development`, `heldout`) for one language; every cell of every language must meet the floor, so
a layer never ships on one language's evidence.

| Layer | Unit | Rows per parameter | Wrong rows per cell | Rows per cell | Parameters | Item |
|---|---|---|---|---|---|---|
| `span-reranker` | labelled span | 10 | 30 | 0 | one weight per feature, plus a bias | 1.2 |
| `doubt-detector` | labelled span | 10 | 100 | 0 | one weight per feature, a bias and up to 10 calibration steps, each needing about 10 wrong spans | 1.9 |
| `context-ngram` | text sentence | 0 | 0 | 2,000 | counts only, no labels | 1.11 |
| `masked-scorer` | labelled span | 0 | 2,000 | 0 | about 20 million, so thousands of wrong spans per cell rather than a ratio | 1.12 |
| `override-gate` | decision | 10 | 30 | 300 | a calibration temperature and a threshold; 300 decisions bound the false-override rate under 1 in 100 with zero failures, and certifying the 1 in 1,000 target takes the 2,995 in [accuracy-targets.md](accuracy-targets.md#the-targets) | 1.13 |
| `person-offset` | decision | 10 | 0 | 0 | one bounded offset, learned per person from reverts and undos, so 10 of them before it moves | CM.33 |

`uttrflow-eval fit` prints the right and wrong rows in every cell and, when any count is under the
`span-reranker` floor, names each one with its shortfall and exits 1 without fitting:

```text
heldout english: 8 right, 8 wrong
below the span-reranker floor in Docs/dictation-quality.md; not fitted:
  wrong rows in heldout english: 8, needs 30 (22 short)
```

`FitFloorTests` checks that this table matches `FittedLayer.floor`.

### What the corpus yields

`LabelYield.measure` reads recogniser errors per 1,000 reference words from a baseline, per
language, with the 95% interval from resampling whole passages. A word error is the most a
passage can yield: a labelled wrong span may cover several errors, and a reranker row also needs
the right word among the candidates. From the committed baseline (`Scripts/accuracy_baseline.json`,
synthesised English, 6 passages):

| Language | Errors | Words | Per 1,000 words | 95% interval |
|---|---|---|---|---|
| English | 11 | 305 | 36.1 | 6.9 to 71.2 |
| Hindi | not measured: no committed baseline | | | |
| Hinglish | not measured: no committed baseline | | | |

At 120 words a minute (`LabelYield.wordsPerMinute`, the rate `TranscriptionCorpus` costs reading
at), the minutes of English reading or synthesised audio each floor's wrong spans cost, over both
splits, at the yield and at the interval's low end:

| Layer | Wrong spans per language | Minutes at 36.1 | Minutes at 6.9 |
|---|---|---|---|
| `span-reranker`, `override-gate` | 60 | 14 | 73 |
| `doubt-detector` | 200 | 46 | 242 |
| `masked-scorer` | 4,000 | 924 | 4,833 |

The whole corpus is 686 words, about 25 errors at this yield, so no fitted layer meets its floor
from it today. `context-ngram`
counts text and `person-offset` counts use, so neither is costed in reading.

### Choosing the override gate's threshold

A rate is never reported without the sample that bounds it: 0 wrong in 40 overrides does not
show a rate under 1 in 1,000. `uttrflow-eval calibrate-gate` reads a `decision` fit table, one
row per candidate the gate weighed with its score in one feature column and `wrong` marking a
false override, and weighs only the held-out rows (`GateCalibration`,
`Sources/UttrflowEval/GateCalibration.swift`):

```bash
uttrflow-eval calibrate-gate --from-table <table.json> --target 0.001 --confidence 0.95 --feature 0
```

Each distinct score is a threshold, strictest first; a threshold applies every candidate scored
at or above it. The bound on its false-override rate is the one-sided Clopper-Pearson upper bound
from its counts (`RiskBound`). Thresholds with fewer overrides than the target needs with none
wrong (2,995 for 1 in 1,000 at 95%) are left out before any label is read, and the rest are tested
in order: testing stops at the first whose bound is above the target, and the loosest one before
it is certified, so the size of the grid cannot inflate the claim. When none is certified, the
gate ships the strictest threshold and the report states the rate it is certified at instead.
Every report prints the decisions weighed, each threshold's bound and the smallest target the
split could certify. Today's gate thresholds the integer evidence margin of
`DoubtPolicy.OverridePolicy` ([ai-correction-thresholds.md](ai-correction-thresholds.md)), so its
grid is those margins; `GateCalibrationTests` checks the bound against published values.
