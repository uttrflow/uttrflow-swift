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
false, measured, then turned on in a reviewed pull request.

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
