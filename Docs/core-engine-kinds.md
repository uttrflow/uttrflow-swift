# Which transformer kinds a build contains

A transformer is a clean-up engine: it turns a raw transcript into the text that is inserted.
`TransformerKind` in `Sources/UttrflowCore/Models/EngineKinds.swift` names every kind a
configuration can mention, `TransformerKind.selectable` lists the ones compiled into this
binary, and `EngineConfiguration.resolvedTransformerPreference`
(`Sources/UttrflowCore/Models/EngineConfiguration.swift`) filters the stored preference through
it. `TextTransformers.all()` in `Sources/UttrflowAI/TextTransformers.swift` is the one place that
builds the concrete engines.

## Why the preference is filtered

A stored preference can name an engine this binary does not contain: a configuration written
by another build, or the shipped default itself. Unfiltered, the router drops such an entry
silently, so the configuration says one thing and the product does another. The router,
the Settings choices and Diagnostics all read `resolvedTransformerPreference`, so all three
show the order that actually runs.

## The kinds

| Kind | Selectable | Why |
|---|---|---|
| `.localModel` | always | The open-weight model through MLX; available only while its weights are loaded, so a dictation never waits on a load or a download. |
| `.foundationModels` | always | Apple's on-device model. |
| `.rules` | always | Deterministic punctuation, capitalisation and filler removal; the floor every preference ends in. |
| `.cloud` | never | No build contains a hosted engine; the case remains only so a stored record or preference naming it still decodes, and the preference drops it. See [`offline.md`](offline.md). |
| `.untidied` | never | Not an engine: it is what a record says when every engine was starved or refused and the transcript went in as heard. |

`EngineConfiguration.default` is `[.localModel, .foundationModels, .rules]` with WhisperKit for
speech: the local model while it is loaded, Apple's model when it is not or declines, rules as
the floor.

## The local model is one protocol and one setting

`UttrflowAI` cannot import `UttrflowLocalModel`, where MLX is quarantined, so the app target
builds the model and hands it to `TextTransformers.local` as an `any CleanupModel`. The one
implementation is `MLXCandidateScorer`, which also serves suggestions, so the app holds one copy
of the weights. Which weights it loads is configuration, not code: `LocalModel.configured` reads
the `LocalModel` defaults key, matched by repository path or short name against
`LocalModel.candidates`, and falls back to `LocalModel.standard`. A model of similar memory and
compute cost is swapped in by naming it there; a new candidate is one catalogue entry.

Hindi does not need it. Apple's model handles Hindi although Apple's own language list omits
it, so `AppleFoundationCleanupModel.verifiedBeyondApplesList` adds it. The measurement is in
[`bakeoff.md`](bakeoff.md), "Apple's model can do Hindi, and Apple does not say so".
