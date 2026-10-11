# Who owns the question mark

Two places decide whether a sentence ends in "?": the recogniser, which picks "?" or "." from
the sound, and `QuestionShape` (`Sources/UttrflowCore/Cleaning/QuestionShape.swift`), which reads
the words. One of them owns the mark, or one feature combining both feeds the existing override
gate; a second classifier is not added. This page holds the measurement that decides it.

## The measurement

`Tests/UttrflowSpeechTests/QuestionMarkOwnerProbeTests.swift` runs the shipping model on
recorded clips and scores three owners with `QuestionMarkOwnership`
(`Sources/UttrflowEval/QuestionMarkOwnership.swift`):

| Owner | Says "?" when |
|---|---|
| decoder | the recogniser's last closing mark is "?" |
| rules | `QuestionShape.asks` reads the last sentence, marks removed, as a question |
| both | both say so |

For each it prints precision, recall and the false-question rate (statements marked "?"), each
with a 95% Wilson interval, and how often decoder and rules agree. Where "?" and "." are both
among the recogniser's leaders at the closing position (see
[decoder-evidence.md](decoder-evidence.md)), the probe also keeps P("?") against P(".").

```bash
UTTRFLOW_QUESTION_CLIPS=/path/to/clips.tsv \
  swift test --disable-sandbox --filter QuestionMarkOwnerProbe
```

The listing holds one clip per line, `audio-path<TAB>the sentence as said`, the sentence ending
in its true mark. Clips are recorded human speech: a synthesiser's intonation is not evidence for
which owner reads a real question. Neither the clips nor the listing are committed.

## Deciding

The owner with the lower false-question rate at no worse recall wins; overlapping intervals mean
the clips are too few to decide, not a tie. If the decoder wins, `QuestionShape` keeps only the
lines it still reaches and the pull request counts the lines removed.

## Result

Measured on synthesised speech only: 30 questions and 30 statements, six macOS system voices
across US, UK and Indian English, 16 kHz. The statements include the comma-led "which" cases
and the "Here is the list" case that were once written as questions, and the questions include
five that only intonation marks ("You sent it already?").

| Owner | Precision | Recall | False-question rate |
|---|---|---|---|
| decoder | 0.92 (0.76-0.98, 24/26) | 0.80 (0.63-0.90, 24/30) | 0.07 (0.02-0.21, 2/30) |
| rules | 0.96 (0.80-0.99, 23/24) | 0.77 (0.59-0.88, 23/30) | 0.03 (0.01-0.17, 1/30) |
| both | 0.96 (0.80-0.99, 23/24) | 0.77 (0.59-0.88, 23/30) | 0.03 (0.01-0.17, 1/30) |

Decoder and rules agree on 58 of 60 (0.97, 0.89-0.99).

Every interval overlaps, so by the rule above this decides nothing, and synthesised intonation is
weaker evidence than recorded speech. The code keeps its current owner, `QuestionShape` behind
the existing override gate, and no line is removed. The same command on at least 30 recorded
questions and 30 recorded statements replaces this table; a clear win for the decoder there
removes the `QuestionShape` lines it no longer reaches.
