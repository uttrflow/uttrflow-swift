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

81 cases in six macOS voices (Samantha, Daniel, Karen, Rishi, Moira, Tessa), shipping model on
the GPU plan, rules engine with default steps. Synthesised speech only; recorded speech was not
measured.

| Shape | Raw exact | Final exact | Passes that lost a span |
|---|---|---|---|
| long-string | 1.00 (0.95-1.00, 72/72) | 1.00 (0.95-1.00, 72/72) | - |
| alphanumeric | 0.97 (0.90-0.99, 70/72) | 0.97 (0.90-0.99, 70/72) | - |
| oh-for-zero | 0.90 (0.81-0.95, 65/72) | 0.90 (0.81-0.95, 65/72) | - |
| grouped | 0.98 (0.92-1.00, 65/66) | 0.98 (0.92-1.00, 65/66) | - |
| repeated | 0.71 (0.59-0.80, 51/72) | 0.86 (0.76-0.92, 62/72) | - |
| time | 0.42 (0.31-0.54, 28/66) | 0.85 (0.74-0.92, 56/66) | - |
| year-then-number | 1.00 (0.94-1.00, 66/66) | 1.00 (0.94-1.00, 66/66) | - |

No shape is worse after the rules, so no pass is blamed. The rules recover spans in two shapes:
"double seven three" and "triple one" become `773` and `111`, and a time written "7.35" becomes
`7:35`. What stays wrong is the recogniser's: a time written as a decimal or run together ("2.40",
"240"), "double two" heard as "double too", "five oh six" written "5.06", and a repeated pair
written as a decimal ("3.3").
