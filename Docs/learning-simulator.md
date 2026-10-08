# Learning simulator

`Tests/UttrflowAITests/LearningDynamicsSimulatorTests.swift` replays the invented week of dictations in
`Sources/UttrflowTestSupport/LearnedWordReplay.swift` (the same corpus the learned-word replay gate uses)
through the real `PersonalDictionaryStore.learn` for eight simulated weeks, then runs the real
`WordCorrectionEngine` over a persona-free held-out set after each week.

## Models

| Model | What lands |
|---|---|
| no learning | nothing is learnt |
| right persona | every edit as the corpus writes it |
| 20% wrong edits | one edit over a selection in five writes a misspelling (two inner letters swapped) |
| scripted page | one application rewrites the last word of every dictation into its own respelling |

Rates: doubted words at confidence 0.3, clear at 0.95; a wrong override is undone 70% of the time;
fixed seed 4513. The held-out set is 36 sentences of ordinary speech, every word right, with sound-alikes
of the persona's terms doubted and no screen context. Probes are the corpus's own mishearings, heard in
their window.

## Measured

Host: Apple M5 Pro, 48 GB. `swift test --filter LearningDynamicsSimulatorTests`, exit 0.

| Model | Entries at week 8 | Peak false overrides per 1,000 held-out words | Probes fixed | Most learnt in a day |
|---|---|---|---|---|
| no learning | 0 | 0.0 | 0/11 | 0 |
| right persona | 18 | 0.0 | 9/11 | 5 |
| 20% wrong edits | 28 | 0.0 | 9/11 | 6 |
| scripted page | 39 | 0.0 | 9/11 | 7 |

No learning model makes a false override on the held-out set: wrong edits and the scripted page add
entries but no held-out harm, because a single-word candidate without screen evidence never wins a
decisive reason, and no entry is undone.

## Ceiling

Learning may add at most 6 false overrides per 1,000 persona-free words over no learning, at any week.
The test fails above it.

## Constants chosen from the curves

- **Provisional promotion count: 3 uses without undo.** Fitted in
  [app-dictionary-store.md](app-dictionary-store.md#provisional-words): every real term survives 8
  uses with no undo, so any count up to 8 promotes all of them; 3 matches the use floor
  `isTrustworthy` already applies and promotes a term used weekly in its third week.
- **Daily cap: 3 learnt entries per day.** The right persona never learns more than 3 in a day; the
  scripted page learns 7, so the cap holds back more than half of a rewriting page's day.
