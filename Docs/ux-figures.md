# The figures on Dictation and Insights

`DictationPresenter` in `Sources/UttrflowUX/MainDictationPresentation.swift` computes the
rail figures; Insights reuses the same arithmetic. The rule for every figure: nothing is
shown that was not measured. There is no "time saved" tile because Uttrflow has never
watched the user type.

## Left as dictated

The figure this page used to call accuracy. Both halves of the fraction count *spoken* words and
both are read out of the same value:

```
accuracy = (spokenWords - correctedWords) / spokenWords
```

`RecordedChanges.correctedWords` counts distinct positions within the utterance, so the
subtrahend cannot exceed the denominator whatever is on disk. There is deliberately no
`max(_, 0)` under the division: a clamp there would turn a units mismatch into a
plausible-looking zero, which is how an earlier mismatch (finished-text words as the
denominator against heard words as the subtrahend) once reported 0% for "the s q l query"
with SQL in the dictionary.

Only measured dictations count. A dictation whose insertion failed reports no changes —
nobody was keeping a record — and counting its words in the denominator while its
corrections cannot appear in the numerator would report an accuracy higher than the truth.
A dictation whose `spokenWords` is `nil` is left out on the same grounds. The figure is
`nil` when nothing has been measured or nothing was said.

The caption says "as you said them", not "as you wrote them": the denominator is the
utterance, so a dictation the dictionary improved is not penalised for coming out shorter.

**It is not accuracy, and it no longer says it is.** The fraction measures how little the clean-up
altered the transcript, and a recogniser that mishears a word the clean-up then leaves alone scores
it 100% — which is exactly what happened to the product's own name before the dictionary shipped
knowing it. `Docs/measuring-accuracy.md` and `UttrflowEval` are where accuracy is defined, against a
read corpus, and the two must not share a word.

There is no baseline beside it either. The figure is near enough 100% for everybody every day, so
yesterday's copy of it was a second bar of the same length: a comparison that cannot differ tells
the reader nothing. If a figure worth comparing appears here — corrections the user made by hand,
or dictations they undid, both of which are already recorded — the comparison comes back with it.

## Pace

Words per minute is pooled across every timed dictation (total words over total seconds),
not averaged per dictation, so a two-word aside does not weigh as much as a two-minute
paragraph. `nil` when nothing was timed.

## Streak

Counted back from the most recent day, not from today, so a streak is not reported broken
at breakfast. A streak that merely reaches the oldest entry the app happens to have is not
evidence of anything: a new user's whole history is "the oldest thing kept". The "at
least — anything older has been deleted" comment only appears when the snapshot still
carries an entry retention drops, on the run's oldest day or the day before it — that entry
is the evidence that the run went further back than what is shown. A run that merely fills
the retention window proves nothing, since a new install dictating every day for its first
week fills it too. Short of that evidence, the comment reads
plainly: "days in a row".

## Comparisons

The Dictation page compares today against earlier days once there is at least one
(`comparisonFloor = 1`). The "Words dictated" figure is the total within the retention
window and is never called a lifetime total, because older words are gone and cannot be
counted.
