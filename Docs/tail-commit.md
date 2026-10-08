# Committing the open tail while the key is held

While the key is held, finished pieces are decoded ahead and the last piece waits for key-up. How
that last piece is chosen decides the wait after release. This page records the decision between
the ways of committing it and the measurement behind it.

## The candidates

1. **Pause rule** (shipped): `SpeechWindowing.standard` ends a piece at a pause; the last piece is
   whatever follows the last cut, up to 30 s for a speaker who never pauses long enough.
2. **Agreement commit**: every 1.5 s the open piece is decoded again; the longest word prefix two
   consecutive passes agree on is committed, the piece is cut at the last committed word's end, and
   only the rest is decoded at key-up.
3. **A block-causal encoder**: excluded, since it needs a new model and a new dependency.

## The probe

`uttrflow-dev tail-probe JOBS` decodes each clip whole, under the pause rule and under agreement
commit, and prints one `TAIL` JSON line per clip and policy: the last piece's length, the decode
time after key-up (`tailWait`), the decode time spent while the key is held (`heldDecode`, the
processor-cost stand-in), the word error rate of the joined text and of the whole decode, and the
seam artefacts `TailCommit.seamArtefacts` counts at every join: a stop where the reference has
none, a capital where the reference word is lower case, a word repeated across the join, and
reference words lost next to it. Each job line is id, WAV path and reference text, tab-separated.

## The result

Measured at commit `61a991577` with a debug build on an Apple M5 Pro under a load average of 73 to
224, one pass, on speech from two system voices (no recorded human speech) reading invented
paragraphs with no pause long enough to end a piece early. Seam artefacts are stops / capitals /
repeats / lost words.

| clip | policy | audio s | last piece s | tail wait s | held decode s | decodes | WER joined | WER whole | seams | artefacts |
|---|---|---|---|---|---|---|---|---|---|---|
| voice 1, 5 s | pause | 3.7 | 3.7 | 1.02 | 0.0 | 1 | 0.000 | 0.000 | 0 | 0/0/0/0 |
| voice 1, 5 s | agreement | 3.7 | 2.3 | 0.88 | 1.9 | 3 | 0.083 | 0.000 | 1 | 0/1/1/0 |
| voice 1, 30 s | pause | 28.3 | 28.3 | 5.54 | 0.0 | 1 | 0.021 | 0.021 | 0 | 0/0/0/0 |
| voice 1, 30 s | agreement | 28.3 | 3.0 | 0.96 | 20.8 | 19 | 0.052 | 0.021 | 13 | 0/1/3/0 |
| voice 1, 120 s | pause | 100.9 | 27.4 | 6.07 | 16.7 | 4 | 0.018 | 0.012 | 3 | 0/0/0/0 |
| voice 1, 120 s | agreement | 100.9 | 2.3 | 0.95 | 100.4 | 68 | 0.029 | 0.012 | 50 | 0/3/5/0 |
| voice 2, 5 s | pause | 3.8 | 3.8 | 1.65 | 0.0 | 1 | 0.000 | 0.000 | 0 | 0/0/0/0 |
| voice 2, 5 s | agreement | 3.8 | 2.5 | 1.42 | 2.9 | 3 | 0.083 | 0.000 | 1 | 0/1/1/0 |
| voice 2, 30 s | pause | 30.3 | 10.4 | 4.07 | 7.1 | 2 | 0.021 | 0.021 | 1 | 0/0/0/0 |
| voice 2, 30 s | agreement | 30.3 | 1.7 | 1.26 | 93.0 | 21 | 0.042 | 0.021 | 10 | 1/4/2/0 |
| voice 2, 120 s | pause | 105.8 | 15.9 | 5.15 | 28.2 | 5 | 0.015 | 0.015 | 4 | 0/0/0/0 |
| voice 2, 120 s | agreement | 105.8 | 3.9 | 2.54 | 355.7 | 71 | 0.029 | 0.015 | 37 | 1/4/3/0 |

1. **Agreement commit shortens the wait**: the last piece is under 4 s on every clip, and the tail
   wait falls from 4 to 6 s to 1 to 2.5 s on 30 s and longer clips.
2. **It costs accuracy at the joins**: the joined word error rate doubles against the whole decode,
   from repeated words and capitals at cuts placed inside a clause, and nothing in the pause rule's
   rows comes close.
3. **It costs processor time**: three to twelve times the decode work while the key is held.

## The decision

The pause rule stays, and agreement commit does not ship. Agreement commit misses the accuracy bar
(joined word error rate within the evaluation interval of the whole decode) on every clip, which
outweighs a shorter wait. No product code changes, so there is no losing implementation to delete.
What would reopen it, in [decisions.md](decisions.md) terms: an agreement rule whose joined word
error rate matches the whole decode on this probe, for example committing only up to a word that
ends a clause or holding back the last agreed word.

**Limits.** Debug build, loaded Mac, one pass, two synthetic voices, no energy reading
(`powermetrics` needs administrator rights; `heldDecode` stands in). A release build on an idle Mac
over public read speech replaces the table.
