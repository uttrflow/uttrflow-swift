# Pause gaps per speaker

Sentence and paragraph rules that read a pause need a way to call a gap a break. A fixed length is
wrong for a speaker who breaks in 500 ms, and a gap measured from the signal has a floor the
detector sets. This page records the gap distribution of synthetic speakers, and whether the
rank of a gap among the speaker's own gaps calls breaks better than a fixed length. The gap itself
is the audio measure that [pause-timing.md](pause-timing.md#decision) chose.

## The probe

`uttrflow-eval gap-distribution` speaks the six long-form dictations with `say` in four voices
at three paces, over room noise at -60 dBFS. Each pace fixes the rate, the silence at a
hesitation inside a sentence and the silence at a break the case marks (`pausedAfter`):

| Pace | Rate | Hesitation ms | Break ms |
|---|---|---|---|
| fast | 230 words a minute | none | 500 |
| ordinary | the voice's own | 250 | 1,000 |
| slow | 120 words a minute | 900 | 1,800 |

The phrases between silences are cut to their speech and joined, so the length of every built
silence is exact and every break is known. The gaps are the quiet runs between speech that
`VoiceActivity.quietRuns` finds in the joined clip: every run, including the short ones inside a
phrase. A run that holds a built break is a break; every other run is not.

The rank of a gap is how many spreads it lies above the median of the speaker's gaps heard so far
in this dictation, after the detector's floor of 40 ms (the zero-pause row of the pause-timing
table) is taken off. The spread is 1.4826 times the median absolute deviation, never below 20 ms.
No rank is given before five gaps are heard. The rank rule calls a break at 3 spreads, a value
chosen before the run; the other rules in the table are shown so the choice can be checked against
its neighbours. The fixed rule is 700 ms.

```bash
swift run uttrflow-eval gap-distribution
```

## Measured

Debug build, 24 dictations per pace, synthetic speech only: no recorded speech was used, so the
hand-marked recorded clips the question also asks for are not in these tables. Paces are built by
choosing the silences, so they show what each rule does with a speaker of that rhythm, not how
common the rhythm is.

Gap distribution by speaker

| Speaker | Dictations | Other gaps | Other median ms | Other 90th ms | Other longest ms | Breaks | Break shortest ms | Break median ms |
|---|---|---|---|---|---|---|---|---|
| Samantha fast | 6 | 137 | 40 | 160 | 500 | 25 | 480 | 500 |
| Samantha ordinary | 6 | 140 | 40 | 260 | 380 | 25 | 980 | 1000 |
| Samantha slow | 6 | 146 | 40 | 900 | 1040 | 25 | 1780 | 1800 |
| Daniel fast | 6 | 131 | 40 | 120 | 400 | 25 | 480 | 500 |
| Daniel ordinary | 6 | 153 | 40 | 260 | 420 | 25 | 980 | 1000 |
| Daniel slow | 6 | 146 | 60 | 900 | 1040 | 25 | 1780 | 1800 |
| Karen fast | 6 | 113 | 40 | 180 | 440 | 25 | 480 | 500 |
| Karen ordinary | 6 | 106 | 180 | 260 | 340 | 25 | 980 | 1000 |
| Karen slow | 6 | 102 | 880 | 900 | 1000 | 25 | 1780 | 1800 |
| Rishi fast | 6 | 160 | 40 | 100 | 580 | 25 | 480 | 500 |
| Rishi ordinary | 6 | 182 | 40 | 240 | 380 | 25 | 980 | 1000 |
| Rishi slow | 6 | 180 | 40 | 900 | 1060 | 25 | 1780 | 1800 |

Break F1 by rule and pace

| Rule | fast | ordinary | slow | All |
|---|---|---|---|---|
| fixed 400 ms | 0.97 | 0.99 | 0.49 | 0.73 |
| fixed 500 ms | 0.84 | 1.00 | 0.49 | 0.70 |
| fixed 700 ms | 0.00 | 1.00 | 0.49 | 0.56 |
| fixed 1000 ms | 0.00 | 0.91 | 0.95 | 0.74 |
| rank 2 spreads | 0.51 | 0.61 | 0.32 | 0.49 |
| rank 3 spreads | 0.57 | 0.35 | 0.29 | 0.40 |
| rank 4 spreads | 0.59 | 0.35 | 0.30 | 0.41 |
| rank 6 spreads | 0.64 | 0.31 | 0.30 | 0.41 |

Rank 3 spreads less fixed 700 ms, per dictation: -0.092 F1, paired 95% bound 0.127.

## Reading the tables

- The floor holds. The median of the gaps that are not breaks is 40 ms for nine of twelve
  speakers, the detector's floor; a gap near 40 ms is no pause. The three exceptions are Daniel
  slow (60 ms) and Karen ordinary and slow (180 and 880 ms), where few gaps between words are
  found and the built hesitations are most of what is. The probe does not establish why.
- A fixed length is wrong for some speaker whatever its value. 700 ms finds no fast break (F1
  0.00) and, for the slow speaker, calls the 900 ms hesitations too (F1 0.49). The best fixed
  length differs by pace: 400 ms for fast, 500 to 700 ms for ordinary, 1,000 ms for slow. The
  problem the question names is real on this set.
- The rank of a gap among the speaker's own gaps does not fix it. It calls 3 spreads above the
  median, which is every hesitation as well as every break, because both lie far above gaps of
  40 ms. It is 0.092 F1 worse than the fixed 700 ms per dictation, and worse than the best fixed
  length in every column. The paired bound of 0.127 means the difference is not
  established either way; no rank cut from 2 to 6 spreads reaches the fixed lengths of the table's
  best rows.
- The floor was taken off but did not decide anything here: the breaks are 400 ms or more, far
  above 40 ms.

## Decision

**The rank of a gap against the median and spread of the speaker's gaps is not adopted as the
break rule on this evidence.** It does not improve break F1 over a fixed length by more than the
paired bound, so the acceptance test is not met on synthetic speech. What the tables do support
is that a fixed length cannot serve every speaker, so a speaker-relative rule remains worth
having. What a better rule must separate is a hesitation from a break, which needs more than the
position of a gap among all gaps: the gaps that carry a sentence or paragraph end, or the length
of the pause relative to the speaker's own hesitations, not to their word spacing.

The cutter's pause threshold (the second piece of the parent change) and the pause rules that
would consume a rank both wait for a rule that passes this table.

Reopened by: a run on recorded speech from several people, or a rank that separates hesitations
from breaks with a break F1 above the best fixed length by more than its paired bound.
