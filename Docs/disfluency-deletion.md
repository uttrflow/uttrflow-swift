# Disfluency deletion

A clean-up case's similarity blends two failures: a disfluency left in, and a meant word taken
out. This page scores them apart, by the words deleted.

## What is measured

For each case in `EvaluationCorpus.disfluency`, the spoken words are aligned against the expected
text and against the output (`DeletionScore`). Spoken words the expected text has no word for are
the deletable words; spoken words the output has no word for are the deletions. A rewritten word,
such as a numeral, is aligned as a substitution and is not a deletion.

| Rate | Meaning |
|---|---|
| precision | deletions that were deletable, over deletions |
| recall | deletable words deleted, over deletable words |
| F1 | harmonic mean of the two |
| over-deletion | words the expected text keeps that the output deleted, over those words |

Recall alone rewards deleting everything; over-deletion is the number that protects a speaker.
Each row also names the passes that removed words, from the engine's `CleaningRecord`.

## Classes

`DisfluencyClass`: filled pause, repetition, restart, self-repair (one-word trigger), editing
phrase (a trigger phrase such as "scratch that"), discourse marker kept by policy, and fluent
control (doubles said on purpose: "very very", "had had", a place name said twice,
second-language phrasing). The last two have no deletable word, so they measure over-deletion only.

## Baseline and gate

`Tests/UttrflowEvalTests/Golden/disfluency-deletion.golden` holds the rules engine's counts and
rates per class. `DisfluencyDeletionTests` fails when a line moves, and separately when any
class's over-deletion rate rises above the recorded one. Regenerate after an intended change with
`UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter DisfluencyDeletionTests`.

A seeded fault that deletes the second of every doubled word raises over-deletion (fluent
controls lose "very", "had", "that", "no") and lowers precision; the suite checks this. It can
only add correct deletions, where the rules missed a doubled word.

## Recorded on the rules engine

60 cases: precision 98.6%, recall 84.1%, over-deletion 0.3% (1 of 307 fluent words, by the
stammers pass, in a fluent control). Weakest: restart recall 71.4% (a restart inside a word with
no hyphen) and editing-phrase recall 73.3% ("make that", "wait no"). The classes and their cases
include ones the rules are expected to miss; the baseline records what they score, not a target.
