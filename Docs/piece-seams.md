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
