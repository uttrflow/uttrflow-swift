# The figures on Dictation and Insights

`DictationPresenter` in `Sources/UttrflowUX/MainDictationPresentation.swift` computes the
rail figures; Insights reuses the same arithmetic. The rule for every figure: nothing is
shown that was not measured. There is no "time saved" tile because Uttrflow has never
watched the user type.

## Accuracy

Both halves of the fraction count *spoken* words and both are read out of the same value:

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

## Pace

Words per minute is pooled across every timed dictation (total words over total seconds),
not averaged per dictation, so a two-word aside does not weigh as much as a two-minute
paragraph. `nil` when nothing was timed.

## Streak

Counted back from the most recent day, not from today, so a streak is not reported broken
at breakfast. A streak that reaches the oldest thing kept is a floor, and the comment says
"at least".

## Comparisons

The Dictation page compares today against earlier days once there is at least one
(`comparisonFloor = 1`). The "Words dictated" figure is the total within the retention
window and is never called a lifetime total, because older words are gone and cannot be
counted.
