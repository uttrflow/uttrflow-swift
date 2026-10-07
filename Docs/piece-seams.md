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

```bash
for step in fillers repeatedPhrase stammers selfCorrection spokenPunctuation spokenEmoji \
    layoutWords numberForms contractions spacing; do
  swift run -c release uttrflow-dev seams --without "$step" --check Scripts/seam_baseline.json \
    > "seams-without-$step.txt" 2>&1
done
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

`make seam-audit` runs the probe with `--check Scripts/seam_baseline.json`. It fails when a cut
differs that the baseline does not list. A cut that comes to match is reported, and `--update`
lowers the baseline. The baseline covers two-piece cuts only.

## Measured

Rules engine, Apple M5 Pro, debug build:

| Cuts | Differing | In cases | words | punctuation | case | Run time |
|---|---|---|---|---|---|---|
| 2,717 two-piece | 1,902 | 399 | 498 | 1,401 | 3 | 687 s |

Most differences are a stop the joiner adds at the seam, which the whole never has
("We need. The final version"), or a capital after that stop.
