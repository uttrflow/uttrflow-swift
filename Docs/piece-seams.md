# Piece seams

A dictation is recognised in pieces, cut at pauses. Each piece is cleaned on its own, then
`PieceJoiner.join` joins the pieces and `finishMessage` runs the message passes once over the whole.
The property: for any cut, cleaning the pieces and joining them writes what cleaning the
unbroken transcript writes.

## The probe

`uttrflow-dev seams` takes every case in `EvaluationCorpus.all` and cuts it at every word boundary
into two pieces. It sends each cut through `DictationPipeline.clean` under the rules engine, with
the case's own screen context, and compares the result with the same call on the uncut transcript.
`--three` also cuts at every pair of boundaries. `--list` prints each differing cut, and the count
is split into three kinds:

| Kind | Meaning |
|---|---|
| words | the words themselves differ |
| punctuation | the same words with different marks, sometimes with a capital the marks brought |
| case | only the letters' case differs |

Cuts are made at every word boundary, not only where `SpeechWindowing` would cut. A pause can
fall between any two words, so every boundary is a real cut.

## Which pass makes a cut differ

`--without <step>` switches one cleaning step off for the whole run (repeat it for several).
Run with `--check Scripts/seam_baseline.json`: the recorded cuts that now match are the ones that
step makes differ, which is the list the move of seam-sensitive passes to the message stage
works from. Only the steps a user can switch off are accepted (`CleaningSteps.offered`); the
pause stop and spoken casing always run.

`--attribute` answers it for every differing cut in one run: for each cut it switches the running
steps off one at a time, in run order, and names the first whose removal makes pieces and whole
agree. A cut no single step accounts for is counted as `join`: the joiner's seam mark, or a pass
that always runs.

```bash
swift run -c release uttrflow-dev seams --attribute
```

`--sample N` cuts only every Nth corpus case, the same cases on every run, and a `--check` then
compares only those cases' recorded cuts. Attribution is the cuts that differ with every step on
and match with the step off.

Measured with `--sample 5 --list` (one case in five, 1,193 two-piece cuts), release build,
Apple M5 Pro under load, about 45 s a run:

| Step off | Differing | Matched by switching it off | Newly differing |
|---|---|---|---|
| none | 612 | - | - |
| fillers | 614 | 2 | 4 |
| repeatedPhrase | 611 | 1 | 0 |
| stammers | 610 | 3 | 1 |
| selfCorrection | 609 | 4 | 1 |
| spokenPunctuation | 611 | 5 | 4 |
| spokenEmoji | 612 | 0 | 0 |
| layoutWords | 622 | 2 | 12 |
| numberForms | 607 | 5 | 0 |
| contractions | 612 | 0 | 0 |
| spacing | 612 | 0 | 0 |

The offered steps account for at most 22 of the 612 differing cuts. 539 of the 612 have more
sentence stops in the joined pieces than in the whole: the stop the joiner writes at a seam,
which no offered step controls. Moving offered steps to the message stage therefore cannot bring
the count near zero; the stop at the seam is the cause to remove. The full run, every case, is
the loop above without `--sample`.

## The gate

`make seam-audit` runs the probe with `--check Scripts/seam_baseline.json`, and `make verify`
runs it after `build`. It fails when a cut differs that the baseline does not list. A cut that comes to match is reported, and `--update`
lowers the baseline; it refuses a cut the baseline does not list unless `--after-merge` says the
cut came to differ with `main`. The baseline covers two-piece cuts only.

## Measured

Rules engine, Apple M5 Pro. The cases run side by side, one pipeline each; the count is the same
as a one-at-a-time run.

| Corpus | Cuts | Differing | In cases | words | punctuation | case | Run time |
|---|---|---|---|---|---|---|---|
| before FD.3 | 2,717 two-piece | 1,902 | 399 | 498 | 1,401 | 3 | 687 s, debug, one at a time |
| after FD.3 | 6,349 two-piece | 3,539 | 688 | 478 | 3,058 | 3 | 48 s release, 237 s debug |

The corpus grew between the two rows, so the totals are not a before and after of FD.3; the
`words` column, which fell from 498 to 478 on a larger corpus, is the comparable one.

First pass whose removal makes the cut match, after FD.3:

| Pass | Cuts |
|---|---|
| join (no single step) | 3,420 |
| spokenPunctuation | 51 |
| layoutWords | 30 |
| selfCorrection | 13 |
| numberForms | 8 |
| repeatedPhrase | 8 |
| stammers | 5 |
| fillers | 4 |

Most differences are a stop the joiner adds at the seam, which the whole never has
("We need. The final version"), or a capital after that stop.

## Seam artefacts per seam

`SeamScore(whole:pieces:)` (in `UttrflowEval`) scores one clip's piece texts against the same
speech written in one pass. It aligns the two by word match (`WordErrorRate.measure`) and gives
each seam a `SeamTally`: stray stops (the piece before ends in `.`, `!` or `?` where the whole
does not), wrong capitals (the first word after differs in case), and words duplicated or
dropped in the run of edits that touches the seam. Edits away from a seam are not counted.
