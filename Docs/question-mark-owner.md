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

Not yet measured on recorded speech. A run on six synthesised takes proves only that the
harness runs end to end; synthesised intonation decides nothing.
