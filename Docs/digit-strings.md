# Digit strings and codes

Order and reference numbers, codes that mix letters and digits, times and years are where one
wrong character changes the meaning. This page holds how often the recogniser writes them exactly,
and how often the text is still exact after the clean-up rules, so a loss is put on the layer that
made it.

## The class

`DigitStringCorpus` (`Sources/UttrflowEval/DigitStringCorpus.swift`) holds 81 invented English
sentences, at least ten for each shape in `DigitShape`: long strings read digit by digit,
alphanumeric codes, "oh" against "zero", digits spoken in groups, repeated digits ("double",
"triple"), clock times, and a year followed by another number. Each case lists the spans that must
come back.

## Scoring

`DigitSpan` (`Sources/UttrflowEval/DigitStringScore.swift`) finds each span as a run of whole words
whose characters match exactly; spaces, hyphens, letter case and the punctuation around a word are
not counted, so "QX-417" matches `QX417`, but "7.45" does not match `7:45` and "4056" does not
match `405`. A case is exact when every span is there, in order.

Each case is scored twice: on the recogniser's own text (raw) and on the text
`RuleBasedTransformer` makes of it (final). Where raw is exact and final is not, the passes in the
cleaning record that touched a span are named. A shape whose final rate is below its raw rate is a
rule defect, filed against the passes the table names.

```bash
swift build --product uttrflow-eval
.build/debug/uttrflow-eval digit-strings --compute gpu
```

`--compute gpu` leaves the Neural Engine alone when other model loads are queued on it; the words
are the same model's.

## Result

Measurement pending: the table is added here by the run above, one row per shape with raw and
final exact rates and their 95% Wilson intervals. Synthesised speech in six macOS voices is weaker
evidence than recorded speech, and only English is covered.
